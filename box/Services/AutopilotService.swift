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
    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 3600 // 1 hour

    private init() {
        self.aiService = AIService.shared
        self.userContextService = UserContextService.shared
        self.learningEngine = AutopilotLearningEngine.shared
        // Note: lifecycleService will be injected when starting
        self.lifecycleService = GoalLifecycleService(
            aiService: AIService.shared,
            calendarService: CalendarService(),
            userContextService: UserContextService.shared
        )
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isRunning else { return }

        isRunning = true
        print("🤖 Autopilot monitoring started (checking every \(Int(checkInterval / 60)) minutes)")

        // Check immediately on start
        Task {
            await performAutopilotCheck()
        }

        // Schedule periodic checks
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performAutopilotCheck()
            }
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
        isRunning = false
        print("🤖 Autopilot monitoring stopped")
    }

    // MARK: - Core Logic

    func performAutopilotCheck() async {
        print("🤖 Autopilot check started...")
        lastCheckDate = Date()

        // This needs to be called with actual goals and modelContext from the app
        // Will be triggered via notification or direct call from ContentView
    }

    func processAutopilotGoals(_ goals: [Goal], modelContext: ModelContext) async {
        let autopilotGoals = goals.filter { $0.isAutopilotEnabled && !$0.isLocked }

        guard !autopilotGoals.isEmpty else {
            print("🤖 No autopilot goals found")
            return
        }

        print("🤖 Processing \(autopilotGoals.count) autopilot goal(s)...")

        for goal in autopilotGoals {
            await processGoal(goal, allGoals: goals, modelContext: modelContext)
        }

        print("🤖 Autopilot check complete")
    }

    private func processGoal(_ goal: Goal, allGoals: [Goal], modelContext: ModelContext) async {
        // Check each condition and take action

        // 1. Auto-breakdown if needed
        if shouldBreakdown(goal) {
            await autoBreakdown(goal, allGoals: allGoals, modelContext: modelContext)
        }

        // 2. Auto-activate if ready
        if shouldActivate(goal) {
            await autoActivate(goal, allGoals: allGoals, modelContext: modelContext)
        }

        // 3. Auto-update progress based on subgoals
        if shouldUpdateProgress(goal) {
            await autoUpdateProgress(goal)
        }

        // 4. Auto-complete if all subgoals done
        if shouldComplete(goal) {
            await autoComplete(goal, allGoals: allGoals, modelContext: modelContext)
        }

        // 5. Nudge if stagnant
        if shouldNudge(goal) {
            await autoNudge(goal)
        }
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

    private func shouldNudge(_ goal: Goal) -> Bool {
        // Nudge if: Stagnant for 7+ days + active + incomplete
        let stagnantThreshold: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let isStagnant = Date().timeIntervalSince(goal.updatedAt) >= stagnantThreshold
        let isActive = goal.activationState == .active
        let isIncomplete = goal.progress < 1.0

        return isStagnant && isActive && isIncomplete
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
            let plan = try await lifecycleService.generateActivationPlan(for: goal, within: allGoals)

            try await lifecycleService.confirmActivation(
                goal: goal,
                plan: plan,
                within: allGoals,
                modelContext: modelContext
            )

            // Record in chat
            recordSystemMessage(
                goal: goal,
                content: "🤖 Autopilot: Activated with \(plan.events.count) focus session\(plan.events.count == 1 ? "" : "s")"
            )

            print("🤖 Auto-activate: Scheduled '\(goal.title)' with \(plan.events.count) sessions")

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

    private func autoNudge(_ goal: Goal) async {
        // Add a nudge message to chat
        let daysSinceUpdate = Int(Date().timeIntervalSince(goal.updatedAt) / 86400)

        recordSystemMessage(
            goal: goal,
            content: "🤖 Autopilot: This goal hasn't moved in \(daysSinceUpdate) days. Need help breaking through?"
        )

        print("🤖 Auto-nudge: Sent reminder for '\(goal.title)'")
    }

    // MARK: - Helper

    private func recordSystemMessage(goal: Goal, content: String) {
        // Note: This method should be called from a context where modelContext is available
        // For now, it's not used since AutopilotService doesn't have direct access to modelContext
        // Messages are typically added via the chat views which have modelContext access
        print("📝 Autopilot note for \(goal.title): \(content)")
    }
}