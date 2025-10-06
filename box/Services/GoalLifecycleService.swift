//
//  GoalLifecycleService.swift
//  box
//
//  Created on 29.09.2025.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class GoalLifecycleService: ObservableObject {
    enum LifecycleError: LocalizedError {
        case goalLocked
        case activationFailed(String)

        var errorDescription: String? {
            switch self {
            case .goalLocked:
                return "Goal is locked and cannot be modified."
            case .activationFailed(let reason):
                return reason
            }
        }
    }

    @Published private(set) var processingGoals: Set<UUID> = []
    @Published private(set) var lastError: String?

    private let aiService: AIService
    private let userContextService: UserContextService

    init(
        aiService: AIService,
        userContextService: UserContextService
    ) {
        self.aiService = aiService
        self.userContextService = userContextService
    }

    func isProcessing(goalID: Goal.ID) -> Bool {
        processingGoals.contains(goalID)
    }

    func lock(goal: Goal, within goals: [Goal], modelContext: ModelContext) async {
        guard !goal.isLocked else { return }
        lastError = nil
        setProcessing(goal.id, isProcessing: true)

        let context = await userContextService.buildContext(from: goals)

        var summary: String?
        do {
            summary = try await aiService.summarizeProgress(for: goal, context: context)
        } catch {
            lastError = error.localizedDescription
        }

        let snapshot = GoalSnapshot(
            title: goal.title,
            content: goal.content,
            aiSummary: summary,
            category: goal.category,
            priority: goal.priority.rawValue,
            progress: goal.progress
        )
        modelContext.insert(snapshot)
        snapshot.goalID = goal.id
        goal.lock(with: snapshot)
        goal.updatedAt = .now

        setProcessing(goal.id, isProcessing: false)
    }

    func unlock(goal: Goal, reason: String? = nil) {
        guard goal.isLocked else { return }
        goal.unlock(reason: reason)
        goal.updatedAt = .now
    }

    func regenerate(goal: Goal, within goals: [Goal], modelContext: ModelContext) async throws {
        guard !goal.isLocked else {
            throw LifecycleError.goalLocked
        }

        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        let context = await userContextService.buildContext(from: goals)
        let input = "Regenerate this goal with a refined framing, clear description, and motivational tone.\nTitle: \(goal.title)\nDescription: \(goal.content)"

        let response = try await aiService.createGoal(from: input, context: context)

        goal.title = response.title
        goal.content = response.content
        goal.category = response.category
        goal.priority = Goal.Priority(rawValue: response.priority.capitalized) ?? goal.priority
        GoalCreationMapper.apply(response, to: goal, referenceDate: .now, modelContext: modelContext)
        goal.recordRegeneration(summary: "Card regenerated", rationale: "AI provided refreshed framing")
        goal.updatedAt = .now
    }

    func activate(goal: Goal, within goals: [Goal], modelContext: ModelContext) async throws {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        guard !goal.isLocked else {
            throw LifecycleError.goalLocked
        }

        goal.activate(at: .now, rationale: "Goal activated")
        goal.updatedAt = .now

        await refreshMirrorCard(for: goal, within: goals, modelContext: modelContext, tips: [])
    }

    func deactivate(goal: Goal, reason: String? = nil, modelContext: ModelContext) async {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        goal.deactivate(to: .draft, rationale: reason)
        goal.updatedAt = .now

        await removeMirrorCard(for: goal, modelContext: modelContext)
    }

    private func setProcessing(_ goalID: UUID, isProcessing: Bool) {
        if isProcessing {
            processingGoals.insert(goalID)
        } else {
            processingGoals.remove(goalID)
        }
    }


    private func refreshMirrorCard(
        for goal: Goal,
        within goals: [Goal],
        modelContext: ModelContext,
        tips: [String]
    ) async {
        let context = await userContextService.buildContext(from: goals)

        do {
            let response = try await aiService.generateMirrorCard(for: goal, context: context)

            let descriptor = FetchDescriptor<AIMirrorCard>()
            let mirrorCards = (try? modelContext.fetch(descriptor)) ?? []

            let card: AIMirrorCard
            if let existing = mirrorCards.first(where: { $0.relatedGoalId == goal.id }) {
                card = existing
            } else {
                let newCard = AIMirrorCard(
                    title: goal.title,
                    interpretation: response.aiInterpretation,
                    relatedGoalId: goal.id
                )
                modelContext.insert(newCard)
                card = newCard
            }

            var actions = response.suggestedActions
            if !tips.isEmpty {
                actions.append(contentsOf: tips.map { "Tip: \($0)" })
            }

            card.aiInterpretation = response.aiInterpretation
            card.suggestedActions = actions
            card.confidence = response.confidence
            card.emotionalTone = response.emotionalTone
            card.insights = response.insights ?? []

            let snapshot = AIMirrorSnapshot(
                aiInterpretation: response.aiInterpretation,
                suggestedActions: actions,
                confidence: response.confidence,
                emotionalTone: response.emotionalTone,
                insights: response.insights ?? [],
                relatedGoalId: goal.id
            )
            snapshot.capturedAt = Date()
            modelContext.insert(snapshot)
            card.snapshots.append(snapshot)

            if card.snapshots.count > 20 {
                card.snapshots
                    .sorted { $0.capturedAt > $1.capturedAt }
                    .dropFirst(20)
                    .forEach { oldSnapshot in
                        modelContext.delete(oldSnapshot)
                    }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func removeMirrorCard(for goal: Goal, modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<AIMirrorCard>()
        let mirrorCards = (try? modelContext.fetch(descriptor)) ?? []

        if let existing = mirrorCards.first(where: { $0.relatedGoalId == goal.id }) {
            existing.aiInterpretation = "Goal is paused. Mirror mode will refresh when reactivated."
            existing.suggestedActions = []
            existing.confidence = 0.2
            existing.emotionalTone = "paused"
            existing.insights = ["AI mirror on standby until goal resumes"]

            let snapshot = AIMirrorSnapshot(
                aiInterpretation: existing.aiInterpretation,
                suggestedActions: [],
                confidence: 0.2,
                emotionalTone: "paused",
                insights: existing.insights,
                relatedGoalId: goal.id
            )
            snapshot.capturedAt = Date()
            modelContext.insert(snapshot)
            existing.snapshots.append(snapshot)

            if existing.snapshots.count > 20 {
                existing.snapshots
                    .sorted { $0.capturedAt > $1.capturedAt }
                    .dropFirst(20)
                    .forEach { oldSnapshot in
                        modelContext.delete(oldSnapshot)
                    }
            }
        }
    }

    // MARK: - Additional Lifecycle Operations

    func delete(goal: Goal, within goals: [Goal], modelContext: ModelContext) async throws {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        // Remove mirror cards
        let descriptor = FetchDescriptor<AIMirrorCard>()
        let mirrorCards = (try? modelContext.fetch(descriptor)) ?? []
        if let mirrorCard = mirrorCards.first(where: { $0.relatedGoalId == goal.id }) {
            modelContext.delete(mirrorCard)
        }

        // Delete subgoals recursively
        if let subgoals = goal.subgoals {
            for subgoal in subgoals {
                try await delete(goal: subgoal, within: goals, modelContext: modelContext)
            }
        }

        // Delete the goal itself
        modelContext.delete(goal)
    }

    func complete(goal: Goal, within goals: [Goal], modelContext: ModelContext) async {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        // Mark as completed
        goal.deactivate(to: .completed, rationale: "Goal marked as completed")
        goal.progress = 1.0
        goal.updatedAt = .now

        // Update mirror card
        await refreshMirrorCard(for: goal, within: goals, modelContext: modelContext, tips: ["Congratulations on completing this goal!"])
    }

    func updateGoal(_ goal: Goal, title: String? = nil, content: String? = nil, category: String? = nil, priority: Goal.Priority? = nil) {
        if let title = title, !title.isEmpty {
            goal.title = title
        }
        if let content = content {
            goal.content = content
        }
        if let category = category, !category.isEmpty {
            goal.category = category
        }
        if let priority = priority {
            goal.priority = priority
        }

        goal.updatedAt = .now
        // Create a revision record for the update
        let revision = GoalRevision(summary: "Goal updated", rationale: "Manual edit")
        revision.goalID = goal.id
        goal.revisionHistory.append(revision)
    }
}

