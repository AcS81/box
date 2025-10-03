//
//  UserContextService.swift
//  box
//
//  Created on 29.09.2025.
//

import Combine
import Foundation
import SwiftData

@MainActor
class UserContextService: ObservableObject {
    static let shared = UserContextService()

    @Published var userPreferences: UserPreferences = UserPreferences()
    @Published var workingHours: (start: Int, end: Int) = (9, 17)

    enum ContextStatus: Equatable {
        case idle
        case preparing
        case ready(Date)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var isPreparing: Bool {
            if case .preparing = self { return true }
            return false
        }
    }

    @Published private(set) var contextStatus: ContextStatus = .idle

    // Context cache to avoid expensive rebuilds
    private var cachedContext: AIContext?
    private var cacheKey: String = ""
    private var inflightTask: (key: String, task: Task<[ChatGoalSnapshot], Never>)?

    private init() {
        loadUserPreferences()
    }

    func buildContext(from goals: [Goal]) async -> AIContext {
        // Generate cache key from goal IDs and timestamps
        let key = generateCacheKey(for: goals)

        // Return cached context if valid
        if key == cacheKey, let cached = cachedContext {
            print("✓ Using cached context (performance boost)")
            contextStatus = .ready(Date())
            return cached
        }

        print("🔄 Building fresh context from \(goals.count) goals...")

        if let inflight = inflightTask, inflight.key == key {
            let snapshots = await inflight.task.value
            var context = makeBaseContext(from: goals)
            context.goalSnapshots = snapshots
            cachedContext = context
            cacheKey = key
            contextStatus = .ready(Date())
            inflightTask = nil
            return context
        }

        contextStatus = .preparing

        let baseContext = makeBaseContext(from: goals)
        let relevantGoals = selectRelevantGoals(from: goals, limit: 20)
        let relevantGoalIDs = relevantGoals.map { $0.id }
        let seedIDs = collectSeedIDs(for: relevantGoals)

        guard !seedIDs.isEmpty else {
            cachedContext = baseContext
            cacheKey = key
            contextStatus = .ready(Date())
            return baseContext
        }

        let seeds = makeGoalSeeds(from: goals, allowedIDs: seedIDs)

        let task = Task(priority: .userInitiated) { @Sendable () -> [ChatGoalSnapshot] in
            ContextSnapshotBuilder.buildSnapshots(
                for: relevantGoalIDs,
                using: seeds
            )
        }

        inflightTask = (key: key, task: task)

        let snapshots = await task.value
        inflightTask = nil

        var context = baseContext
        context.goalSnapshots = snapshots

        // Cache the result
        cachedContext = context
        cacheKey = key
        contextStatus = .ready(Date())
        print("✓ Context cached with key: \(key.prefix(12))...")

        return context
    }

    /// Invalidate the cache (call when goals are modified)
    func invalidateCache() {
        cachedContext = nil
        cacheKey = ""
        contextStatus = .idle
        print("🗑 Context cache invalidated")
    }

    func prewarmContext(for goals: [Goal]) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.buildContext(from: goals)
        }
    }

    /// Generate a cache key based on goal IDs and update times
    private func generateCacheKey(for goals: [Goal]) -> String {
        let signature = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: "|")
        return signature
    }

    /// Select most relevant goals for context (prioritize active, recent, high-priority)
    private func selectRelevantGoals(from goals: [Goal], limit: Int) -> [Goal] {
        guard goals.count > limit else { return goals }

        // Prioritize: active > high priority > recently updated
        let scored = goals.map { goal -> (goal: Goal, score: Int) in
            var score = 0
            if goal.activationState == .active { score += 100 }
            if goal.priority == .now { score += 50 }
            else if goal.priority == .next { score += 25 }

            // Recency bonus (up to 25 points for goals updated in last day)
            let hoursSinceUpdate = abs(goal.updatedAt.timeIntervalSinceNow) / 3600
            if hoursSinceUpdate < 24 {
                score += Int(25 - hoursSinceUpdate)
            }

            return (goal, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.goal }
    }

    private func extractUserPatterns(from goals: [Goal]) -> [String: Any] {
        var patterns: [String: Any] = [:]

        let categoryFrequency = Dictionary(grouping: goals, by: { $0.category })
            .mapValues { $0.count }
        patterns["preferredCategories"] = categoryFrequency

        let priorityDistribution = Dictionary(grouping: goals, by: { $0.priority.rawValue })
            .mapValues { $0.count }
        patterns["priorityPatterns"] = priorityDistribution

        let progressSpeeds = goals.compactMap { goal -> Double? in
            let timeElapsed = goal.updatedAt.timeIntervalSince(goal.createdAt)
            guard timeElapsed > 0 else { return nil }
            return goal.progress / timeElapsed
        }

        if !progressSpeeds.isEmpty {
            let averageProgressSpeed = progressSpeeds.reduce(0, +) / Double(progressSpeeds.count)
            patterns["averageProgressSpeed"] = averageProgressSpeed
        } else {
            patterns["averageProgressSpeed"] = 0.0
        }

        let completionTimes = goals
            .filter { $0.progress >= 1.0 }
            .map { $0.updatedAt.timeIntervalSince($0.createdAt) }

        if !completionTimes.isEmpty {
            let averageCompletionTime = completionTimes.reduce(0, +) / Double(completionTimes.count)
            patterns["averageCompletionTime"] = averageCompletionTime
        }

        return patterns
    }

    private func makeBaseContext(from goals: [Goal]) -> AIContext {
        let recentGoals = goals.sorted { $0.updatedAt > $1.updatedAt }
        let patterns = extractUserPatterns(from: goals)

        return AIContext(
            goals: recentGoals,
            patterns: patterns,
            preferredHours: workingHours
        )
    }

    private func makeGoalSeeds(from goals: [Goal], allowedIDs: Set<UUID>) -> [UUID: GoalSeed] {
        guard !allowedIDs.isEmpty else { return [:] }

        var seeds: [UUID: GoalSeed] = [:]
        seeds.reserveCapacity(allowedIDs.count)

        for goal in goals where allowedIDs.contains(goal.id) {
            let subgoalIDs = goal.sortedSubgoals.map { $0.id }
            let blockedBy = goal.incomingDependencies.compactMap { $0.prerequisite?.title }
            let unblocks = goal.outgoingDependencies.compactMap { $0.dependent?.title }

            seeds[goal.id] = GoalSeed(
                id: goal.id,
                title: goal.title,
                content: goal.content,
                activationState: goal.activationState.rawValue,
                isLocked: goal.isLocked,
                progress: goal.progress,
                priority: goal.priority.rawValue,
                category: goal.category,
                availableActions: goal.availableChatActions,
                eventCount: goal.scheduledEvents.count,
                revisionCount: goal.revisionHistory.count,
                parentID: goal.parent?.id,
                subgoalIDs: subgoalIDs,
                blockedBy: blockedBy,
                unblocks: unblocks
            )
        }

        return seeds
    }

    private func collectSeedIDs(for goals: [Goal]) -> Set<UUID> {
        var ids: Set<UUID> = []

        func includeDescendants(of goal: Goal) {
            if !ids.insert(goal.id).inserted { return }
            if let children = goal.subgoals {
                for child in children {
                    includeDescendants(of: child)
                }
            }
        }

        for goal in goals {
            includeDescendants(of: goal)

            if let parent = goal.parent {
                ids.insert(parent.id)

                if let siblings = parent.subgoals {
                    for sibling in siblings {
                        ids.insert(sibling.id)
                    }
                }

                if let grandParent = parent.parent {
                    ids.insert(grandParent.id)
                    if let cousins = grandParent.subgoals {
                        for cousin in cousins {
                            ids.insert(cousin.id)
                        }
                    }
                }
            }
        }

        return ids
    }

    private func loadUserPreferences() {
        // Load from UserDefaults or other persistent storage
        if let savedStart = UserDefaults.standard.object(forKey: "workingHours.start") as? Int,
           let savedEnd = UserDefaults.standard.object(forKey: "workingHours.end") as? Int {
            workingHours = (savedStart, savedEnd)
        }

        // Load other user preferences
        userPreferences.load()
    }

    func updateWorkingHours(start: Int, end: Int) {
        workingHours = (start, end)
        UserDefaults.standard.set(start, forKey: "workingHours.start")
        UserDefaults.standard.set(end, forKey: "workingHours.end")
    }

    func analyzeGoalCompletionPattern(_ goals: [Goal]) -> String {
        let completedGoals = goals.filter { $0.progress >= 1.0 }
        let totalGoals = goals.count

        guard totalGoals > 0 else { return "No goals to analyze" }

        let completionRate = Double(completedGoals.count) / Double(totalGoals)

        switch completionRate {
        case 0.8...:
            return "High achiever - consistently completes goals"
        case 0.6..<0.8:
            return "Good progress - completes most goals"
        case 0.4..<0.6:
            return "Moderate success - room for improvement"
        case 0.2..<0.4:
            return "Needs focus - consider fewer, more focused goals"
        default:
            return "Getting started - focus on building consistency"
        }
    }
}

private extension UserContextService {
    struct GoalSeed: Sendable {
        let id: UUID
        let title: String
        let content: String
        let activationState: String
        let isLocked: Bool
        let progress: Double
        let priority: String
        let category: String
        let availableActions: [String]
        let eventCount: Int
        let revisionCount: Int
        let parentID: UUID?
        let subgoalIDs: [UUID]
        let blockedBy: [String]
        let unblocks: [String]
    }
}

private enum ContextSnapshotBuilder {
    static func buildSnapshots(
        for goalIDs: [UUID],
        using seeds: [UUID: UserContextService.GoalSeed]
    ) -> [ChatGoalSnapshot] {
        goalIDs.compactMap { id in
            guard let seed = seeds[id] else { return nil }

            let subgoalTree = buildSubgoalTree(for: seed, seeds: seeds, visited: [])
            let summary = summarizeSubgoalTree(subgoalTree)

            let parentRelation = seed.parentID.flatMap { parentID in
                relationSnapshot(for: parentID, seeds: seeds, relation: "parent")
            }

            let siblingRelations = buildSiblingRelations(for: seed, seeds: seeds)
            let uncleRelations = buildUncleRelations(for: seed, seeds: seeds)

            return ChatGoalSnapshot(
                id: seed.id.uuidString,
                title: seed.title,
                content: seed.content,
                activationState: seed.activationState,
                isLocked: seed.isLocked,
                progress: seed.progress,
                priority: seed.priority,
                category: seed.category,
                subgoals: subgoalTree,
                availableActions: seed.availableActions,
                eventCount: seed.eventCount,
                revisionCount: seed.revisionCount,
                hasParent: seed.parentID != nil,
                parent: parentRelation,
                siblings: siblingRelations,
                uncles: uncleRelations,
                totalSubgoalCount: summary.total,
                atomicSubgoalCount: summary.atomic,
                maxSubgoalDepth: summary.depth
            )
        }
    }

    private static func relationSnapshot(
        for id: UUID,
        seeds: [UUID: UserContextService.GoalSeed],
        relation: String
    ) -> ChatGoalRelationSnapshot? {
        guard let seed = seeds[id] else { return nil }
        return ChatGoalRelationSnapshot(
            id: seed.id.uuidString,
            title: seed.title,
            activationState: seed.activationState,
            progress: seed.progress,
            priority: seed.priority,
            relation: relation
        )
    }

    private static func buildSiblingRelations(
        for seed: UserContextService.GoalSeed,
        seeds: [UUID: UserContextService.GoalSeed]
    ) -> [ChatGoalRelationSnapshot] {
        guard
            let parentID = seed.parentID,
            let parent = seeds[parentID]
        else { return [] }

        return parent.subgoalIDs
            .filter { $0 != seed.id }
            .compactMap { siblingID in
                relationSnapshot(for: siblingID, seeds: seeds, relation: "sibling")
            }
    }

    private static func buildUncleRelations(
        for seed: UserContextService.GoalSeed,
        seeds: [UUID: UserContextService.GoalSeed]
    ) -> [ChatGoalRelationSnapshot] {
        guard
            let parentID = seed.parentID,
            let parent = seeds[parentID],
            let grandParentID = parent.parentID,
            let grandParent = seeds[grandParentID]
        else { return [] }

        return grandParent.subgoalIDs
            .filter { $0 != parent.id }
            .compactMap { cousinID in
                relationSnapshot(for: cousinID, seeds: seeds, relation: "uncle")
            }
    }

    private static func buildSubgoalTree(
        for seed: UserContextService.GoalSeed,
        seeds: [UUID: UserContextService.GoalSeed],
        visited: Set<UUID>
    ) -> [ChatSubgoalSnapshot] {
        guard !seed.subgoalIDs.isEmpty else { return [] }

        var path = visited
        if path.contains(seed.id) {
            return []
        }
        path.insert(seed.id)

        return seed.subgoalIDs.compactMap { childID in
            guard let childSeed = seeds[childID] else { return nil }
            let children = buildSubgoalTree(for: childSeed, seeds: seeds, visited: path)
            return ChatSubgoalSnapshot(
                id: childSeed.id.uuidString,
                title: childSeed.title,
                progress: childSeed.progress,
                isComplete: childSeed.progress >= 1.0,
                isAtomic: children.isEmpty,
                blockedBy: childSeed.blockedBy,
                unblocks: childSeed.unblocks,
                children: children
            )
        }
    }

    private static func summarizeSubgoalTree(
        _ nodes: [ChatSubgoalSnapshot],
        currentDepth: Int = 1
    ) -> (total: Int, atomic: Int, depth: Int) {
        guard !nodes.isEmpty else { return (0, 0, currentDepth - 1) }

        var total = 0
        var atomic = 0
        var maxDepth = currentDepth

        for node in nodes {
            total += 1
            if node.isAtomic {
                atomic += 1
                maxDepth = max(maxDepth, currentDepth)
            }

            if !node.children.isEmpty {
                let summary = summarizeSubgoalTree(node.children, currentDepth: currentDepth + 1)
                total += summary.total
                atomic += summary.atomic
                maxDepth = max(maxDepth, summary.depth)
            }
        }

        return (total, atomic, maxDepth)
    }
}

struct UserPreferences {
    var preferredGoalTypes: [String] = []
    var workStyle: WorkStyle = .balanced
    var motivationStyle: MotivationStyle = .encouraging
    var reminderFrequency: ReminderFrequency = .daily

    enum WorkStyle: String, CaseIterable {
        case focused = "Deep focus sessions"
        case balanced = "Balanced work-life approach"
        case flexible = "Flexible scheduling"
    }

    enum MotivationStyle: String, CaseIterable {
        case encouraging = "Encouraging and supportive"
        case direct = "Direct and results-focused"
        case analytical = "Data-driven insights"
    }

    enum ReminderFrequency: String, CaseIterable {
        case never = "Never"
        case daily = "Daily"
        case weekly = "Weekly"
        case custom = "Custom"
    }

    mutating func load() {
        if let savedWorkStyle = UserDefaults.standard.string(forKey: "userPreferences.workStyle"),
           let workStyle = WorkStyle(rawValue: savedWorkStyle) {
            self.workStyle = workStyle
        }

        if let savedMotivationStyle = UserDefaults.standard.string(forKey: "userPreferences.motivationStyle"),
           let motivationStyle = MotivationStyle(rawValue: savedMotivationStyle) {
            self.motivationStyle = motivationStyle
        }

        if let savedReminderFreq = UserDefaults.standard.string(forKey: "userPreferences.reminderFrequency"),
           let reminderFreq = ReminderFrequency(rawValue: savedReminderFreq) {
            self.reminderFrequency = reminderFreq
        }

        self.preferredGoalTypes = UserDefaults.standard.stringArray(forKey: "userPreferences.goalTypes") ?? []
    }

    func save() {
        UserDefaults.standard.set(workStyle.rawValue, forKey: "userPreferences.workStyle")
        UserDefaults.standard.set(motivationStyle.rawValue, forKey: "userPreferences.motivationStyle")
        UserDefaults.standard.set(reminderFrequency.rawValue, forKey: "userPreferences.reminderFrequency")
        UserDefaults.standard.set(preferredGoalTypes, forKey: "userPreferences.goalTypes")
    }
}