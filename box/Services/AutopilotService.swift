//
//  AutopilotService.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import SwiftData
import Combine

/// Autonomous AI service that manages goals with autopilot enabled
@MainActor
class AutopilotService: ObservableObject {
    static let shared = AutopilotService()

    @Published var isRunning = false
    @Published var lastCheckDate: Date?

    private let aiService: AIService
    private let userContextService: UserContextService
    private let lifecycleService: GoalLifecycleService
    private let learningEngine: AutopilotLearningEngine

    private init() {
        self.aiService = AIService.shared
        self.userContextService = UserContextService.shared
        self.learningEngine = AutopilotLearningEngine.shared
        // Note: lifecycleService will be injected when starting
        self.lifecycleService = GoalLifecycleService(
            aiService: AIService.shared,
            userContextService: UserContextService.shared
        )
    }

    // MARK: - Manual Processing (User-Action Triggered Only)

    func startMonitoring() {
        // NO-OP: Timer-based monitoring removed
        print("🤖 Autopilot ready (user-action triggered only)")
    }

    func stopMonitoring() {
        // NO-OP: Timer-based monitoring removed
        print("🤖 Autopilot stopped")
    }

    func processAutopilotGoals(_ goals: [Goal], modelContext: ModelContext, skipExpensive: Bool = false) async {
        let autopilotGoals = goals.filter { $0.isAutopilotEnabled && !$0.isLocked }

        guard !autopilotGoals.isEmpty else {
            print("🤖 No autopilot goals found")
            return
        }

        print("🤖 Processing \(autopilotGoals.count) autopilot goal(s)\(skipExpensive ? " (quick mode)" : "")...")

        for goal in autopilotGoals {
            await processGoal(goal, allGoals: goals, modelContext: modelContext, skipExpensive: skipExpensive)
        }

        print("🤖 Autopilot check complete")
    }

    private func processGoal(_ goal: Goal, allGoals: [Goal], modelContext: ModelContext, skipExpensive: Bool = false) async {
        // Check each condition and take action

        // OPTIMIZATION: Skip expensive AI operations during preload (breakdown & activate)
        if !skipExpensive {
            // 1. Auto-breakdown if needed
            if shouldBreakdown(goal) {
                await autoBreakdown(goal, allGoals: allGoals, modelContext: modelContext)
            }

            // 2. Auto-activate if ready
            if shouldActivate(goal) {
                await autoActivate(goal, allGoals: allGoals, modelContext: modelContext)
            }
        }

        // 3. Auto-update progress based on subgoals
        if shouldUpdateProgress(goal) {
            await autoUpdateProgress(goal)
        }

        // 4. Auto-complete if all subgoals done
        if shouldComplete(goal) {
            await autoComplete(goal, allGoals: allGoals, modelContext: modelContext)
        }

        // 5. Nudge REMOVED (no time-based notifications)
    }

    // MARK: - Condition Checks

    private func shouldBreakdown(_ goal: Goal) -> Bool {
        // Check if already broken down
        guard !goal.hasBeenBrokenDown else { return false }

        // Breakdown if: No subgoals + priority is Now + not yet broken down
        let hasNoSubgoals = goal.subgoals?.isEmpty ?? true
        let isPriorityNow = goal.priority == .now
        let notStarted = goal.progress < 0.1

        let basicCondition = hasNoSubgoals && isPriorityNow && notStarted

        // Use learning engine to determine confidence
        let categoryScore = learningEngine.categorySuccessScore(for: goal.category)
        let confidence = categoryScore * (basicCondition ? 0.9 : 0.3)

        return basicCondition && learningEngine.shouldTakeAutopilotAction(confidence: confidence)
    }

    private func shouldActivate(_ goal: Goal) -> Bool {
        // Activate if: Has subgoals + priority Now/Next + not active + not stagnant
        let hasSubgoals = !(goal.subgoals?.isEmpty ?? true)
        let isPriorityHigh = goal.priority == .now || goal.priority == .next
        let notActive = goal.activationState != .active
        let notStagnant = Date().timeIntervalSince(goal.updatedAt) < 14 * 24 * 60 * 60 // 2 weeks

        return hasSubgoals && isPriorityHigh && notActive && notStagnant
    }

    private func shouldUpdateProgress(_ goal: Goal) -> Bool {
        // Update progress if: Has subgoals + progress is outdated
        guard goal.hasSubtasks else {
            return false
        }

        let calculatedProgress = goal.aggregatedProgress()
        let diff = abs(goal.progress - calculatedProgress)

        return diff > 0.05 // More than 5% difference
    }

    private func shouldComplete(_ goal: Goal) -> Bool {
        // Complete if: All subgoals are done + goal not already complete
        guard goal.hasSubtasks else {
            return false
        }

        let leaves = goal.leafDescendants()
        guard !leaves.isEmpty else { return false }

        let allComplete = leaves.allSatisfy { $0.progress >= 1.0 }
        let notYetComplete = goal.progress < 1.0

        return allComplete && notYetComplete
    }

    // MARK: - Actions

    private func autoBreakdown(_ goal: Goal, allGoals: [Goal], modelContext: ModelContext) async {
        do {
            let context = await userContextService.buildContext(from: allGoals)
            let response = try await aiService.breakdownGoal(goal, context: context)

            let breakdown = GoalBreakdownBuilder.apply(response: response, to: goal, in: modelContext)
            let atomicCount = max(breakdown.atomicTaskCount, breakdown.createdGoals.count)

            // Observe breakdown for learning
            learningEngine.observeManualBreakdown(goal: goal, subtaskCount: atomicCount)

            // Mark as broken down to prevent duplicates
            goal.hasBeenBrokenDown = true
            goal.updatedAt = Date()

            // Record in chat as system message
            recordSystemMessage(
                goal: goal,
                content: "🤖 Autopilot: Created \(atomicCount) atomic step\(atomicCount == 1 ? "" : "s") automatically\(breakdown.dependencyCount > 0 ? " with \(breakdown.dependencyCount) dependency link\(breakdown.dependencyCount == 1 ? "" : "s")" : "")"
            )

            // Observe action acceptance
            learningEngine.observeAutopilotAction(accepted: true)

            print("🤖 Auto-breakdown: Created \(atomicCount) atomic steps for '\(goal.title)' (\(breakdown.dependencyCount) dependencies)")

        } catch {
            print("❌ Auto-breakdown failed for '\(goal.title)': \(error)")
            learningEngine.observeAutopilotAction(accepted: false)
        }
    }

    private func autoActivate(_ goal: Goal, allGoals: [Goal], modelContext: ModelContext) async {
        do {
            try await lifecycleService.activate(goal: goal, within: allGoals, modelContext: modelContext)

            // Record in chat
            recordSystemMessage(
                goal: goal,
                content: "🤖 Autopilot: Goal activated"
            )

            print("🤖 Auto-activate: Activated '\(goal.title)'")

        } catch {
            print("❌ Auto-activate failed for '\(goal.title)': \(error)")
        }
    }

    private func autoUpdateProgress(_ goal: Goal) async {
        guard goal.hasSubtasks else { return }

        let oldProgress = goal.progress
        let newProgress = goal.aggregatedProgress()

        goal.progress = newProgress
        goal.updatedAt = Date()

        // Only record significant progress changes (>10%)
        if abs(newProgress - oldProgress) > 0.1 {
            recordSystemMessage(
                goal: goal,
                content: "🤖 Autopilot: Updated progress to \(Int(newProgress * 100))% based on subtasks"
            )

            print("🤖 Auto-progress: '\(goal.title)' updated to \(Int(newProgress * 100))%")
        }
    }

    private func autoComplete(_ goal: Goal, allGoals: [Goal], modelContext: ModelContext) async {
        await lifecycleService.complete(goal: goal, within: allGoals, modelContext: modelContext)

        // Learn from completion
        let timeTaken = goal.updatedAt.timeIntervalSince(goal.createdAt)
        learningEngine.observeGoalCompletion(goal: goal, timeTaken: timeTaken)
        learningEngine.observeAutopilotAction(accepted: true)

        recordSystemMessage(
            goal: goal,
            content: "🤖 Autopilot: All subtasks complete! Marked as done 🎉"
        )

        print("🤖 Auto-complete: '\(goal.title)' completed automatically")
    }

    // MARK: - Helper

    private func recordSystemMessage(goal: Goal, content: String) {
        // Note: This method should be called from a context where modelContext is available
        // For now, it's not used since AutopilotService doesn't have direct access to modelContext
        // Messages are typically added via the chat views which have modelContext access
        print("📝 Autopilot note for \(goal.title): \(content)")
    }
}