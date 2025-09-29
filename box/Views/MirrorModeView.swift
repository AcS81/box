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
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Understanding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                if mirrorCards.isEmpty {
                    EmptyMirrorView()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(mirrorCards.sorted(by: { $0.createdAt > $1.createdAt })) { card in
                            MirrorCardView(card: card)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color.blue.opacity(0.05))
        .task {
            await generateMirrorCards()
        }
    }
    
    private func generateMirrorCards() async {
        let context = userContextService.buildContext(from: goals)

        // Generate AI interpretation for each active goal
        for goal in goals.filter({ $0.isActive }) {
            // Check if mirror card already exists
            let existingCard = mirrorCards.first { $0.relatedGoalId == goal.id }

            do {
                let response = try await aiService.generateMirrorCard(for: goal, context: context)

                await MainActor.run {
                    if let existingCard = existingCard {
                        // Update existing mirror card
                        existingCard.aiInterpretation = response.aiInterpretation
                        existingCard.suggestedActions = response.suggestedActions
                        existingCard.confidence = response.confidence
                    } else {
                        // Create new mirror card
                        let newMirrorCard = AIMirrorCard(
                            title: goal.title,
                            interpretation: response.aiInterpretation,
                            relatedGoalId: goal.id
                        )
                        newMirrorCard.suggestedActions = response.suggestedActions
                        newMirrorCard.confidence = response.confidence

                        modelContext.insert(newMirrorCard)
                    }
                }

                print("🪞 Generated mirror card for: \(goal.title)")
            } catch {
                print("❌ Failed to generate mirror card: \(error)")
            }
        }
    }
}

struct MirrorCardView: View {
    let card: AIMirrorCard
    @State private var isExpanded = false

    private var emotionalToneColor: Color {
        // This would come from the AI response, but for now we'll use a default
        return .blue
    }

    private var confidenceText: String {
        let percentage = Int(card.confidence * 100)
        return "\(percentage)% understanding"
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
                    Circle()
                        .fill(emotionalToneColor.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text("Motivated") // This would come from AI response
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

                Text(card.createdAt.timeAgo)
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
                Text("Mirror Mode")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Text("AI Understanding")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Active goals will appear here with AI insights")
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
