//
//  EmptyStateView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct EmptyStateView: View {
    @StateObject private var voiceService = VoiceService()
    @State private var animateSparkles = false

    var body: some View {
        VStack(spacing: 24) {
            // Animated Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                VStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)

                    // Animated sparkles
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Image(systemName: "sparkle")
                                .font(.caption)
                                .foregroundStyle(.purple)
                                .scaleEffect(animateSparkles ? 1.2 : 0.8)
                                .animation(
                                    .easeInOut(duration: 1.5)
                                    .repeatForever()
                                    .delay(Double(index) * 0.3),
                                    value: animateSparkles
                                )
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                Text("Start with your first goal")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text("Type or speak what you want to achieve.\nAI will help you break it down and schedule it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }

            VStack(spacing: 16) {
                // Example goals
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try saying:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ExampleGoalButton(text: "\"Learn to cook Italian food\"")
                        ExampleGoalButton(text: "\"Build a fitness routine\"")
                        ExampleGoalButton(text: "\"Launch my side project\"")
                    }
                }

                // Voice hint
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)

                    Text("Tap the microphone to speak your goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            animateSparkles = true
        }
    }
}

struct ExampleGoalButton: View {
    let text: String
    @Environment(\.modelContext) private var modelContext
    @StateObject private var userContextService = UserContextService.shared

    private var aiService: AIService { AIService.shared }

    var body: some View {
        Button(action: {
            createExampleGoal()
        }) {
            HStack {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func createExampleGoal() {
        let goalText = text.replacingOccurrences(of: "\"", with: "")

        Task {
            do {
                let context = userContextService.buildContext(from: [])
                let response = try await aiService.createGoal(from: goalText, context: context)

                await MainActor.run {
                    let priority = Goal.Priority(rawValue: response.priority) ?? .next
                    let newGoal = Goal(
                        title: response.title,
                        content: response.content,
                        category: response.category,
                        priority: priority
                    )

                    modelContext.insert(newGoal)

                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }
            } catch {
                print("❌ Failed to create example goal: \(error)")

                // Fallback: create basic goal
                await MainActor.run {
                    let newGoal = Goal(title: goalText)
                    modelContext.insert(newGoal)
                }
            }
        }
    }
}

#Preview {
    EmptyStateView()
}