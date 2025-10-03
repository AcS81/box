//
//  AIActionExecutor.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import SwiftData

@MainActor
class AIActionExecutor {
    private let lifecycleService: GoalLifecycleService
    private let aiService: AIService
    private let userContextService: UserContextService

    init(lifecycleService: GoalLifecycleService, aiService: AIService, userContextService: UserContextService) {
        self.lifecycleService = lifecycleService
        self.aiService = aiService
        self.userContextService = userContextService
    }

    // MARK: - Main Execution

    func execute(
        _ action: AIAction,
        modelContext: ModelContext,
        goals: [Goal],
        fallbackGoal: Goal? = nil
    ) async throws -> ActionResult {
        // Execute based on action type
        switch action.type {
        // Creation - doesn't require existing goal
        case .create_goal:
            return try await createGoal(action: action, goals: goals, modelContext: modelContext)

        // Bulk/general operations that don't target a single goal
        case .bulk_delete:
            return try await bulkDeleteGoals(action: action, goals: goals, modelContext: modelContext)

        case .bulk_archive:
            return await bulkArchiveGoals(action: action, goals: goals)

        case .bulk_complete:
            return await bulkCompleteGoals(action: action, goals: goals, modelContext: modelContext)

        case .merge_goals:
            return try await mergeGoals(action: action, goals: goals, modelContext: modelContext)

        case .reorder_goals:
            return try reorderGoals(action: action, goals: goals, modelContext: modelContext)

        case .chat:
            return ActionResult(success: true, message: "Continuing conversation")

        default:
            break
        }

        guard let goal = resolveGoal(
            for: action,
            within: goals,
            fallbackGoal: fallbackGoal,
            modelContext: modelContext
        ) else {
            throw ActionError.goalNotFound
        }

        // Validate action is available for the resolved goal
        guard goal.availableChatActions.contains(action.type.rawValue) else {
            throw ActionError.actionNotAvailable(action.type.rawValue)
        }

        switch action.type {
        // Lifecycle operations
        case .activate_goal:
            return try await activateGoal(goal, goals: goals, modelContext: modelContext)

        case .deactivate_goal:
            return await deactivateGoal(goal, modelContext: modelContext)

        case .delete_goal:
            return try await deleteGoal(goal, goals: goals, modelContext: modelContext)

        case .complete_goal:
            return await completeGoal(goal, goals: goals, modelContext: modelContext)

        case .lock_goal:
            return await lockGoal(goal, goals: goals, modelContext: modelContext)

        case .unlock_goal:
            return unlockGoal(goal)

        case .regenerate_goal:
            return try await regenerateGoal(goal, goals: goals, modelContext: modelContext)

        // Goal modifications
        case .edit_title, .edit_content, .edit_category:
            return try editGoal(goal, action: action)

        case .set_progress:
            return try setProgress(goal, action: action)

        case .change_priority:
            return try changePriority(goal, action: action)

        case .mark_incomplete:
            return markIncomplete(goal)

        case .reactivate:
            return try await reactivateGoal(goal, goals: goals, modelContext: modelContext)

        // Subgoal operations
        case .breakdown:
            return try await breakdownGoal(goal, goals: goals, modelContext: modelContext)

        case .create_subgoal:
            return try createSubgoal(goal, action: action, modelContext: modelContext)

        case .update_subgoal:
            return try updateSubgoal(goal, action: action, modelContext: modelContext)

        case .complete_subgoal:
            return try completeSubgoal(goal, action: action, modelContext: modelContext)

        case .delete_subgoal:
            return try deleteSubgoal(goal, action: action, modelContext: modelContext)

        // Query operations
        case .view_subgoals:
            return viewSubgoals(goal)

        case .view_history:
            return viewHistory(goal)

        case .summarize:
            return try await summarizeGoal(goal, goals: goals)

        case .bulk_delete, .bulk_archive, .bulk_complete, .merge_goals, .reorder_goals, .chat:
            preconditionFailure("Bulk or general actions should be handled before resolving a goal")

        @unknown default:
            throw ActionError.notImplemented(action.type.rawValue)
        }
    }

    func executeAll(
        _ actions: [AIAction],
        modelContext: ModelContext,
        goals: [Goal],
        fallbackGoal: Goal? = nil
    ) async throws -> [ActionResult] {
        var results: [ActionResult] = []

        for action in actions {
            do {
                let result = try await execute(
                    action,
                    modelContext: modelContext,
                    goals: goals,
                    fallbackGoal: fallbackGoal
                )
                results.append(result)
            } catch {
                results.append(ActionResult(success: false, message: error.localizedDescription))
            }
        }

        return results
    }

    private func cleanedUUID(from raw: String?) -> UUID? {
        guard let string = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return UUID(uuidString: string)
    }

    private func cleanedString(from raw: String?) -> String? {
        guard let string = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }

    private func resolveGoal(
        for action: AIAction,
        within goals: [Goal],
        fallbackGoal: Goal?,
        modelContext: ModelContext
    ) -> Goal? {
        if let uuid = cleanedUUID(from: action.goalId) {
            if let matchedGoal = goals.first(where: { $0.id == uuid }) {
                return matchedGoal
            }

            let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == uuid })
            if let fetchedGoal = try? modelContext.fetch(descriptor).first {
                return fetchedGoal
            }
        }

        return fallbackGoal
    }

    private func resolveSubgoal(
        withId subgoalId: String,
        parent goal: Goal,
        modelContext: ModelContext
    ) -> Goal? {
        let trimmed = subgoalId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let subgoal = goal.subgoals?.first(where: { $0.id.uuidString == trimmed }) {
            return subgoal
        }

        guard let uuid = UUID(uuidString: trimmed) else { return nil }

        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == uuid })
        guard let fetchedSubgoal = try? modelContext.fetch(descriptor).first else { return nil }

        if let parent = fetchedSubgoal.parent, parent.id != goal.id {
            return nil
        }

        if fetchedSubgoal.parent == nil {
            fetchedSubgoal.parent = goal
        }

        return fetchedSubgoal
    }

    // MARK: - Lifecycle Operations

    private func activateGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        try await lifecycleService.activate(goal: goal, within: goals, modelContext: modelContext)
        let eventCount = goal.scheduledEvents.count
        return ActionResult(
            success: true,
            message: "Activated '\(goal.title)' with \(eventCount) calendar event\(eventCount == 1 ? "" : "s")"
        )
    }

    private func deactivateGoal(_ goal: Goal, modelContext: ModelContext) async -> ActionResult {
        await lifecycleService.deactivate(goal: goal, reason: "Deactivated via chat", modelContext: modelContext)
        return ActionResult(success: true, message: "Deactivated '\(goal.title)'")
    }

    private func deleteGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        let title = goal.title
        try await lifecycleService.delete(goal: goal, within: goals, modelContext: modelContext)
        return ActionResult(success: true, message: "Deleted '\(title)'")
    }

    private func completeGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async -> ActionResult {
        await lifecycleService.complete(goal: goal, within: goals, modelContext: modelContext)
        return ActionResult(success: true, message: "Completed '\(goal.title)' 🎉")
    }

    private func lockGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async -> ActionResult {
        await lifecycleService.lock(goal: goal, within: goals, modelContext: modelContext)
        return ActionResult(success: true, message: "Locked '\(goal.title)'")
    }

    private func unlockGoal(_ goal: Goal) -> ActionResult {
        lifecycleService.unlock(goal: goal, reason: "Unlocked via chat")
        return ActionResult(success: true, message: "Unlocked '\(goal.title)'")
    }

    private func regenerateGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        try await lifecycleService.regenerate(goal: goal, within: goals, modelContext: modelContext)
        return ActionResult(success: true, message: "Regenerated '\(goal.title)' with fresh AI perspective")
    }

    private func reactivateGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        goal.deactivate(to: .draft, rationale: "Reactivated via chat")
        goal.progress = 0.0
        goal.updatedAt = .now
        return ActionResult(success: true, message: "Reactivated '\(goal.title)'")
    }

    // MARK: - Goal Creation

    private func createGoal(action: AIAction, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        guard let params = action.parameters,
              let title = params["title"]?.stringValue, !title.isEmpty else {
            throw ActionError.invalidParameters
        }

        let content = params["content"]?.stringValue ?? ""
        let priorityStr = params["priority"]?.stringValue ?? "next"
        let category = params["category"]?.stringValue ?? "General"

        // Build input for AI processing
        let input = content.isEmpty ? title : "\(title)\n\(content)"
        let context = await userContextService.buildContext(from: goals)

        // Use AI to generate full goal structure
        let response = try await aiService.createGoal(from: input, context: context)

        // Create new goal from AI response
        let goal = Goal(
            title: response.title,
            content: response.content,
            category: response.category.isEmpty ? category : response.category,
            priority: Goal.Priority(rawValue: response.priority.capitalized) ?? Goal.Priority(rawValue: priorityStr.capitalized) ?? .next
        )

        // Apply AI-generated structure (phases, roadmap, etc.)
        GoalCreationMapper.apply(response, to: goal, referenceDate: .now, modelContext: modelContext)

        // Insert into context
        modelContext.insert(goal)

        return ActionResult(
            success: true,
            message: "Created goal '\(goal.title)'",
            data: ["goalId": goal.id.uuidString]
        )
    }

    // MARK: - Goal Modifications

    private func editGoal(_ goal: Goal, action: AIAction) throws -> ActionResult {
        guard let params = action.parameters else {
            throw ActionError.invalidParameters
        }

        var changes: [String] = []

        switch action.type {
        case .edit_title:
            if let title = params["title"]?.stringValue, !title.isEmpty {
                goal.title = title
                changes.append("title")
            }
        case .edit_content:
            if let content = params["content"]?.stringValue {
                goal.content = content
                changes.append("description")
            }
        case .edit_category:
            if let category = params["category"]?.stringValue, !category.isEmpty {
                goal.category = category
                changes.append("category")
            }
        default:
            break
        }

        goal.updatedAt = .now

        let changesStr = changes.joined(separator: " and ")
        return ActionResult(success: true, message: "Updated \(changesStr) for '\(goal.title)'")
    }

    private func setProgress(_ goal: Goal, action: AIAction) throws -> ActionResult {
        guard let params = action.parameters,
              let progress = params["progress"]?.doubleValue
        else {
            throw ActionError.invalidParameters
        }

        let clampedProgress = min(max(progress, 0), 1.0)
        goal.progress = clampedProgress
        goal.updatedAt = .now

        return ActionResult(
            success: true,
            message: "Set progress to \(Int(clampedProgress * 100))% for '\(goal.title)'"
        )
    }

    private func changePriority(_ goal: Goal, action: AIAction) throws -> ActionResult {
        guard let params = action.parameters,
              let priorityStr = params["priority"]?.stringValue,
              let priority = Goal.Priority(rawValue: priorityStr.capitalized)
        else {
            throw ActionError.invalidParameters
        }

        goal.priority = priority
        goal.updatedAt = .now

        return ActionResult(success: true, message: "Changed priority to \(priority.rawValue) for '\(goal.title)'")
    }

    private func markIncomplete(_ goal: Goal) -> ActionResult {
        goal.progress = 0.0
        goal.deactivate(to: .draft, rationale: "Marked incomplete via chat")
        goal.updatedAt = .now
        return ActionResult(success: true, message: "Marked '\(goal.title)' as incomplete")
    }

    // MARK: - Subgoal Operations

    private func breakdownGoal(_ goal: Goal, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        let context = await userContextService.buildContext(from: goals)
        let response = try await aiService.breakdownGoal(goal, context: context)
        let result = GoalBreakdownBuilder.apply(response: response, to: goal, in: modelContext)

        goal.hasBeenBrokenDown = true
        goal.updatedAt = .now

        let atomicCount = max(result.atomicTaskCount, result.createdGoals.count)
        let dependencySuffix = result.dependencyCount > 0 ? " and \(result.dependencyCount) dependency link\(result.dependencyCount == 1 ? "" : "s")" : ""

        return ActionResult(
            success: true,
            message: "Created \(atomicCount) atomic step\(atomicCount == 1 ? "" : "s")\(dependencySuffix) for '\(goal.title)'"
        )
    }

    private func createSubgoal(_ goal: Goal, action: AIAction, modelContext: ModelContext) throws -> ActionResult {
        guard let params = action.parameters,
              let title = cleanedString(from: params["title"]?.stringValue)
        else {
            throw ActionError.invalidParameters
        }

        let content = params["content"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let subgoal = Goal(
            title: title,
            content: content,
            category: goal.category,
            priority: .later
        )
        subgoal.parent = goal
        modelContext.insert(subgoal)

        goal.updatedAt = .now

        return ActionResult(success: true, message: "Created subtask '\(title)'")
    }

    private func updateSubgoal(_ goal: Goal, action: AIAction, modelContext: ModelContext) throws -> ActionResult {
        guard let params = action.parameters,
              let subgoalId = cleanedString(from: params["subgoalId"]?.stringValue),
              let subgoal = resolveSubgoal(withId: subgoalId, parent: goal, modelContext: modelContext)
        else {
            throw ActionError.subgoalNotFound
        }

        var changes: [String] = []

        if let title = cleanedString(from: params["title"]?.stringValue) {
            subgoal.title = title
            changes.append("title")
        }

        if let progress = params["progress"]?.doubleValue {
            subgoal.progress = min(max(progress, 0), 1.0)
            changes.append("progress")
        }

        subgoal.updatedAt = .now
        goal.updatedAt = .now

        let changesStr = changes.joined(separator: " and ")
        return ActionResult(success: true, message: "Updated \(changesStr) for subtask '\(subgoal.title)'")
    }

    private func completeSubgoal(_ goal: Goal, action: AIAction, modelContext: ModelContext) throws -> ActionResult {
        guard let params = action.parameters,
              let subgoalId = cleanedString(from: params["subgoalId"]?.stringValue),
              let subgoal = resolveSubgoal(withId: subgoalId, parent: goal, modelContext: modelContext)
        else {
            throw ActionError.subgoalNotFound
        }

        subgoal.progress = 1.0
        subgoal.updatedAt = .now
        goal.updatedAt = .now

        return ActionResult(success: true, message: "Completed subtask '\(subgoal.title)' ✓")
    }

    private func deleteSubgoal(_ goal: Goal, action: AIAction, modelContext: ModelContext) throws -> ActionResult {
        guard let params = action.parameters,
              let subgoalId = cleanedString(from: params["subgoalId"]?.stringValue),
              let subgoal = resolveSubgoal(withId: subgoalId, parent: goal, modelContext: modelContext)
        else {
            throw ActionError.subgoalNotFound
        }

        let title = subgoal.title
        modelContext.delete(subgoal)
        goal.updatedAt = .now

        return ActionResult(success: true, message: "Deleted subtask '\(title)'")
    }

    // MARK: - Query Operations

    private func viewSubgoals(_ goal: Goal) -> ActionResult {
        guard let subgoals = goal.subgoals, !subgoals.isEmpty else {
            return ActionResult(success: true, message: "No subtasks yet for '\(goal.title)'")
        }

        let total = goal.allDescendants().count
        let atomic = goal.leafDescendants().count
        let depth = goal.subgoalTreeDepth()

        var message = "Subtasks for '\(goal.title)':\n"
        message += "Total: \(total) • Atomic: \(atomic) • Depth: \(depth)\n"

        let treeLines = buildSubgoalLines(from: goal.sortedSubgoals)
        message += treeLines.map { "  \($0)" }.joined(separator: "\n")

        return ActionResult(success: true, message: message)
    }

    private func buildSubgoalLines(from subgoals: [Goal], prefix: [Int] = []) -> [String] {
        guard !subgoals.isEmpty else { return [] }

        var lines: [String] = []

        for (index, subgoal) in subgoals.enumerated() {
            let numberingComponents = prefix + [index + 1]
            let label = numberingComponents.map(String.init).joined(separator: ".")
            let status = subgoal.progress >= 1.0 ? "✓" : "○"
            var line = "\(label) \(status) \(subgoal.title) (\(Int(subgoal.progress * 100))%)"

            let blockers = summarizeTitles(from: subgoal.incomingDependencies.compactMap { $0.prerequisite?.title })
            if !blockers.isEmpty {
                line += " | wait for: \(blockers)"
            }

            let dependents = summarizeTitles(from: subgoal.outgoingDependencies.compactMap { $0.dependent?.title })
            if !dependents.isEmpty {
                line += " | unlocks: \(dependents)"
            }

            lines.append(line)

            let children = subgoal.sortedSubgoals
            if !children.isEmpty {
                lines += buildSubgoalLines(from: children, prefix: numberingComponents)
            }
        }

        return lines
    }

    private func summarizeTitles(from titles: [String]) -> String {
        let unique = Array(Set(titles)).sorted()
        guard !unique.isEmpty else { return "" }

        if unique.count <= 3 {
            return unique.joined(separator: ", ")
        }

        return unique.prefix(3).joined(separator: ", ") + " (+\(unique.count - 3))"
    }

    private func viewHistory(_ goal: Goal) -> ActionResult {
        let revisions = goal.revisionHistory
        guard !revisions.isEmpty else {
            return ActionResult(success: true, message: "No revision history for '\(goal.title)'")
        }

        var message = "History for '\(goal.title)':\n"
        for (idx, revision) in revisions.suffix(5).enumerated() {
            message += "\n\(idx + 1). \(revision.summary)"
            if let rationale = revision.rationale {
                message += " - \(rationale)"
            }
            message += " (\(revision.createdAt.timeAgo))"
        }

        if revisions.count > 5 {
            message += "\n... and \(revisions.count - 5) more"
        }

        return ActionResult(success: true, message: message)
    }

    private func summarizeGoal(_ goal: Goal, goals: [Goal]) async throws -> ActionResult {
        let context = await userContextService.buildContext(from: goals)
        let summary = try await aiService.summarizeProgress(for: goal, context: context)

        return ActionResult(success: true, message: summary)
    }

    // MARK: - Bulk Operations

    private func bulkDeleteGoals(action: AIAction, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        guard let params = action.parameters,
              let goalIdsArray = params["goalIds"]?.arrayValue else {
            throw ActionError.invalidParameters
        }

        let goalUUIDs = Set(goalIdsArray.compactMap { cleanedUUID(from: $0.stringValue) })
        guard !goalUUIDs.isEmpty else {
            throw ActionError.invalidParameters
        }

        let goalsToDelete = goals.filter { goalUUIDs.contains($0.id) }
        guard !goalsToDelete.isEmpty else {
            return ActionResult(success: false, message: "No goals found to delete")
        }

        var deletedCount = 0
        for goal in goalsToDelete {
            do {
                try await lifecycleService.delete(goal: goal, within: goals, modelContext: modelContext)
                deletedCount += 1
            } catch {
                print("❌ Failed to delete '\(goal.title)': \(error)")
            }
        }

        return ActionResult(
            success: true,
            message: "Deleted \(deletedCount) goal\(deletedCount == 1 ? "" : "s")"
        )
    }

    private func bulkArchiveGoals(action: AIAction, goals: [Goal]) async -> ActionResult {
        guard let params = action.parameters,
              let goalIdsArray = params["goalIds"]?.arrayValue else {
            return ActionResult(success: false, message: "Invalid parameters")
        }

        let goalUUIDs = Set(goalIdsArray.compactMap { cleanedUUID(from: $0.stringValue) })
        guard !goalUUIDs.isEmpty else {
            return ActionResult(success: false, message: "No goal IDs provided")
        }

        let goalsToArchive = goals.filter { goalUUIDs.contains($0.id) }
        guard !goalsToArchive.isEmpty else {
            return ActionResult(success: false, message: "No goals found to archive")
        }

        for goal in goalsToArchive {
            goal.deactivate(to: .archived, rationale: "Bulk archived via general chat")
            goal.updatedAt = Date()
        }

        return ActionResult(
            success: true,
            message: "Archived \(goalsToArchive.count) goal\(goalsToArchive.count == 1 ? "" : "s")"
        )
    }

    private func bulkCompleteGoals(action: AIAction, goals: [Goal], modelContext: ModelContext) async -> ActionResult {
        guard let params = action.parameters,
              let goalIdsArray = params["goalIds"]?.arrayValue else {
            return ActionResult(success: false, message: "Invalid parameters")
        }

        let goalUUIDs = Set(goalIdsArray.compactMap { cleanedUUID(from: $0.stringValue) })
        guard !goalUUIDs.isEmpty else {
            return ActionResult(success: false, message: "No goal IDs provided")
        }

        let goalsToComplete = goals.filter { goalUUIDs.contains($0.id) }
        guard !goalsToComplete.isEmpty else {
            return ActionResult(success: false, message: "No goals found to complete")
        }

        for goal in goalsToComplete {
            await lifecycleService.complete(goal: goal, within: goals, modelContext: modelContext)
        }

        return ActionResult(
            success: true,
            message: "Completed \(goalsToComplete.count) goal\(goalsToComplete.count == 1 ? "" : "s") 🎉"
        )
    }

    // MARK: - Board Operations

    private func mergeGoals(action: AIAction, goals: [Goal], modelContext: ModelContext) async throws -> ActionResult {
        guard let params = action.parameters,
              let goalIdsArray = params["goalIds"]?.arrayValue else {
            throw ActionError.invalidParameters
        }

        let requestedUUIDs = goalIdsArray.compactMap { cleanedUUID(from: $0.stringValue) }
        var seen = Set<UUID>()
        var resolvedGoals: [Goal] = []

        for uuid in requestedUUIDs where !seen.contains(uuid) {

            if let inMemory = goals.first(where: { $0.id == uuid }) {
                resolvedGoals.append(inMemory)
                seen.insert(uuid)
                continue
            }

            let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == uuid })
            if let fetched = try modelContext.fetch(descriptor).first {
                resolvedGoals.append(fetched)
                seen.insert(uuid)
            }
        }

        guard resolvedGoals.count >= 2 else {
            throw ActionError.insufficientGoals
        }

        let lockedGoals = resolvedGoals.filter { $0.isLocked }
        if !lockedGoals.isEmpty {
            let titles = lockedGoals.map { "'\($0.title)'" }.joined(separator: ", ")
            throw ActionError.executionFailed("Cannot merge locked goals: \(titles)")
        }

        let primaryGoal = resolvedGoals[0]
        let additionalGoals = resolvedGoals.dropFirst()

        let existingContent = primaryGoal.content.trimmed
        var combinedContent: [String] = []
        if !existingContent.isEmpty {
            combinedContent.append(existingContent)
        }

        var mergedCount = 0
        var mergedTitles: [String] = []
        var maxProgress = primaryGoal.progress
        var hasActiveGoal = primaryGoal.activationState == .active
        var hasCompletedGoal = primaryGoal.activationState == .completed
        var hasDraftGoal = primaryGoal.activationState == .draft
        var hasArchivedGoal = primaryGoal.activationState == .archived
        var highestPriority = primaryGoal.priority
        var earliestTargetDate = primaryGoal.targetDate
        var latestRegeneration = primaryGoal.lastRegeneratedAt
        var earliestActivation = primaryGoal.activatedAt

        for goal in additionalGoals {
            let secondaryContent = goal.content.trimmed
            if !secondaryContent.isEmpty {
                combinedContent.append("Merged from \"\(goal.title)\":\n\(secondaryContent)")
            } else {
                combinedContent.append("Merged from \"\(goal.title)\"")
            }

            highestPriority = maxPriority(highestPriority, goal.priority)
            maxProgress = max(maxProgress, goal.progress)
            hasActiveGoal = hasActiveGoal || goal.activationState == .active
            hasCompletedGoal = hasCompletedGoal || goal.activationState == .completed
            hasDraftGoal = hasDraftGoal || goal.activationState == .draft
            hasArchivedGoal = hasArchivedGoal || goal.activationState == .archived

            if let target = goal.targetDate {
                if let current = earliestTargetDate {
                    if target < current { earliestTargetDate = target }
                } else {
                    earliestTargetDate = target
                }
            }

            if let regen = goal.lastRegeneratedAt {
                if let current = latestRegeneration {
                    if regen > current { latestRegeneration = regen }
                } else {
                    latestRegeneration = regen
                }
            }

            if let activated = goal.activatedAt {
                if let current = earliestActivation {
                    if activated < current { earliestActivation = activated }
                } else {
                    earliestActivation = activated
                }
            }

            primaryGoal.isAutopilotEnabled = primaryGoal.isAutopilotEnabled || goal.isAutopilotEnabled

            if let subgoals = goal.subgoals {
                let baseOrder = (primaryGoal.sortedSubgoals.last?.effectiveSortOrder ?? primaryGoal.effectiveSortOrder) + 1.0
                for (idx, subgoal) in subgoals.sorted(by: { $0.effectiveSortOrder < $1.effectiveSortOrder }).enumerated() {
                    subgoal.parent = primaryGoal
                    subgoal.sortOrder = baseOrder + Double(idx)
                }
            }

            // Note: Chat history migration is no longer needed
            // ChatEntry records are stored separately and scoped by goal ID
            // They will remain accessible via the unified timeline

            for revision in goal.revisionHistory {
                revision.goalID = primaryGoal.id
                primaryGoal.revisionHistory.append(revision)
            }
            goal.revisionHistory.removeAll()

            for link in goal.scheduledEvents {
                link.goalID = primaryGoal.id
                if !primaryGoal.scheduledEvents.contains(where: { $0.eventIdentifier == link.eventIdentifier }) {
                    primaryGoal.scheduledEvents.append(link)
                }
            }
            goal.scheduledEvents.removeAll()

            if let snapshot = goal.lockedSnapshot {
                snapshot.goalID = primaryGoal.id
            }

            let revision = GoalRevision(
                summary: "Merged goal",
                rationale: "Consolidated from \(goal.title)",
                snapshot: goal.lockedSnapshot
            )
            revision.goalID = primaryGoal.id
            primaryGoal.revisionHistory.append(revision)

            mergedTitles.append(goal.title)
            mergedCount += 1

            // Clean up mirror cards referencing the merged goal
            let descriptor = FetchDescriptor<AIMirrorCard>()
            let mirrorCards = (try? modelContext.fetch(descriptor)) ?? []
            let orphanCards = mirrorCards.filter { $0.relatedGoalId == goal.id }
            for card in orphanCards {
                modelContext.delete(card)
            }

            modelContext.delete(goal)
        }

        if !combinedContent.isEmpty {
            primaryGoal.content = combinedContent.joined(separator: "\n\n")
        }

        primaryGoal.priority = highestPriority
        primaryGoal.progress = maxProgress
        primaryGoal.targetDate = earliestTargetDate
        primaryGoal.lastRegeneratedAt = latestRegeneration
        primaryGoal.activatedAt = earliestActivation
        primaryGoal.activationState = resolvedActivationState(
            hasActive: hasActiveGoal,
            hasCompleted: hasCompletedGoal,
            hasDraft: hasDraftGoal,
            hasArchived: hasArchivedGoal,
            fallback: primaryGoal.activationState
        )
        primaryGoal.isActive = primaryGoal.activationState == .active
        primaryGoal.updatedAt = .now

        if mergedCount == 0 {
            return ActionResult(success: false, message: "No goals were merged")
        }

        let mergedList = mergedTitles.joined(separator: ", ")
        return ActionResult(
            success: true,
            message: "Merged \(mergedCount) goal\(mergedCount == 1 ? "" : "s") into '\(primaryGoal.title)'\(mergedList.isEmpty ? "" : " (\(mergedList))")"
        )
    }

    private func reorderGoals(action: AIAction, goals: [Goal], modelContext: ModelContext) throws -> ActionResult {
        guard let params = action.parameters,
              let orderedIdsArray = params["orderedIds"]?.arrayValue else {
            throw ActionError.invalidParameters
        }

        let orderedUUIDs = orderedIdsArray.compactMap { cleanedUUID(from: $0.stringValue) }
        var orderedGoals: [Goal] = []
        var seen = Set<UUID>()

        for uuid in orderedUUIDs where !seen.contains(uuid) {
            if let goal = goals.first(where: { $0.id == uuid }) {
                orderedGoals.append(goal)
                seen.insert(uuid)
            } else {
                let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == uuid })
                if let fetched = try? modelContext.fetch(descriptor).first {
                    orderedGoals.append(fetched)
                    seen.insert(uuid)
                }
            }
        }

        guard !orderedGoals.isEmpty else {
            throw ActionError.goalNotFound
        }

        let commonParent = orderedGoals.first?.parent
        guard orderedGoals.allSatisfy({ $0.parent?.id == commonParent?.id }) else {
            throw ActionError.executionFailed("Goals must share the same parent to reorder")
        }

        let siblings: [Goal]
        if let parent = commonParent {
            siblings = (parent.subgoals ?? []).sorted { lhs, rhs in
                let lhsOrder = lhs.effectiveSortOrder
                let rhsOrder = rhs.effectiveSortOrder
                if lhsOrder == rhsOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhsOrder < rhsOrder
            }
        } else {
            siblings = goals.filter { $0.parent == nil }.sorted { lhs, rhs in
                let lhsOrder = lhs.effectiveSortOrder
                let rhsOrder = rhs.effectiveSortOrder
                if lhsOrder == rhsOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhsOrder < rhsOrder
            }
        }

        var finalOrder: [Goal] = orderedGoals
        let orderedIds = Set(orderedGoals.map { $0.id })
        let remaining = siblings.filter { !orderedIds.contains($0.id) }
        finalOrder.append(contentsOf: remaining)

        for (index, goal) in finalOrder.enumerated() {
            goal.sortOrder = Double(index)
            goal.updatedAt = .now
        }

        if let parent = commonParent {
            parent.updatedAt = .now
        }

        return ActionResult(
            success: true,
            message: "Reordered \(orderedGoals.count) goal\(orderedGoals.count == 1 ? "" : "s")"
        )
    }

    private func maxPriority(_ lhs: Goal.Priority, _ rhs: Goal.Priority) -> Goal.Priority {
        switch (lhs, rhs) {
        case (.now, _), (_, .now):
            return .now
        case (.next, _), (_, .next):
            return .next
        default:
            return .later
        }
    }

    private func resolvedActivationState(
        hasActive: Bool,
        hasCompleted: Bool,
        hasDraft: Bool,
        hasArchived: Bool,
        fallback: Goal.ActivationState
    ) -> Goal.ActivationState {
        if hasActive {
            return .active
        }

        if hasCompleted && !hasDraft && !hasActive {
            return .completed
        }

        if hasArchived && !hasDraft && !hasCompleted && !hasActive {
            return .archived
        }

        return fallback
    }
}