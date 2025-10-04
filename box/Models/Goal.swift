//
//  Goal.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

@Model
class Goal {
    enum ActivationState: String, Codable, CaseIterable {
        case draft
        case active
        case completed
        case archived
    }

    enum Kind: String, Codable, CaseIterable {
        case event
        case campaign
        case hybrid
    }

    var id = UUID()
    var title: String = ""
    var content: String = ""
    var category: String = "General"
    var priority: Priority = Goal.Priority.next
    private var kindStorage: String = Goal.Kind.campaign.rawValue
    var isActive: Bool = false
    var activationState: ActivationState = Goal.ActivationState.draft
    var isLocked: Bool = false
    var progress: Double = 0.0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var targetDate: Date?
    var lastRegeneratedAt: Date?
    var activatedAt: Date?
    var completedAt: Date?  // When this step was actually completed (for timeline accuracy)
    var sortOrder: Double?

    var aiGlyph: String?
    var aiGlyphUpdatedAt: Date?

    // AI Autopilot mode: AI manages this goal automatically (enabled by default)
    var isAutopilotEnabled: Bool = true

    // Track if goal has been broken down to prevent duplicate breakdown attempts
    var hasBeenBrokenDown: Bool = false

    // Unified sequential step system (replaces GoalStop)
    var isSequentialStep: Bool = false  // true = this is a step in a sequence
    var orderIndexInParent: Int = 0     // position in sequence (0, 1, 2...)
    var outcome: String = ""            // what gets achieved at this step

    enum StepStatus: String, Codable, CaseIterable {
        case pending     // Future step not yet accessible
        case current     // Active step user is working on
        case completed   // Done - "until now"
        case unknown     // Not yet generated

        var icon: String {
            switch self {
            case .pending: return "lock.fill"
            case .current: return "play.circle.fill"
            case .completed: return "checkmark.circle.fill"
            case .unknown: return "questionmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .pending: return .gray
            case .current: return .orange
            case .completed: return .green
            case .unknown: return .purple
            }
        }
    }

    private var stepStatusStorage: String = StepStatus.unknown.rawValue
    var stepStatus: StepStatus {
        get { StepStatus(rawValue: stepStatusStorage) ?? .unknown }
        set { stepStatusStorage = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade) var subgoals: [Goal]?
    @Relationship(inverse: \Goal.subgoals) var parent: Goal?
    @Relationship(deleteRule: .cascade) var lockedSnapshot: GoalSnapshot?
    @Relationship(deleteRule: .cascade) var revisionHistory: [GoalRevision]
    @Relationship(deleteRule: .cascade) var scheduledEvents: [ScheduledEventLink]
    @Relationship(deleteRule: .cascade, inverse: \GoalDependency.prerequisite) var outgoingDependencies: [GoalDependency]
    @Relationship(deleteRule: .cascade, inverse: \GoalDependency.dependent) var incomingDependencies: [GoalDependency]
    @Relationship(deleteRule: .cascade) var targetMetric: GoalTargetMetric?
    @Relationship(deleteRule: .cascade) var phases: [GoalPhase]
    @Relationship(deleteRule: .cascade) var projections: [GoalProjection]
    
    enum Priority: String, Codable, CaseIterable {
        case now = "Now"
        case next = "Next"
        case later = "Later"
    }
    
    init(
        title: String,
        content: String = "",
        category: String = "General",
        priority: Priority = Goal.Priority.next,
        targetDate: Date? = nil,
        kind: Kind = Goal.Kind.campaign
    ) {
        self.title = title
        self.content = content
        self.category = category
        self.priority = priority
        self.targetDate = targetDate
        self.kindStorage = kind.rawValue
        self.revisionHistory = []
        self.scheduledEvents = []
        self.outgoingDependencies = []
        self.incomingDependencies = []
        self.phases = []
        self.projections = []
        self.sortOrder = Date().timeIntervalSinceReferenceDate
        self.aiGlyph = nil
        self.aiGlyphUpdatedAt = nil
    }

    var isEvent: Bool { kind == .event }

    var isCampaign: Bool { kind == .campaign }

    var hasTargetMetric: Bool { targetMetric != nil }

    var hasSubtasks: Bool {
        guard let subgoals else { return false }
        return !subgoals.isEmpty
    }

    // MARK: - Unified Sequential/Parallel Subgoals

    /// All sequential steps (stops) sorted by order
    var sequentialSteps: [Goal] {
        guard let subgoals else { return [] }
        return subgoals
            .filter { $0.isSequentialStep }
            .sorted { $0.orderIndexInParent < $1.orderIndexInParent }
    }

    /// All parallel branches (traditional subgoals)
    var parallelBranches: [Goal] {
        guard let subgoals else { return [] }
        return subgoals.filter { !$0.isSequentialStep }
    }

    /// Current active sequential step
    var currentSequentialStep: Goal? {
        sequentialSteps.first { $0.stepStatus == .current }
    }

    /// Next pending step in sequence
    var nextSequentialStep: Goal? {
        guard let current = currentSequentialStep else {
            return sequentialSteps.first { $0.stepStatus == .pending }
        }
        let nextIndex = current.orderIndexInParent + 1
        return sequentialSteps.first { $0.orderIndexInParent == nextIndex }
    }

    /// Completed sequential steps ("until now")
    var completedSequentialSteps: [Goal] {
        sequentialSteps.filter { $0.stepStatus == .completed }
    }

    /// Progress based on sequential steps
    var sequentialProgress: Double {
        let steps = sequentialSteps
        guard !steps.isEmpty else { return 0 }
        let completed = steps.filter { $0.stepStatus == .completed }.count
        return Double(completed) / Double(steps.count)
    }

    /// Whether this goal has sequential steps
    var hasSequentialSteps: Bool {
        !sequentialSteps.isEmpty
    }

    /// Whether this goal has parallel branches
    var hasParallelBranches: Bool {
        !parallelBranches.isEmpty
    }

    /// Complete current sequential step and activate next
    func advanceSequentialStep() {
        guard let current = currentSequentialStep else { return }

        // Mark current step as 100% complete
        current.progress = 1.0
        current.completedAt = Date()  // Track actual completion time

        // Lock current (becomes "until now")
        current.stepStatus = .completed
        current.lock(with: current.captureSnapshot())

        // Activate next if exists
        if let next = nextSequentialStep {
            next.stepStatus = .current
            next.progress = 0.0 // Reset next step progress
        }

        // Sync parent progress with sequential steps
        syncProgressWithSequentialSteps()
        updatedAt = Date()
    }

    /// Synchronize parent goal progress with sequential step completion
    func syncProgressWithSequentialSteps() {
        guard hasSequentialSteps else { return }
        progress = sequentialProgress
    }

    /// Mark sequential step complete and advance
    func completeSequentialStep(_ step: Goal) {
        guard sequentialSteps.contains(where: { $0.id == step.id }),
              step.stepStatus == .current else { return }

        step.progress = 1.0
        step.completedAt = Date()  // Track actual completion time
        step.stepStatus = .completed
        step.lock(with: step.captureSnapshot())

        // Activate next if exists
        let nextIndex = step.orderIndexInParent + 1
        if let next = sequentialSteps.first(where: { $0.orderIndexInParent == nextIndex }) {
            next.stepStatus = .current
            next.progress = 0.0
        }

        syncProgressWithSequentialSteps()
        updatedAt = Date()
    }

    /// Create a new sequential step as a child
    func createSequentialStep(title: String, outcome: String, targetDate: Date? = nil) -> Goal {
        let step = Goal(
            title: title,
            content: outcome,
            category: category,
            priority: priority
        )
        step.isSequentialStep = true
        step.orderIndexInParent = sequentialSteps.count
        step.outcome = outcome
        step.targetDate = targetDate
        step.stepStatus = sequentialSteps.isEmpty ? .current : .pending

        if subgoals == nil {
            subgoals = []
        }
        subgoals?.append(step)

        return step
    }

    var isLeaf: Bool {
        subgoals?.isEmpty ?? true
    }

    func allDescendants(includeSelf: Bool = false) -> [Goal] {
        var visited: Set<UUID> = []
        return collectDescendants(includeSelf: includeSelf, visited: &visited)
    }

    func leafDescendants() -> [Goal] {
        var visited: Set<UUID> = []
        return collectLeafDescendants(visited: &visited)
    }

    func subgoalTreeDepth() -> Int {
        var visited: Set<UUID> = []
        return subgoalTreeDepth(visited: &visited)
    }

    private func subgoalTreeDepth(visited: inout Set<UUID>) -> Int {
        if visited.contains(id) {
            return 0
        }

        visited.insert(id)
        defer { visited.remove(id) }

        guard let subgoals, !subgoals.isEmpty else { return 0 }

        var maxDepth = 0
        for subgoal in subgoals {
            let depth = subgoal.subgoalTreeDepth(visited: &visited)
            maxDepth = max(maxDepth, depth)
        }

        return 1 + maxDepth
    }

    func aggregatedProgress() -> Double {
        let leaves = leafDescendants()
        guard !leaves.isEmpty else { return progress }
        let total = leaves.reduce(0.0) { $0 + $1.progress }
        return total / Double(leaves.count)
    }

    private func collectDescendants(includeSelf: Bool, visited: inout Set<UUID>) -> [Goal] {
        if visited.contains(id) { return [] }
        visited.insert(id)

        var results: [Goal] = includeSelf ? [self] : []
        guard let subgoals else { return results }

        for subgoal in subgoals {
            results.append(contentsOf: subgoal.collectDescendants(includeSelf: true, visited: &visited))
        }

        return results
    }

    private func collectLeafDescendants(visited: inout Set<UUID>) -> [Goal] {
        if visited.contains(id) { return [] }
        visited.insert(id)

        guard let subgoals, !subgoals.isEmpty else {
            return [self]
        }

        return subgoals.flatMap { $0.collectLeafDescendants(visited: &visited) }
    }


    var isDraft: Bool {
        activationState == .draft
    }

    var isActivated: Bool {
        activationState == .active
    }

    func lock(with snapshot: GoalSnapshot) {
        guard !isLocked else { return }
        let before = captureSnapshot()
        snapshot.goalID = id
        lockedSnapshot = snapshot
        isLocked = true
        appendRevision(summary: "Card locked", rationale: snapshot.aiSummary, beforeSnapshot: before)
    }

    func unlock(reason: String? = nil) {
        guard isLocked else { return }
        let before = captureSnapshot()
        lockedSnapshot = nil
        isLocked = false
        appendRevision(summary: "Card unlocked", rationale: reason, beforeSnapshot: before)
    }

    func activate(at date: Date = .now, rationale: String? = nil) {
        guard activationState != .active else { return }
        let before = captureSnapshot()
        activationState = .active
        activatedAt = date
        isActive = true
        appendRevision(summary: "Card activated", rationale: rationale, beforeSnapshot: before)
    }

    func deactivate(to state: ActivationState = .draft, rationale: String? = nil) {
        guard activationState != state else { return }
        let before = captureSnapshot()
        activationState = state
        if state != .active {
            isActive = false
        }
        appendRevision(summary: "Card moved to \(state.rawValue)", rationale: rationale, beforeSnapshot: before)
    }

    func recordRegeneration(summary: String, rationale: String? = nil, snapshot: GoalSnapshot? = nil) {
        lastRegeneratedAt = .now
        if let snapshot {
            lockedSnapshot = snapshot
        }
        appendRevision(summary: summary, rationale: rationale)
    }

    func linkScheduledEvent(_ link: ScheduledEventLink) {
        guard !scheduledEvents.contains(where: { $0.eventIdentifier == link.eventIdentifier }) else { return }
        link.goalID = id
        scheduledEvents.append(link)
    }

    func unlinkScheduledEvent(withIdentifier identifier: String) {
        scheduledEvents.removeAll { $0.eventIdentifier == identifier }
    }

    private func appendRevision(summary: String, rationale: String?, beforeSnapshot: GoalSnapshot? = nil) {
        // Capture "after" snapshot
        let afterSnapshot = GoalSnapshot(
            title: title,
            content: content,
            category: category,
            priority: priority.rawValue,
            progress: progress
        )
        afterSnapshot.goalID = id

        let revision = GoalRevision(
            summary: summary,
            rationale: rationale,
            snapshot: afterSnapshot,
            beforeSnapshot: beforeSnapshot
        )
        revision.goalID = id
        revisionHistory.append(revision)
    }

    /// Capture current state as snapshot for before/after comparison
    func captureSnapshot() -> GoalSnapshot {
        let snapshot = GoalSnapshot(
            title: title,
            content: content,
            category: category,
            priority: priority.rawValue,
            progress: progress
        )
        snapshot.goalID = id
        return snapshot
    }

    // MARK: - Chat Actions

    var availableChatActions: [String] {
        var actions = [
            AIActionType.chat.rawValue,
            AIActionType.breakdown.rawValue,
            AIActionType.summarize.rawValue,
            AIActionType.view_subgoals.rawValue,
            AIActionType.view_history.rawValue
        ]

        // Lifecycle actions based on state
        if !isLocked {
            actions.append(AIActionType.lock_goal.rawValue)
            actions.append(AIActionType.regenerate_goal.rawValue)
            actions.append(AIActionType.delete_goal.rawValue)
            actions.append(AIActionType.edit_title.rawValue)
            actions.append(AIActionType.edit_content.rawValue)
            actions.append(AIActionType.edit_category.rawValue)
        }

        if isLocked {
            actions.append(AIActionType.unlock_goal.rawValue)
        }

        // Activation state actions
        switch activationState {
        case .draft:
            actions.append(AIActionType.activate_goal.rawValue)
            if progress < 1.0 {
                actions.append(AIActionType.set_progress.rawValue)
            }
        case .active:
            actions.append(AIActionType.deactivate_goal.rawValue)
            actions.append(AIActionType.set_progress.rawValue)
        case .completed:
            actions.append(AIActionType.mark_incomplete.rawValue)
            actions.append(AIActionType.reactivate.rawValue)
        case .archived:
            actions.append(AIActionType.reactivate.rawValue)
            actions.append(AIActionType.delete_goal.rawValue)
        }

        // Progress actions
        if progress < 1.0 && activationState != .completed {
            actions.append(AIActionType.complete_goal.rawValue)
        }

        // Priority actions
        actions.append(AIActionType.change_priority.rawValue)

        // Subgoal actions
        actions.append(AIActionType.create_subgoal.rawValue)
        if let subgoals = subgoals, !subgoals.isEmpty {
            actions.append(AIActionType.update_subgoal.rawValue)
            actions.append(AIActionType.complete_subgoal.rawValue)
            actions.append(AIActionType.delete_subgoal.rawValue)
        }

        return actions.sorted()
    }

    var sortedSubgoals: [Goal] {
        guard let subgoals else { return [] }
        return subgoals.sorted { lhs, rhs in
            let lhsOrder = lhs.effectiveSortOrder
            let rhsOrder = rhs.effectiveSortOrder
            if lhsOrder == rhsOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhsOrder < rhsOrder
        }
    }

    var effectiveSortOrder: Double {
        sortOrder ?? createdAt.timeIntervalSinceReferenceDate
    }

    var normalizedCategory: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unsorted" : trimmed
    }

    var kind: Kind {
        get { Kind(rawValue: kindStorage) ?? .campaign }
        set { kindStorage = newValue.rawValue }
    }

    // MARK: - Unified Timeline

    /// Timeline item that can be either a chat entry or a revision event
    enum TimelineItem: Identifiable {
        case chat(ChatEntry)
        case revision(GoalRevision)

        var id: String {
            switch self {
            case .chat(let entry): return "chat_\(entry.id.uuidString)"
            case .revision(let rev): return "revision_\(rev.id.uuidString)"
            }
        }

        var timestamp: Date {
            switch self {
            case .chat(let entry): return entry.timestamp
            case .revision(let rev): return rev.createdAt
            }
        }

        var isSystemEvent: Bool {
            switch self {
            case .chat(let entry): return entry.isSystemEvent
            case .revision: return true
            }
        }
    }

    /// Unified timeline showing all activity for this goal AND its subtasks
    /// Includes: chat messages, subtask chat messages, and all revision events
    func unifiedTimeline(from modelContext: ModelContext) -> [TimelineItem] {
        var items: [TimelineItem] = []

        // Fetch chat entries for this goal
        let goalScope = ChatEntry.Scope.goal(id)
        if let goalChats = fetchChatEntries(scope: goalScope, from: modelContext) {
            items.append(contentsOf: goalChats.map { .chat($0) })
        }

        // Fetch chat entries for all subtasks
        if let subgoals = subgoals {
            for subgoal in subgoals {
                let subgoalScope = ChatEntry.Scope.subgoal(subgoal.id)
                if let subgoalChats = fetchChatEntries(scope: subgoalScope, from: modelContext) {
                    items.append(contentsOf: subgoalChats.map { .chat($0) })
                }
            }
        }

        // Add this goal's revisions
        items.append(contentsOf: revisionHistory.map { .revision($0) })

        // Add subtask revisions
        if let subgoals = subgoals {
            for subgoal in subgoals {
                items.append(contentsOf: subgoal.revisionHistory.map { .revision($0) })
            }
        }

        // Sort by timestamp
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    private func fetchChatEntries(scope: ChatEntry.Scope, from modelContext: ModelContext) -> [ChatEntry]? {
        let descriptor = FetchDescriptor<ChatEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        guard let allEntries = try? modelContext.fetch(descriptor) else { return nil }

        // Filter by scope
        return allEntries.filter { $0.scope == scope }
    }

    /// Convenience property for views that need timeline items
    var timelineItems: [TimelineItem] {
        // This needs modelContext which views have access to
        // For now, return just revisions - views should use unifiedTimeline(from:) directly
        return revisionHistory.map { .revision($0) }
    }
}

@Model
class AIMirrorCard {
    var id = UUID()
    var title: String = ""
    var aiInterpretation: String = ""
    var suggestedActions: [String] = []
    var confidence: Double = 0.0
    var relatedGoalId: UUID?
    var createdAt: Date = Date()
    var emotionalTone: String?
    var insights: [String] = []

    @Relationship(deleteRule: .cascade) var snapshots: [AIMirrorSnapshot]
    
    init(title: String, interpretation: String = "", relatedGoalId: UUID? = nil) {
        self.title = title
        self.aiInterpretation = interpretation
        self.relatedGoalId = relatedGoalId
        self.snapshots = []
    }
}

@Model
final class AIMirrorSnapshot {
    var id = UUID()
    var capturedAt: Date = Date()
    var aiInterpretation: String
    var suggestedActions: [String]
    var confidence: Double
    var emotionalTone: String?
    var insights: [String] = []
    @Relationship(inverse: \AIMirrorCard.snapshots) var mirrorCard: AIMirrorCard?
    var relatedGoalId: UUID?

    init(
        aiInterpretation: String,
        suggestedActions: [String],
        confidence: Double,
        emotionalTone: String? = nil,
        insights: [String] = [],
        relatedGoalId: UUID? = nil
    ) {
        self.aiInterpretation = aiInterpretation
        self.suggestedActions = suggestedActions
        self.confidence = confidence
        self.emotionalTone = emotionalTone
        self.insights = insights
        self.relatedGoalId = relatedGoalId
    }
}

@Model
final class GoalSnapshot {
    var id = UUID()
    var capturedAt: Date = Date()
    var title: String
    var content: String
    var aiSummary: String?
    var category: String = "General"
    var priority: String = Goal.Priority.next.rawValue
    var progress: Double = 0.0
    var goalID: UUID?

    init(
        title: String,
        content: String,
        aiSummary: String? = nil,
        category: String = "General",
        priority: String = Goal.Priority.next.rawValue,
        progress: Double = 0.0
    ) {
        self.title = title
        self.content = content
        self.aiSummary = aiSummary
        self.category = category
        self.priority = priority
        self.progress = progress
    }
}

@Model
final class GoalTargetMetric {
    var id = UUID()
    var label: String
    var targetValue: Double?
    var unit: String?
    var baselineValue: Double?
    var measurementWindowDays: Int?
    var lowerBound: Double?
    var upperBound: Double?
    var notes: String?
    var lastUpdatedAt: Date = Date()
    var goalID: UUID?
    @Relationship(inverse: \Goal.targetMetric) var goal: Goal?

    init(
        label: String,
        targetValue: Double? = nil,
        unit: String? = nil,
        baselineValue: Double? = nil,
        measurementWindowDays: Int? = nil,
        lowerBound: Double? = nil,
        upperBound: Double? = nil,
        notes: String? = nil,
        goalID: UUID? = nil
    ) {
        self.label = label
        self.targetValue = targetValue
        self.unit = unit
        self.baselineValue = baselineValue
        self.measurementWindowDays = measurementWindowDays
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.notes = notes
        self.goalID = goalID
    }
}

@Model
final class GoalPhase {
    enum Status: String, Codable, CaseIterable {
        case planned
        case active
        case completed
        case skipped
    }

    var id = UUID()
    var title: String
    var summary: String
    var order: Int
    var status: Status = GoalPhase.Status.planned
    var startedAt: Date?
    var completedAt: Date?
    var goalID: UUID?
    @Relationship(inverse: \Goal.phases) var goal: Goal?

    init(
        title: String,
        summary: String,
        order: Int,
        status: Status = GoalPhase.Status.planned,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        goalID: UUID? = nil
    ) {
        self.title = title
        self.summary = summary
        self.order = order
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.goalID = goalID
    }
}

@Model
final class GoalProjection {
    enum Status: String, Codable, CaseIterable {
        case upcoming
        case inProgress
        case complete
        case skipped
        case stale
    }

    var id = UUID()
    var title: String
    var detail: String?
    var startDate: Date
    var endDate: Date
    var expectedMetricDelta: Double?
    var metricUnit: String?
    var confidence: Double = 0.75
    var status: Status = GoalProjection.Status.upcoming
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var goalID: UUID?
    @Relationship(inverse: \Goal.projections) var goal: Goal?

    init(
        title: String,
        detail: String? = nil,
        startDate: Date,
        endDate: Date,
        expectedMetricDelta: Double? = nil,
        metricUnit: String? = nil,
        confidence: Double = 0.75,
        status: Status = GoalProjection.Status.upcoming,
        goalID: UUID? = nil
    ) {
        self.title = title
        self.detail = detail
        self.startDate = startDate
        self.endDate = endDate
        self.expectedMetricDelta = expectedMetricDelta
        self.metricUnit = metricUnit
        self.confidence = confidence
        self.status = status
        self.goalID = goalID
    }
}

@Model
final class GoalRevision {
    var id = UUID()
    var createdAt: Date = Date()
    var summary: String
    var rationale: String?
    @Relationship(deleteRule: .nullify) var snapshot: GoalSnapshot?
    @Relationship(deleteRule: .nullify) var beforeSnapshot: GoalSnapshot?
    var goalID: UUID?

    var goalId: UUID? {
        get { goalID }
        set { goalID = newValue }
    }

    init(summary: String, rationale: String? = nil, snapshot: GoalSnapshot? = nil, beforeSnapshot: GoalSnapshot? = nil) {
        self.summary = summary
        self.rationale = rationale
        self.snapshot = snapshot
        self.beforeSnapshot = beforeSnapshot
    }

    /// Computed description showing what changed
    var changeDescription: String {
        guard let before = beforeSnapshot, let after = snapshot else {
            return summary
        }

        var changes: [String] = []

        if before.title != after.title {
            changes.append("Title: '\(before.title)' → '\(after.title)'")
        }

        if before.content != after.content {
            changes.append("Description updated")
        }

        if before.progress != after.progress {
            let beforePercent = Int(before.progress * 100)
            let afterPercent = Int(after.progress * 100)
            changes.append("Progress: \(beforePercent)% → \(afterPercent)%")
        }

        if before.category != after.category {
            changes.append("Category: \(before.category) → \(after.category)")
        }

        if before.priority != after.priority {
            changes.append("Priority: \(before.priority) → \(after.priority)")
        }

        return changes.isEmpty ? summary : changes.joined(separator: "\n")
    }
}

@Model
final class ScheduledEventLink {
    enum Status: String, Codable {
        case proposed
        case confirmed
        case cancelled
    }

    var id = UUID()
    var eventIdentifier: String
    var status: Status = ScheduledEventLink.Status.proposed
    var startDate: Date?
    var endDate: Date?
    var lastSyncedAt: Date = Date()
    var goalID: UUID?

    init(eventIdentifier: String, status: Status = ScheduledEventLink.Status.proposed, startDate: Date? = nil, endDate: Date? = nil) {
        self.eventIdentifier = eventIdentifier
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
    }
}
