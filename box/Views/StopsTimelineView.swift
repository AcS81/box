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
            CurrentStopCard(goal: goal, onComplete: {
                handleStopCompletion(for: goal)
            }, isGenerating: isGenerating)

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
            current.updatedAt = Date()

            // Mark entire goal as complete
            goal.progress = 1.0
            goal.deactivate(to: .completed, rationale: "All sequential steps completed")
            goal.updatedAt = Date()

            do {
                try modelContext.save()
                errorMessage = "🎉 Goal completed! All steps finished."
            } catch {
                errorMessage = "⚠️ Goal completed but failed to save: \(error.localizedDescription)"
                print("❌ Failed to save completed goal: \(error)")
            }
            return
        }

        // Check if next step already exists (pre-generated)
        let nextStep = goal.nextSequentialStep
        let hasPreGeneratedSteps = nextStep != nil
        let pendingStepsCount = goal.sequentialSteps.filter { $0.stepStatus == .pending }.count

        // Decide whether to regenerate:
        // - If no next step exists (at the end)
        // - If on the last pending step (so we can look ahead)
        let shouldRegenerateSteps = !hasPreGeneratedSteps || pendingStepsCount == 0

        if hasPreGeneratedSteps && !shouldRegenerateSteps {
            // FAST PATH: Just advance to pre-generated step (NO API CALL!)
            current.progress = 1.0
            current.completedAt = Date()
            current.stepStatus = .completed
            current.lock(with: current.captureSnapshot())
            current.updatedAt = Date()

            // Activate next step
            nextStep!.stepStatus = .current
            nextStep!.progress = 0.0
            nextStep!.updatedAt = Date()

            goal.syncProgressWithSequentialSteps()
            goal.updatedAt = Date()

            do {
                try modelContext.save()
                errorMessage = nil
                print("✅ Advanced to next pre-generated step (no API call)")
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                print("❌ Failed to save: \(error)")
            }
            return
        }

        // REGENERATION PATH: Ran out of steps - ask AI what's next based on progress so far
        print("🔄 Regenerating steps - reviewing progress to determine what comes next...")

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

                // Ask AI: "Based on what's been accomplished, what's next?"
                // AI will review all completed steps + user inputs and decide:
                // - Generate next step if more work needed
                // - Mark as final step if goal is achieved
                let nextStepResponse = try await AIService.shared.generateNextSequentialStep(
                    for: goal,
                    completedStep: current,
                    context: context
                )

                // Check for duplicate titles
                let existingTitles = goal.sequentialSteps.map { $0.title.lowercased().trimmingCharacters(in: .whitespaces) }
                let newTitleLower = nextStepResponse.title.lowercased().trimmingCharacters(in: .whitespaces)

                if existingTitles.contains(newTitleLower) {
                    print("❌ Duplicate step detected - AI thinks we're done")
                    // Mark current as complete and finish
                    current.progress = 1.0
                    current.stepStatus = .completed
                    current.lock(with: current.captureSnapshot())
                    current.updatedAt = Date()

                    // Complete the goal
                    goal.progress = 1.0
                    goal.deactivate(to: .completed, rationale: "All necessary steps completed")
                    goal.updatedAt = Date()
                    try modelContext.save()

                    await MainActor.run {
                        errorMessage = "🎉 Goal completed! AI determined no more steps needed."
                    }
                    return
                }

                // Mark current step as complete
                current.progress = 1.0
                current.completedAt = Date()
                current.stepStatus = .completed
                current.lock(with: current.captureSnapshot())
                current.updatedAt = Date()

                // Create new step based on AI analysis of progress
                let newStep = goal.createSequentialStep(
                    title: nextStepResponse.title,
                    outcome: nextStepResponse.outcome,
                    targetDate: Calendar.current.date(
                        byAdding: .day,
                        value: nextStepResponse.daysFromNow ?? 7,
                        to: Date()
                    )
                )

                newStep.content = nextStepResponse.aiSuggestion ?? ""
                newStep.updatedAt = Date()

                // Check if AI says goal is complete after this step
                if nextStepResponse.isGoalComplete == true {
                    print("🎯 AI indicates this is the final step (confidence: \(nextStepResponse.confidenceLevel ?? 0))")
                    newStep.stepStatus = .current
                    newStep.content = "⭐️ Final Step - Complete this to finish the goal!\n\n" + (nextStepResponse.aiSuggestion ?? nextStepResponse.outcome)
                    await MainActor.run {
                        errorMessage = "✅ Final step generated: \(nextStepResponse.title)"
                    }
                } else {
                    newStep.stepStatus = .current
                    await MainActor.run {
                        errorMessage = nil
                    }
                }

                // Apply tree grouping if provided
                if let treeGrouping = nextStepResponse.treeGrouping {
                    applyTreeStructure(treeGrouping: treeGrouping, to: goal)
                }

                goal.syncProgressWithSequentialSteps()
                goal.updatedAt = Date()

                try modelContext.save()

                print("✅ Regenerated next step based on progress so far")

            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate next step: \(error.localizedDescription)"
                }
                print("❌ Sequential step regeneration error: \(error)")
            }
        }
    }

    /// Creates real parent-child Goal hierarchy from AI's tree grouping
    @MainActor
    private func applyTreeStructure(treeGrouping: TreeGrouping, to goal: Goal) {
        print("📁 Applying tree structure with \(treeGrouping.sections.count) sections")

        // Work with current sequential steps
        let steps = goal.sequentialSteps
        var processedIndices = Set<Int>()
        var parentsToInsert: [(index: Int, parent: Goal)] = []

        // Process each section to create parent Goals
        for section in treeGrouping.sections.sorted(by: { $0.stepIndices.min() ?? 0 < $1.stepIndices.min() ?? 0 }) {
            guard !section.stepIndices.isEmpty else { continue }

            // Validate indices
            let validIndices = section.stepIndices.filter { $0 < steps.count }
            guard !validIndices.isEmpty else { continue }

            // Skip if already processed
            if validIndices.contains(where: { processedIndices.contains($0) }) {
                continue
            }

            // Get the child steps
            let childSteps = validIndices.compactMap { index -> Goal? in
                guard steps.indices.contains(index) else { return nil }
                return steps[index]
            }

            guard !childSteps.isEmpty else { continue }

            // Create parent Goal
            let parent = Goal(title: section.title, priority: goal.priority)
            parent.category = goal.category
            parent.content = "Group containing \(childSteps.count) steps"
            parent.isSequentialStep = true
            parent.orderIndexInParent = validIndices.min() ?? 0
            parent.parent = goal

            // Calculate parent status based on children
            let allCompleted = childSteps.allSatisfy { $0.stepStatus == .completed }
            let hasCurrentChild = childSteps.contains { $0.stepStatus == .current }

            if allCompleted {
                parent.stepStatus = .completed
                parent.progress = 1.0
            } else if hasCurrentChild {
                parent.stepStatus = .current
                let completedCount = childSteps.filter { $0.stepStatus == .completed }.count
                parent.progress = Double(completedCount) / Double(childSteps.count)
            } else {
                parent.stepStatus = .pending
                parent.progress = 0.0
            }

            // Move children to parent
            if parent.subgoals == nil {
                parent.subgoals = []
            }
            for (idx, child) in childSteps.enumerated() {
                child.parent = parent
                child.orderIndexInParent = idx
                parent.subgoals?.append(child)
            }

            // Insert parent at the position of first child
            let insertPosition = validIndices.min() ?? 0
            parentsToInsert.append((index: insertPosition, parent: parent))

            // Mark these indices as processed
            validIndices.forEach { processedIndices.insert($0) }

            // Insert parent into model context
            modelContext.insert(parent)

            print("  ✓ Created parent '\(parent.title)' with \(childSteps.count) children")
        }

        // Remove processed children from main sequential steps and insert parents
        // Work backwards to avoid index issues
        let indicesToRemove = Array(processedIndices).sorted(by: >)
        for index in indicesToRemove {
            if steps.indices.contains(index) {
                let child = steps[index]
                // Remove from goal's subgoals array
                if let subgoalIndex = goal.subgoals?.firstIndex(where: { $0.id == child.id }) {
                    goal.subgoals?.remove(at: subgoalIndex)
                }
            }
        }

        // Insert parents in correct positions
        for (_, parent) in parentsToInsert.sorted(by: { $0.index < $1.index }) {
            if goal.subgoals == nil {
                goal.subgoals = []
            }
            goal.subgoals?.append(parent)
        }

        // Re-index all sequential steps
        for (index, step) in goal.sequentialSteps.enumerated() {
            step.orderIndexInParent = index
        }

        print("📁 Tree structure applied: \(parentsToInsert.count) parents created")
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
