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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(card.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
            
            // AI Interpretation
            if !card.aiInterpretation.isEmpty {
                Text(card.aiInterpretation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            // Confidence Indicator
            HStack {
                Text("Understanding")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                ProgressView(value: card.confidence)
                    .tint(.blue)
                    .scaleEffect(0.8)
            }
            
            // Suggested Actions
            if !card.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Suggestions")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    
                    ForEach(card.suggestedActions, id: \.self) { action in
                        HStack(spacing: 4) {
                            Image(systemName: "sparkle")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(action)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

struct EmptyMirrorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.largeTitle)
                .foregroundStyle(.blue.opacity(0.3))
            
            Text("AI is learning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Create goals to see AI interpretation")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}
