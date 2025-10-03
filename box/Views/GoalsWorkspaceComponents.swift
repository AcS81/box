import SwiftUI
import SwiftData

struct KanbanBoardView: View {
    let goals: [Goal]

    private var columns: [(state: Goal.ActivationState, goals: [Goal])] {
        let states: [Goal.ActivationState] = [.draft, .active, .completed]
        return states.map { state in
            let filtered = goals
                .filter { $0.activationState == state }
                .sorted { lhs, rhs in
                    if lhs.effectiveSortOrder == rhs.effectiveSortOrder {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.effectiveSortOrder < rhs.effectiveSortOrder
                }
            return (state, filtered)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(columns, id: \.state) { column in
                    KanbanColumn(state: column.state, goals: column.goals)
                        .frame(width: 320)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct KanbanColumn: View {
    let state: Goal.ActivationState
    let goals: [Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if goals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(hintMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(goals) { goal in
                        GoalCardView(goal: goal)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .liquidGlassCard(cornerRadius: 34, tint: tint.opacity(0.26))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Spacer()

            Text("\(goals.count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tint.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var title: String {
        switch state {
        case .draft: return "Drafts"
        case .active: return "Active"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }

    private var icon: String {
        switch state {
        case .draft: return "tray.full"
        case .active: return "bolt.fill"
        case .completed: return "checkmark.seal.fill"
        case .archived: return "archivebox"
        }
    }

    private var tint: Color {
        switch state {
        case .draft: return .orange
        case .active: return .green
        case .completed: return .blue
        case .archived: return .gray
        }
    }

    private var emptyMessage: String {
        switch state {
        case .draft: return "No drafts waiting."
        case .active: return "No active goals."
        case .completed: return "Nothing completed yet."
        case .archived: return "No archived cards."
        }
    }

    private var hintMessage: String {
        switch state {
        case .draft: return "Draft with the assistant to queue your next moves."
        case .active: return "Activate a goal to keep momentum moving."
        case .completed: return "Finish a goal to celebrate wins here."
        case .archived: return "Archive goals you no longer need." 
        }
    }
}

struct GanttTimelineView: View {
    let goals: [Goal]

    @State private var selectedHorizon: Horizon = .seven
    @State private var aiEntries: [UUID: [GoalTimelineEntry]] = [:]
    @State private var isLoadingInsights = false
    @State private var insightsError: String?
    @State private var aiHeadline: String?

    private var horizonInterval: DateInterval {
        DateInterval(start: range.start, end: range.end)
    }

    private var insightTaskKey: String {
        let horizonKey = selectedHorizon.rawValue
        let signature = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)-\(Int($0.updatedAt.timeIntervalSince1970))" }
            .joined(separator: "|")
        return "\(horizonKey)|\(signature)"
    }

    private var goalSections: [GoalTimelineSection] {
        goals.compactMap { goal in
            let entries = GoalTimelineBuilder.entries(
                for: goal,
                in: horizonInterval,
                referenceDate: horizonInterval.start
            )

            if entries.isEmpty, !goalFallsWithinHorizon(goal) {
                return nil
            }

            return GoalTimelineSection(goal: goal, entries: entries)
        }
        .sorted { lhs, rhs in
            lhs.nextMilestone < rhs.nextMilestone
        }
    }

    private func goalFallsWithinHorizon(_ goal: Goal) -> Bool {
        let start = goal.activatedAt ?? goal.createdAt
        let impliedEnd: Date = {
            if let target = goal.targetDate { return target }
            return Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start.addingTimeInterval(14 * 86_400)
        }()

        return impliedEnd >= horizonInterval.start && start <= horizonInterval.end
    }

    @MainActor
    private func refreshTimelineInsights() async {
        guard !goals.isEmpty else {
            aiEntries = [:]
            insightsError = nil
            aiHeadline = nil
            isLoadingInsights = false
            return
        }

        isLoadingInsights = true
        insightsError = nil

        let horizon = horizonInterval
        let service = GoalTimelineIntelligenceService.shared
        var newEntries: [UUID: [GoalTimelineEntry]] = [:]
        var aggregatedHeadline: String?
        var encounteredRecoverableError = false

        for goal in goals {
            let baselineEntries = GoalTimelineBuilder.entries(
                for: goal,
                in: horizon,
                referenceDate: horizon.start
            )

            guard !baselineEntries.isEmpty else { continue }

            do {
                let result = try await service.enrichEntries(
                    baselineEntries,
                    for: goal,
                    horizon: horizon,
                    portfolio: goals
                )

                if !result.entries.isEmpty {
                    newEntries[goal.id] = result.entries
                }

                if aggregatedHeadline == nil,
                   let headline = result.portfolioHeadline?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !headline.isEmpty {
                    aggregatedHeadline = headline
                }
            } catch {
                if case AIError.noAPIKey = error {
                    insightsError = "Add an OpenAI key to unlock intelligent timelines."
                    isLoadingInsights = false
                    aiHeadline = nil
                    return
                }

                encounteredRecoverableError = true
                print("❌ Timeline insights error: \(error.localizedDescription)")
            }
        }

        if !newEntries.isEmpty {
            aiEntries = newEntries
        } else if !encounteredRecoverableError {
            aiEntries = [:]
        }

        aiHeadline = aggregatedHeadline

        if encounteredRecoverableError {
            if newEntries.isEmpty {
                insightsError = "Timeline intelligence is temporarily unavailable."
            } else {
                insightsError = "Some timeline insights may be missing."
            }
        } else {
            insightsError = nil
        }

        isLoadingInsights = false
    }

    private var range: (start: Date, end: Date) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: selectedHorizon.rawValue, to: startOfToday)
            ?? startOfToday.addingTimeInterval(Double(selectedHorizon.rawValue) * 86_400)
        return (startOfToday, end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            timelineHeader

            if !goals.isEmpty {
                if isLoadingInsights {
                    Label("Asking AI what each block can unlock…", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .accessibilityLabel("AI is analyzing the timeline")
                } else if let insightsError {
                    Label(insightsError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                } else if let aiHeadline, !aiHeadline.isEmpty {
                    Label(aiHeadline, systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.cyan.opacity(0.12))
                        )
                        .padding(.horizontal)
                } else if !aiEntries.isEmpty {
                    Label("AI suggests how to use these windows.", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }

            if goalSections.isEmpty {
                Text(goals.isEmpty ? "No scheduled goals yet. Add target dates to populate the timeline." : "Nothing scheduled in this horizon. Try another timeframe or activate more goals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 18) {
                    ForEach(goalSections) { section in
                        GanttRow(
                            goal: section.goal,
                            rangeStart: range.start,
                            rangeEnd: range.end,
                            entries: aiEntries[section.goal.id] ?? section.entries
                        )
                    }
                }
            }
        }
        .padding(26)
        .liquidGlassCard(cornerRadius: 34, tint: Color.cyan.opacity(0.24))
        .task(id: insightTaskKey) {
            await refreshTimelineInsights()
        }
    }

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Roadmap horizon")
                    .font(.headline)
                Spacer()
                Picker("Roadmap horizon", selection: $selectedHorizon) {
                    ForEach(Horizon.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.cyan.opacity(0.2), Color.blue.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 6)
                        .clipShape(Capsule())

                    HStack {
                        Text(Self.dateFormatter.string(from: range.start))
                        Spacer()
                        Text(Self.dateFormatter.string(from: range.end))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: width)
                    .offset(y: 10)
                }
            }
            .frame(height: 28)
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    enum Horizon: Int, CaseIterable, Identifiable {
        case three = 3
        case seven = 7
        case twentyOne = 21

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .three: return "3d"
            case .seven: return "7d"
            case .twentyOne: return "21d"
            }
        }
    }
}

private struct GanttRow: View {
    @Bindable var goal: Goal
    let rangeStart: Date
    let rangeEnd: Date
    let entries: [GoalTimelineEntry]

    private enum RowStyle {
        case event
        case progress
    }

    private var rowStyle: RowStyle {
        if goal.kind == .event {
            return .event
        }

        if entries.allSatisfy({ $0.kind == .event }) && !entries.isEmpty {
            return .event
        }

        return .progress
    }

    private var primaryEntry: GoalTimelineEntry? {
        entries.sorted {
            if $0.startDate == $1.startDate {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.startDate < $1.startDate
        }.first
    }

    private var primaryInsight: GoalTimelineEntryIntelligence? {
        entries.compactMap(\.intelligence).first
    }

    private var eventEntries: [GoalTimelineEntry] {
        entries.filter { $0.kind == .event }
    }

    private var goalStart: Date { goal.activatedAt ?? goal.createdAt }

    private var goalEnd: Date {
        if let target = goal.targetDate, target > goalStart {
            return target
        }
        return Calendar.current.date(byAdding: .day, value: 14, to: goalStart) ?? goalStart.addingTimeInterval(60 * 60 * 24 * 14)
    }

    private var progressPercent: Int { max(0, min(100, Int(goal.progress * 100))) }

    private var digestTint: Color {
        switch rowStyle {
        case .event: return .blue
        case .progress: return .purple
        }
    }

    private var dateRangeLabel: String {
        let start = GanttTimelineView.dateFormatter.string(from: goalStart)
        let end = GanttTimelineView.dateFormatter.string(from: goalEnd)
        return "\(start) → \(end)"
    }

    private var primaryEntryWindow: String? {
        guard let entry = primaryEntry else { return nil }
        if entry.kind == .event {
            return TimelineEntryRow.eventIntervalFormatter.string(from: entry.startDate, to: entry.endDate)
        }
        return TimelineEntryRow.dayIntervalFormatter.string(from: entry.startDate, to: entry.endDate)
    }

    private var primaryEntryRelativeStart: String? {
        guard let entry = primaryEntry else { return nil }
        return GanttRow.relativeFormatter.localizedString(for: entry.startDate, relativeTo: Date())
    }

    private var hasDigestSection: Bool {
        if primaryInsight != nil { return true }
        if let entry = primaryEntry {
            if let metric = entry.metricSummary, !metric.isEmpty { return true }
            if let detail = entry.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleSection
            metadataChips

            if hasDigestSection {
                digestSection
            }

            timelineVisualization

            if !entries.isEmpty {
                Divider()
                    .opacity(0.12)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        TimelineEntryRow(entry: entry, rangeStart: rangeStart, rangeEnd: rangeEnd)
                    }
                }
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 28, tint: goalKindLabel.tint.opacity(0.18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var titleSection: some View {
        switch rowStyle {
        case .progress:
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let entry = primaryEntry, entry.title != goal.title {
                    Text(entry.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(dateRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .event:
            VStack(alignment: .leading, spacing: 6) {
                if let entry = primaryEntry {
                    Text(entry.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                } else {
                    Text(goal.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                }

                Text(goal.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let window = primaryEntryWindow {
                    Text(window)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(dateRangeLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var metadataChips: some View {
        HStack(spacing: 10) {
            goalKindChip

            switch rowStyle {
            case .progress:
                infoChip(icon: "gauge", text: "Progress \(progressPercent)%")

                if let target = goal.targetDate {
                    infoChip(icon: "calendar", text: "Target \(GanttTimelineView.dateFormatter.string(from: target))", tint: .blue)
                }
            case .event:
                infoChip(icon: "clock", text: primaryEntryRelativeStart.map { "In \($0)" } ?? "Scheduled", tint: .blue.opacity(0.8))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var digestSection: some View {
        if let insight = primaryInsight {
            VStack(alignment: .leading, spacing: 8) {
                Label(insight.outcomeSummary, systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(digestTint)

                if !insight.subtaskHighlights.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(insight.subtaskHighlights.enumerated()), id: \.offset) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(digestTint.opacity(0.85))
                                Text(item.element)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let action = insight.recommendedAction, !action.isEmpty {
                    infoChip(icon: "bolt.fill", text: action, tint: digestTint)
                }

                if let metric = primaryEntry?.metricSummary, !metric.isEmpty {
                    infoChip(icon: "target", text: metric, tint: digestTint.opacity(0.9))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(digestTint.opacity(0.12))
            )
        } else if let entry = primaryEntry {
            let detail = entry.metricSummary ?? entry.detail
            if let summary = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(digestTint)

                    if let window = primaryEntryWindow {
                        Text(window)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(digestTint.opacity(0.1))
                )
            }
        }
    }

    @ViewBuilder
    private var timelineVisualization: some View {
        switch rowStyle {
        case .progress:
            progressTimelineView
        case .event:
            if !eventEntries.isEmpty {
                eventTimelineView
            } else {
                Text("No focus blocks in this horizon yet.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressTimelineView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let total = max(rangeEnd.timeIntervalSince(rangeStart), 1)
            let startOffset = max(goalStart.timeIntervalSince(rangeStart), 0)
            let endOffset = max(goalEnd.timeIntervalSince(rangeStart), startOffset + 3600)
            let clampedStart = min(max(startOffset / total, 0), 1)
            let clampedEnd = min(max(endOffset / total, clampedStart + 0.05), 1)
            let barWidth = max(width * CGFloat(clampedEnd - clampedStart), 12)
            let barX = width * CGFloat(clampedStart)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.14))
                    .frame(height: 18)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [goalKindLabel.tint.opacity(0.65), goalKindLabel.tint.opacity(0.28)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth, height: 18)
                    .offset(x: barX)

                Capsule()
                    .fill(goalKindLabel.tint.opacity(0.18))
                    .frame(width: barWidth * CGFloat(max(goal.progress, 0.05)), height: 18)
                    .offset(x: barX)
            }
        }
        .frame(height: 20)
    }

    private var eventTimelineView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let total = max(rangeEnd.timeIntervalSince(rangeStart), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 10)

                ForEach(eventEntries) { entry in
                    let startOffset = max(entry.startDate.timeIntervalSince(rangeStart), 0)
                    let endOffset = max(entry.endDate.timeIntervalSince(rangeStart), startOffset + 900)
                    let clampedStart = min(max(startOffset / total, 0), 1)
                    let clampedEnd = min(max(endOffset / total, clampedStart + 0.01), 1)
                    let markerWidth = max(width * CGFloat(clampedEnd - clampedStart), 4)
                    let markerX = width * CGFloat(clampedStart)

                    Capsule()
                        .fill(goalKindLabel.tint.opacity(0.9))
                        .frame(width: markerWidth, height: 10)
                        .offset(x: markerX)
                }
            }
        }
        .frame(height: 14)
    }

    private var goalKindLabel: (title: String, icon: String, tint: Color) {
        switch goal.kind {
        case .event:
            return ("Event", "calendar.badge.clock", .blue)
        case .campaign:
            return ("Campaign", "chart.line.uptrend.xyaxis", .purple)
        case .hybrid:
            return ("Hybrid", "arrow.triangle.2.circlepath", .teal)
        }
    }

    private var goalKindChip: some View {
        Label(goalKindLabel.title, systemImage: goalKindLabel.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(goalKindLabel.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(goalKindLabel.tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func infoChip(icon: String, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
    }

    private var accessibilityDescription: String {
        switch rowStyle {
        case .progress:
            return "\(goal.title). Progress \(progressPercent) percent. Scheduled between \(dateRangeLabel)."
        case .event:
            if let window = primaryEntryWindow {
                return "\(goal.title) has an upcoming session: \(window)."
            }
            return "\(goal.title) has event windows in this horizon."
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private struct TimelineEntryRow: View {
    let entry: GoalTimelineEntry
    let rangeStart: Date
    let rangeEnd: Date

    private var accent: Color {
        switch entry.kind {
        case .event: return .blue
        case .projection: return .purple
        case .phase: return .orange
        case .metricCheckpoint: return .indigo
        }
    }

    private var detailSummary: String? {
        guard let detail = entry.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return nil
        }
        return detail
    }

    private var relativeStartDescription: String? {
        TimelineEntryRow.relativeFormatter.localizedString(for: entry.startDate, relativeTo: Date())
    }

    private var kindLabel: String {
        switch entry.kind {
        case .event: return "Event"
        case .projection: return "Projection"
        case .phase: return "Phase"
        case .metricCheckpoint: return "Checkpoint"
        }
    }

    private var kindIcon: String {
        switch entry.kind {
        case .event: return "calendar"
        case .projection: return "scope"
        case .phase: return "flag.checkered"
        case .metricCheckpoint: return "target"
        }
    }

    private var hasFooterMetadata: Bool {
        entry.intelligence?.completionLikelihood != nil ||
            entry.intelligence?.readyToMarkGoalComplete == true ||
            entry.confidence != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            intelligenceSection

            if let metric = entry.metricSummary, !metric.isEmpty {
                pill(icon: "target", text: metric, tint: accent.opacity(0.9))
            }

            timelineSegment

            if hasFooterMetadata {
                footerMetadata
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            kindBadge

            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(dateRange)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let relative = relativeStartDescription {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var intelligenceSection: some View {
        if let intelligence = entry.intelligence {
            VStack(alignment: .leading, spacing: 8) {
                Label(intelligence.outcomeSummary, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)

                if !intelligence.subtaskHighlights.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(intelligence.subtaskHighlights.enumerated()), id: \.offset) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(accent.opacity(0.85))
                                Text(item.element)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let action = intelligence.recommendedAction, !action.isEmpty {
                    pill(icon: "bolt.fill", text: action, tint: accent)
                }

                if let detail = detailSummary {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let detail = detailSummary {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timelineSegment: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let total = max(rangeEnd.timeIntervalSince(rangeStart), 1)
            let startOffset = max(entry.startDate.timeIntervalSince(rangeStart), 0)
            let endOffset = max(entry.endDate.timeIntervalSince(rangeStart), startOffset + 1800)
            let clampedStart = min(max(startOffset / total, 0), 1)
            let clampedEnd = min(max(endOffset / total, clampedStart + 0.02), 1)
            let barWidth = max(width * CGFloat(clampedEnd - clampedStart), 10)
            let barX = width * CGFloat(clampedStart)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 8)

                Capsule()
                    .fill(accent.opacity(0.9))
                    .frame(width: barWidth, height: 8)
                    .offset(x: barX)
            }
        }
        .frame(height: 10)
    }

    private var footerMetadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let likelihood = entry.intelligence?.completionLikelihood {
                Label("AI confidence \(Int(likelihood * 100))%", systemImage: "gauge.medium")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.intelligence?.readyToMarkGoalComplete == true {
                Label("Window could finish the entire goal", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.green)
            }

            if let confidence = entry.confidence {
                Label("Schedule confidence \(Int(confidence * 100))%", systemImage: "calendar.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var kindBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: kindIcon)
                .font(.caption2.weight(.semibold))
            Text(kindLabel.uppercased())
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private func pill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    private var dateRange: String {
        switch entry.kind {
        case .event:
            return TimelineEntryRow.eventIntervalFormatter.string(from: entry.startDate, to: entry.endDate)
        default:
            return TimelineEntryRow.dayIntervalFormatter.string(from: entry.startDate, to: entry.endDate)
        }
    }

    static let eventIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let dayIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct GoalTimelineSection: Identifiable {
    let goal: Goal
    let entries: [GoalTimelineEntry]

    var id: UUID { goal.id }

    var nextMilestone: Date {
        entries.map(\.startDate).min() ?? (goal.activatedAt ?? goal.createdAt)
    }
}

struct GoalCategoryGridView: View {
    let goals: [Goal]
    @Binding var selectedCategory: String?

    private let priorityOrder: [Goal.Priority] = [.now, .next, .later]

    private var folders: [CategoryFolder] {
        Dictionary(grouping: goals, by: { $0.category })
            .map { CategoryFolder(name: $0.key, goals: $0.value) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var activeFolder: CategoryFolder? {
        if let selectedCategory,
           let match = folders.first(where: { $0.name == selectedCategory }) {
            return match
        }
        return folders.first
    }

    private var deckGoals: [Goal] {
        let sourceGoals = activeFolder?.goals ?? goals
        return sourceGoals.sorted(by: deckSort)
    }

    private var deckTitle: String {
        if let folder = activeFolder {
            return folder.name
        }
        return "Featured Cards"
    }

    private var deckSubtitle: String {
        if let folder = activeFolder {
            return "\(folder.goals.count) card\(folder.goals.count == 1 ? "" : "s") in this folder"
        }
        let total = goals.count
        return total == 0 ? "No cards yet" : "\(total) card\(total == 1 ? "" : "s") across all folders"
    }

    private var deckIsTruncated: Bool {
        // No longer truncating - always show all goals
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if goals.isEmpty {
                emptyState
            } else {
                folderShelfSection
                deckSection
            }
        }
    }

    private func deckSort(_ lhs: Goal, _ rhs: Goal) -> Bool {
        let lhsIndex = priorityOrder.firstIndex(of: lhs.priority) ?? priorityOrder.count
        let rhsIndex = priorityOrder.firstIndex(of: rhs.priority) ?? priorityOrder.count

        if lhsIndex != rhsIndex {
            return lhsIndex < rhsIndex
        }

        if lhs.progress != rhs.progress {
            return lhs.progress > rhs.progress
        }

        return lhs.createdAt < rhs.createdAt
    }

    private var deckSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(deckTitle, systemImage: "folder.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(deckSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedCategory != nil {
                    Button("Clear") {
                        withAnimation(.smoothSpring) {
                            selectedCategory = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if let folder = activeFolder {
                FolderSummaryStrip(folder: folder)
            } else {
                FolderSummaryStrip(folder: CategoryFolder(name: "All", goals: goals))
            }

            if deckGoals.isEmpty {
                Text("No cards to show yet. Ask Moss to draft your first goal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.panelBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
            } else {
                LazyVStack(spacing: 18) {
                    ForEach(deckGoals) { goal in
                        GoalCardView(goal: goal)
                    }
                }
            }

            if deckIsTruncated {
                Text("Showing top focus. Pick a folder below to dive into the full stack.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var folderShelfSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Folders")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if let folder = activeFolder {
                    Text("Active: \(folder.activeCount) • Completed: \(folder.completedCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !goals.isEmpty {
                    let active = goals.filter { $0.activationState == .active }.count
                    let completed = goals.filter { $0.activationState == .completed }.count
                    Text("Active: \(active) • Completed: \(completed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    AllFolderTile(totalGoals: goals.count, activeGoals: goals.filter { $0.activationState == .active }.count, completedGoals: goals.filter { $0.activationState == .completed }.count, isSelected: selectedCategory == nil) {
                        withAnimation(.smoothSpring) {
                            selectedCategory = nil
                        }
                    }

                    ForEach(folders) { folder in
                        Button {
                            withAnimation(.smoothSpring) {
                                if selectedCategory == folder.name {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = folder.name
                                }
                            }
                        } label: {
                            CategoryFolderTile(folder: folder, isSelected: selectedCategory == folder.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("No folders yet")
                .font(.headline)

            Text("Create a goal and Moss will slot it into a folder for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.blue.opacity(0.12), lineWidth: 1.2)
        )
    }

    struct CategoryFolder: Identifiable {
        let name: String
        let goals: [Goal]

        var id: String { name }

        var tint: Color {
            GoalCategoryGridView.tint(for: name)
        }

        var averageProgress: Double {
            guard !goals.isEmpty else { return 0 }
            let total = goals.reduce(0.0) { $0 + $1.progress }
            return total / Double(goals.count)
        }

        var activeCount: Int {
            goals.filter { $0.activationState == .active }.count
        }

        var completedCount: Int {
            goals.filter { $0.activationState == .completed }.count
        }

        var openCount: Int {
            goals.count - completedCount
        }

        var nowCount: Int {
            goals.filter { $0.priority == .now }.count
        }

        var previewGoals: [Goal] {
            goals.sorted { lhs, rhs in
                if lhs.progress == rhs.progress {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.progress > rhs.progress
            }
        }
    }

    static func tint(for name: String) -> Color {
        let unicodeTotal = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = Double(unicodeTotal % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }
}

private struct FolderSummaryStrip: View {
    let folder: GoalCategoryGridView.CategoryFolder

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SummaryChip(icon: "gauge", label: "Avg", value: "\(Int(folder.averageProgress * 100))%", tint: folder.tint)
                SummaryChip(icon: "checkmark.seal.fill", label: "Complete", value: "\(folder.completedCount)", tint: .blue)
                SummaryChip(icon: "bolt", label: "Active", value: "\(folder.activeCount)", tint: .green)
                SummaryChip(icon: "clock", label: "Open", value: "\(folder.openCount)", tint: .orange)
                SummaryChip(icon: "flag.fill", label: "Now", value: "\(folder.nowCount)", tint: .red)
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    struct SummaryChip: View {
        let icon: String
        let label: String
        let value: String
        let tint: Color

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(label.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

private struct CategoryFolderTile: View {
    let folder: GoalCategoryGridView.CategoryFolder
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(folder.tint)

                Text(folder.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(folder.tint)
                }
            }

            ProgressView(value: folder.averageProgress)
                .progressViewStyle(.linear)
                .tint(folder.tint)

            HStack(spacing: 10) {
                FolderSummaryStrip.SummaryChip(icon: "bolt", label: "Active", value: "\(folder.activeCount)", tint: .green)
                FolderSummaryStrip.SummaryChip(icon: "checkmark.seal.fill", label: "Done", value: "\(folder.completedCount)", tint: .blue)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(folder.previewGoals.prefix(3)) { goal in
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(goalBadgeColor(for: goal.priority))
                            .frame(width: 6, height: 6)

                        Text(goal.title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(Int(goal.progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if folder.previewGoals.count > 3 {
                    Text("+\(folder.previewGoals.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        .frame(width: 240, alignment: .leading)
        .liquidGlassCard(
            cornerRadius: 30,
            tint: folder.tint.opacity(isSelected ? 0.45 : 0.22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(folder.tint.opacity(isSelected ? 0.7 : 0.18), lineWidth: isSelected ? 2 : 1)
        )
    }

    private func goalBadgeColor(for priority: Goal.Priority) -> Color {
        switch priority {
        case .now: return .red
        case .next: return .orange
        case .later: return .blue
        }
    }
}

private struct AllFolderTile: View {
    let totalGoals: Int
    let activeGoals: Int
    let completedGoals: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.cyan)

                    Text("All folders")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.cyan)
                    }
                }

                Text("\(totalGoals) card\(totalGoals == 1 ? "" : "s") on the board")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    FolderSummaryStrip.SummaryChip(icon: "bolt", label: "Active", value: "\(activeGoals)", tint: .green)
                    FolderSummaryStrip.SummaryChip(icon: "checkmark.seal.fill", label: "Done", value: "\(completedGoals)", tint: .blue)
                }
            }
            .padding(22)
            .frame(width: 220, alignment: .leading)
            .liquidGlassCard(
                cornerRadius: 30,
                tint: Color.cyan.opacity(isSelected ? 0.45 : 0.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.cyan.opacity(isSelected ? 0.7 : 0.22), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

