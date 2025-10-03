//
//  MirrorModeView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct MirrorModeView: View {
    @Query private var mirrorCards: [AIMirrorCard]
    @Query private var goals: [Goal]
    @StateObject private var userContextService = UserContextService.shared

    @Environment(\.modelContext) private var modelContext

    private var aiService: AIService { AIService.shared }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                MirrorIntroHeader(lastUpdated: latestSnapshotDate, totalCards: mirrorCards.count)

                if let summary = themeSummary {
                    MirrorThemeOverview(summary: summary)
                }

                if !timelineGroups.isEmpty {
                    MirrorTimelineSection(groups: timelineGroups)
                }
                
                if mirrorCards.isEmpty {
                    EmptyMirrorView()
                } else {
                    MirrorActiveCardsSection(cards: sortedMirrorCards)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(Color.blue.opacity(0.05))
        .task {
            await generateMirrorCards()
        }
    }
    
    private var sortedMirrorCards: [AIMirrorCard] {
        mirrorCards.sorted {
            (latestSnapshot(for: $0)?.capturedAt ?? $0.createdAt) >
            (latestSnapshot(for: $1)?.capturedAt ?? $1.createdAt)
        }
    }

    private var latestSnapshotDate: Date? {
        mirrorCards
            .compactMap { latestSnapshot(for: $0)?.capturedAt }
            .max()
    }

    private var themeSummary: MirrorThemeSummary? {
        guard !mirrorCards.isEmpty else { return nil }

        let cards = mirrorCards
        let confidences = cards.map { $0.confidence }
        let averageConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)

        let tones = cards.compactMap { $0.emotionalTone?.capitalized }
        let dominantTone = mostFrequentValue(in: tones)

        let allInsights = cards.flatMap { $0.insights }
            .filter { !$0.trimmed.isEmpty }
        let topInsights = topValues(in: allInsights, limit: 3)

        let trendDelta = confidenceDelta()

        return MirrorThemeSummary(
            dominantTone: dominantTone,
            averageConfidence: averageConfidence,
            highlightInsights: topInsights,
            confidenceDelta: trendDelta,
            activeCardCount: cards.count
        )
    }

    private var timelineGroups: [MirrorTimelineGroup] {
        let calendar = Calendar.current

        let entries = mirrorCards.flatMap { card in
            card.snapshots.map { snapshot in
                MirrorTimelineEntry(
                    id: snapshot.id,
                    snapshot: snapshot,
                    cardTitle: card.title
                )
            }
        }
        .sorted { $0.snapshot.capturedAt > $1.snapshot.capturedAt }

        let recentEntries = Array(entries.prefix(24))

        let grouped = Dictionary(grouping: recentEntries) { entry in
            calendar.startOfDay(for: entry.snapshot.capturedAt)
        }

        return grouped
            .map { date, entries in
                MirrorTimelineGroup(
                    id: date,
                    date: date,
                    entries: entries.sorted { $0.snapshot.capturedAt > $1.snapshot.capturedAt }
                )
            }
            .sorted { $0.date > $1.date }
    }

    private func latestSnapshot(for card: AIMirrorCard) -> AIMirrorSnapshot? {
        card.snapshots.max(by: { $0.capturedAt < $1.capturedAt })
    }

    private func confidenceDelta() -> Double {
        let latestValues = mirrorCards.map { latestSnapshot(for: $0)?.confidence ?? $0.confidence }
        guard !latestValues.isEmpty else { return 0 }

        let previousValues = mirrorCards.compactMap { card -> Double? in
            let sorted = card.snapshots.sorted { $0.capturedAt > $1.capturedAt }
            guard sorted.count >= 2 else { return nil }
            return sorted[1].confidence
        }

        guard !previousValues.isEmpty else { return 0 }

        let latestAverage = latestValues.reduce(0, +) / Double(latestValues.count)
        let previousAverage = previousValues.reduce(0, +) / Double(previousValues.count)
        return latestAverage - previousAverage
    }

    private func mostFrequentValue(in values: [String]) -> String? {
        guard !values.isEmpty else { return nil }

        let counts = values.reduce(into: [:]) { partialResult, value in
            partialResult[value, default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func topValues(in values: [String], limit: Int) -> [String] {
        guard !values.isEmpty else { return [] }

        let counts = values.reduce(into: [:]) { partialResult, value in
            partialResult[value, default: 0] += 1
        }

        return counts.sorted(by: { $0.value > $1.value }).prefix(limit).map { $0.key }
    }
    
    private func generateMirrorCards() async {
        let context = await userContextService.buildContext(from: goals)

        // Generate AI interpretation for each active goal
        for goal in goals.filter({ $0.isActive }) {
            // Check if mirror card already exists
            let existingCard = mirrorCards.first { $0.relatedGoalId == goal.id }

            do {
                let response = try await aiService.generateMirrorCard(for: goal, context: context)

                let insights = response.insights ?? []

                await MainActor.run {
                    if let existingCard = existingCard {
                        // Update existing mirror card
                        existingCard.aiInterpretation = response.aiInterpretation
                        existingCard.suggestedActions = response.suggestedActions
                        existingCard.confidence = response.confidence
                        existingCard.emotionalTone = response.emotionalTone
                        existingCard.insights = insights

                        recordSnapshot(for: existingCard, with: response, relatedGoalId: goal.id)
                    } else {
                        // Create new mirror card
                        let newMirrorCard = AIMirrorCard(
                            title: goal.title,
                            interpretation: response.aiInterpretation,
                            relatedGoalId: goal.id
                        )
                        newMirrorCard.suggestedActions = response.suggestedActions
                        newMirrorCard.confidence = response.confidence
                        newMirrorCard.emotionalTone = response.emotionalTone
                        newMirrorCard.insights = insights

                        modelContext.insert(newMirrorCard)
                        recordSnapshot(for: newMirrorCard, with: response, relatedGoalId: goal.id)
                    }
                }

                print("🪞 Generated mirror card for: \(goal.title)")
            } catch {
                print("❌ Failed to generate mirror card: \(error)")
            }
        }
    }

    @MainActor
    private func recordSnapshot(
        for card: AIMirrorCard,
        with response: MirrorCardResponse,
        relatedGoalId: UUID?
    ) {
        let snapshot = AIMirrorSnapshot(
            aiInterpretation: response.aiInterpretation,
            suggestedActions: response.suggestedActions,
            confidence: response.confidence,
            emotionalTone: response.emotionalTone,
            insights: response.insights ?? [],
            relatedGoalId: relatedGoalId
        )

        snapshot.capturedAt = Date()
        modelContext.insert(snapshot)
        card.snapshots.append(snapshot)

        // Keep most recent 20 snapshots to avoid unbounded growth
        if card.snapshots.count > 20 {
            card.snapshots
                .sorted { $0.capturedAt > $1.capturedAt }
                .dropFirst(20)
                .forEach { oldSnapshot in
                    modelContext.delete(oldSnapshot)
                }
        }
    }
}

private struct MirrorThemeSummary {
    let dominantTone: String?
    let averageConfidence: Double
    let highlightInsights: [String]
    let confidenceDelta: Double
    let activeCardCount: Int
}

private struct MirrorTimelineGroup: Identifiable {
    let id: Date
    let date: Date
    let entries: [MirrorTimelineEntry]
}

private struct MirrorTimelineEntry: Identifiable {
    let id: UUID
    let snapshot: AIMirrorSnapshot
    let cardTitle: String
}

private func mirrorToneColor(_ tone: String?) -> Color {
    guard let tone else { return .blue }

    switch tone.lowercased() {
    case "motivated": return .green
    case "focused": return .blue
    case "overwhelmed": return .orange
    case "uncertain": return .purple
    case "paused": return .gray
    default: return .blue
    }
}

private struct MirrorIntroHeader: View {
    let lastUpdated: Date?
    let totalCards: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Observatory")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Step into how your assistant is reading the room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Mirror cards")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalCards)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }

            Divider()
                .blendMode(.overlay)

            HStack(spacing: 12) {
                Label {
                    if let lastUpdated {
                        Text("Last reflection \(lastUpdated.timeAgo)")
                    } else {
                        Text("No reflections yet")
                    }
                } icon: {
                    Image(systemName: "sparkles.rectangle.stack")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Label("Live", systemImage: "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct MirrorThemeOverview: View {
    let summary: MirrorThemeSummary

    private var confidencePercent: Int {
        Int((summary.averageConfidence * 100).rounded())
    }

    private var deltaText: String {
        let percentage = Int((summary.confidenceDelta * 100).rounded())
        if percentage == 0 { return "holding steady" }
        return percentage > 0 ? "+\(percentage)% vs last check" : "\(percentage)% vs last check"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today the AI feels")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(alignment: .center, spacing: 20) {
                MetricTile(
                    title: "Tone",
                    value: summary.dominantTone ?? "Observing",
                    caption: "Dominant signal"
                )

                MetricTile(
                    title: "Confidence",
                    value: "\(confidencePercent)%",
                    caption: deltaText
                )

                MetricTile(
                    title: "Mirrors",
                    value: "\(summary.activeCardCount)",
                    caption: "Active goals reflected"
                )
            }

            if !summary.highlightInsights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Highlights")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(summary.highlightInsights, id: \.self) { insight in
                            Text(insight)
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct MirrorTimelineSection: View {
    let groups: [MirrorTimelineGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Insight Timeline")
                    .font(.headline)
                Spacer()
                Label("Newest first", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(groups) { group in
                        MirrorTimelineDayView(group: group)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

private struct MirrorTimelineDayView: View {
    let group: MirrorTimelineGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.entries) { entry in
                    MirrorTimelineCard(entry: entry)
                }
            }
            .padding(16)
            .frame(width: 260)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct MirrorTimelineCard: View {
    let entry: MirrorTimelineEntry

    private var toneText: String {
        entry.snapshot.emotionalTone?.capitalized ?? "Neutral"
    }

    private var toneColor: Color {
        mirrorToneColor(entry.snapshot.emotionalTone)
    }

    private var confidencePercent: Int {
        Int((entry.snapshot.confidence * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.cardTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(entry.snapshot.aiInterpretation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                Label("\(confidencePercent)%", systemImage: "gauge.medium")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(toneText, systemImage: "sparkle")
                    .font(.caption2)
                    .foregroundStyle(toneColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(toneColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(entry.snapshot.capturedAt.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !entry.snapshot.insights.isEmpty {
                Divider()
                    .blendMode(.overlay)

                ForEach(entry.snapshot.insights.prefix(2), id: \.self) { insight in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(toneColor.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)

                        Text(insight)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

}

private struct MirrorActiveCardsSection: View {
    let cards: [AIMirrorCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Mirrors")
                .font(.headline)

            LazyVStack(spacing: 16) {
                ForEach(cards) { card in
                    MirrorCardView(card: card)
                }
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.panelBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
struct MirrorCardView: View {
    let card: AIMirrorCard
    @State private var isExpanded = false

    private var emotionalToneColor: Color {
        mirrorToneColor(card.emotionalTone)
    }

    private var toneText: String {
        card.emotionalTone?.capitalized ?? "Observing"
    }

    private var confidenceText: String {
        let percentage = Int(card.confidence * 100)
        return "\(percentage)% understanding"
    }

    private var latestSnapshot: AIMirrorSnapshot? {
        card.snapshots.max(by: { $0.capturedAt < $1.capturedAt })
    }

    private var recentSnapshots: [AIMirrorSnapshot] {
        card.snapshots.sorted(by: { $0.capturedAt > $1.capturedAt })
    }

    private var lastUpdatedText: String {
        (latestSnapshot?.capturedAt ?? card.createdAt).timeAgo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and emotional indicator
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)

                    Text("AI Analysis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Emotional tone indicator
                HStack(spacing: 4) {
                    Label(toneText, systemImage: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(emotionalToneColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(emotionalToneColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // AI Interpretation - Core insight
            if !card.aiInterpretation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(.blue.opacity(0.7))
                        Text("Understanding")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue.opacity(0.9))
                    }

                    Text(card.aiInterpretation)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(isExpanded ? nil : 2)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Confidence and timestamp
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.medium")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.7))
                    Text(confidenceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(lastUpdatedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Suggested Actions
            if !card.suggestedActions.isEmpty && (isExpanded || card.suggestedActions.count <= 2) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow.opacity(0.8))
                        Text("Suggestions")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }

                    ForEach(card.suggestedActions.prefix(isExpanded ? card.suggestedActions.count : 2), id: \.self) { action in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.6))
                                .padding(.top, 1)
                            Text(action)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if card.suggestedActions.count > 2 && !isExpanded {
                        Text("+\(card.suggestedActions.count - 2) more suggestions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                    }
                }
            }

            // Insights
            if !card.insights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insights the AI is watching")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(card.insights.prefix(isExpanded ? card.insights.count : 2), id: \.self) { insight in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(emotionalToneColor.opacity(0.5))
                                .padding(.top, 6)

                            Text(insight)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if card.insights.count > 2 && !isExpanded {
                        Text("+\(card.insights.count - 2) more signals")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                    }
                }
            }

            // Recent reflections history (when expanded)
            if isExpanded && !recentSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent reflections")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(recentSnapshots.prefix(3)) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(snapshot.capturedAt.timeAgo)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                Spacer()

                                Text("\(Int(snapshot.confidence * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(snapshot.aiInterpretation)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.blue.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.12),
                    Color.blue.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }
    }
}

struct EmptyMirrorView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            // Animated brain icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 8) {
                Text("AI Insights")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Text("How AI Understands Your Goals")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Active goals will appear here with AI insights and analysis")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            // Feature highlights
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "lightbulb.fill", text: "AI-powered insights", color: .yellow)
                FeatureRow(icon: "gauge.medium", text: "Understanding confidence", color: .blue)
                FeatureRow(icon: "sparkle", text: "Personalized suggestions", color: .purple)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding()
        .onAppear {
            isAnimating = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color.opacity(0.8))
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
