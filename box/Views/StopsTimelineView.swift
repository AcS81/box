//
//  StopsTimelineView.swift
//  box
//
//  Created on 03.10.2025.
//

import SwiftUI
import SwiftData

struct StopsTimelineView: View {
    let goals: [Goal]
    @Environment(\.modelContext) private var modelContext
    @StateObject private var userContextService = UserContextService.shared

    @State private var selectedGoal: Goal?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    // Soft warning and hard limit thresholds
    private let STEP_WARNING_THRESHOLD = 12
    private let STEP_HARD_LIMIT = 15

    private var activeGoals: [Goal] {
        goals.filter {
            $0.hasSequentialSteps &&
            ($0.activationState == .active || $0.activationState == .draft)
        }
    }

    private var displayGoal: Goal? {
        selectedGoal ?? activeGoals.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if activeGoals.isEmpty {
                    emptyState
                } else {
                    if activeGoals.count > 1 {
                        goalSelector
                    }

                    if let goal = displayGoal {
                        goalContent(for: goal)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(paperBackground)
        .onAppear {
            if selectedGoal == nil, let first = activeGoals.first {
                selectedGoal = first
            }
        }
    }

    private var goalSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Goal")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(activeGoals) { goal in
                        GoalSelectorChip(
                            goal: goal,
                            isSelected: selectedGoal?.id == goal.id
                        )
                        .onTapGesture {
                            withAnimation(.smoothSpring) {
                                selectedGoal = goal
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func goalContent(for goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Goal header
            goalHeader(for: goal)

            // Gantt timeline view (visual roadmap)
            GanttTimelineView(goal: goal, onStopTap: { stop in
                // Could open detail sheet if needed
                print("Tapped stop: \(stop.title)")
            })

            // Progress bar (simplified overview)
            StopProgressBar(goal: goal)

            // Current stop card (edit & complete)
            CurrentStopCard(goal: goal) {
                handleStopCompletion(for: goal)
            }

            // Next stop preview
            NextStopPreview(goal: goal)

            // Error display
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Loading indicator
            if isGenerating {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating next stop...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }

    private func goalHeader(for goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            if !goal.content.isEmpty {
                Text(goal.content)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(goal.category, systemImage: "folder.fill")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                let completedCount = goal.completedSequentialSteps.count
                let totalCount = goal.sequentialSteps.count
                Label("\(completedCount)/\(totalCount) steps", systemImage: "checkmark.circle")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.gray)

            VStack(spacing: 8) {
                Text("No Roadmaps Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Create a goal with stops to see your timeline here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Go to the chat tab and ask the AI to create a goal with sequential roadmap steps.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 64)
        .frame(maxWidth: .infinity)
    }

    private var paperBackground: some View {
        Color(.systemGroupedBackground)
    }

    @MainActor
    private func handleStopCompletion(for goal: Goal) {
        guard let current = goal.currentSequentialStep else { return }

        // Check if this is the final step (marked with special content)
        let isFinalStep = current.content.contains("⭐️ Final Step")

        if isFinalStep {
            // Mark current step as complete
            current.progress = 1.0
            current.stepStatus = .completed
            current.lock(with: current.captureSnapshot())

            // Mark entire goal as complete
            goal.progress = 1.0
            goal.deactivate(to: .completed, rationale: "All sequential steps completed")
            goal.updatedAt = Date()
            try? modelContext.save()

            errorMessage = "🎉 Goal completed! All steps finished."
            return
        }

        // Hard limit check
        if goal.sequentialSteps.count >= STEP_HARD_LIMIT {
            errorMessage = "⛔️ This goal has reached \(STEP_HARD_LIMIT) steps (maximum). Please complete it or split into smaller goals."
            return
        }

        // Soft warning for many steps
        if goal.sequentialSteps.count >= STEP_WARNING_THRESHOLD {
            errorMessage = "⚠️ This goal has \(goal.sequentialSteps.count) steps. Consider breaking into smaller goals."
        } else {
            errorMessage = nil
        }

        isGenerating = true

        Task {
            defer { isGenerating = false }

            do {
                let context = await userContextService.buildContext(from: goals)

                // Generate NEXT sequential step via AI BEFORE advancing
                let nextStepResponse = try await AIService.shared.generateNextSequentialStep(
                    for: goal,
                    completedStep: current,
                    context: context
                )

                // Check for duplicate titles before creating new step
                let existingTitles = goal.sequentialSteps.map { $0.title.lowercased().trimmingCharacters(in: .whitespaces) }
                let newTitleLower = nextStepResponse.title.lowercased().trimmingCharacters(in: .whitespaces)

                if existingTitles.contains(newTitleLower) {
                    errorMessage = "⚠️ Duplicate step detected: '\(nextStepResponse.title)'. Skipping creation."
                    print("❌ Duplicate step title detected: \(nextStepResponse.title)")
                    // Still mark current as complete but don't create duplicate
                    current.progress = 1.0
                    current.stepStatus = .completed
                    current.lock(with: current.captureSnapshot())
                    goal.syncProgressWithSequentialSteps()
                    goal.updatedAt = Date()
                    try modelContext.save()
                    return
                }

                // Mark current step as complete and locked
                current.progress = 1.0
                current.completedAt = Date()  // Track actual completion time
                current.stepStatus = .completed
                current.lock(with: current.captureSnapshot())

                // Create and activate new step
                let newStep = goal.createSequentialStep(
                    title: nextStepResponse.title,
                    outcome: nextStepResponse.outcome,
                    targetDate: Calendar.current.date(
                        byAdding: .day,
                        value: nextStepResponse.daysFromNow ?? 7,
                        to: Date()
                    )
                )

                // Set AI's proactive guidance as content
                newStep.content = nextStepResponse.aiSuggestion ?? ""

                // Check if AI says goal is complete
                if nextStepResponse.isGoalComplete == true {
                    print("🎯 AI indicates goal is complete (confidence: \(nextStepResponse.confidenceLevel ?? 0))")
                    newStep.stepStatus = .current  // Final step - user needs to complete it
                    // Mark this as the final step (prepend to existing AI suggestion)
                    newStep.content = "⭐️ Final Step - Complete this to finish the goal!\n\n" + (nextStepResponse.aiSuggestion ?? nextStepResponse.outcome)
                    errorMessage = "✅ Final step: \(nextStepResponse.title). Complete this to finish the goal!"
                } else {
                    newStep.stepStatus = .current  // Make this the active step
                }

                // Apply tree grouping if provided by AI
                if let treeGrouping = nextStepResponse.treeGrouping {
                    let sections = treeGrouping.sections.map { section in
                        TreeSection(
                            title: section.title,
                            stepIndices: section.stepIndices,
                            isComplete: section.isComplete
                        )
                    }
                    goal.treeGroupingSections = sections
                    print("📁 Applied tree grouping: \(sections.count) sections")
                }

                // Sync parent goal progress with sequential steps
                goal.syncProgressWithSequentialSteps()
                goal.updatedAt = Date()
                try modelContext.save()

            } catch {
                errorMessage = "Failed to generate next step: \(error.localizedDescription)"
                print("❌ Sequential step completion error: \(error)")
            }
        }
    }

}

private struct GoalSelectorChip: View {
    let goal: Goal
    let isSelected: Bool

    private var progressText: String {
        return "\(goal.completedSequentialSteps.count)/\(goal.sequentialSteps.count) steps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(progressText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    let goal = Goal(title: "Build iOS App", priority: .now)
    goal.activationState = .active

    // Create sequential steps
    let step1 = goal.createSequentialStep(title: "Research", outcome: "Understand requirements", targetDate: Date())
    step1.stepStatus = .completed
    step1.progress = 1.0

    let step2 = goal.createSequentialStep(title: "Prototype", outcome: "Build MVP", targetDate: Date().addingTimeInterval(7*86400))
    step2.stepStatus = .current
    step2.progress = 0.5

    _ = goal.createSequentialStep(title: "Testing", outcome: "Gather feedback", targetDate: Date().addingTimeInterval(14*86400))

    return StopsTimelineView(goals: [goal])
        .modelContainer(for: [Goal.self])
}
