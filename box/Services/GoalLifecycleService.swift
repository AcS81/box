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
        case calendarAccessDenied
        case activationFailed(String)

        var errorDescription: String? {
            switch self {
            case .goalLocked:
                return "Goal is locked and cannot be modified."
            case .calendarAccessDenied:
                return "Calendar access is required to activate this goal."
            case .activationFailed(let reason):
                return reason
            }
        }
    }

    @Published private(set) var processingGoals: Set<UUID> = []
    @Published private(set) var lastError: String?

    private let aiService: AIService
    private let calendarService: CalendarService
    private let userContextService: UserContextService
    private let minimumUpcomingSessions = 3
    private let scheduleMaintenanceInterval: TimeInterval = 3600 // 1 hour
    private var scheduleMaintenanceTask: Task<Void, Never>?

    init(
        aiService: AIService,
        calendarService: CalendarService,
        userContextService: UserContextService
    ) {
        self.aiService = aiService
        self.calendarService = calendarService
        self.userContextService = userContextService
    }

    deinit {
        scheduleMaintenanceTask?.cancel()
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

    func generateActivationPlan(for goal: Goal, within goals: [Goal]) async throws -> CalendarService.ActivationPlan {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        guard !goal.isLocked else {
            throw LifecycleError.goalLocked
        }

        let plan = try await buildActivationPlan(for: goal, within: goals)
        guard !plan.events.isEmpty else {
            throw LifecycleError.activationFailed("No suitable schedule was generated for this goal.")
        }

        return plan
    }

    func confirmActivation(
        goal: Goal,
        plan: CalendarService.ActivationPlan,
        within goals: [Goal],
        modelContext: ModelContext
    ) async throws {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        try await finalizeActivation(goal: goal, plan: plan, within: goals, modelContext: modelContext)
    }

    func activate(goal: Goal, within goals: [Goal], modelContext: ModelContext) async throws {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        let plan = try await buildActivationPlan(for: goal, within: goals)
        guard !plan.events.isEmpty else {
            throw LifecycleError.activationFailed("No suitable schedule was generated for this goal.")
        }

        try await finalizeActivation(goal: goal, plan: plan, within: goals, modelContext: modelContext)
    }

    func deactivate(goal: Goal, reason: String? = nil, modelContext: ModelContext) async {
        lastError = nil
        setProcessing(goal.id, isProcessing: true)
        defer { setProcessing(goal.id, isProcessing: false) }

        for link in goal.scheduledEvents {
            try? await calendarService.deleteEvent(with: link.eventIdentifier)
            modelContext.delete(link)
        }

        goal.scheduledEvents.removeAll()
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

    private func buildActivationPlan(for goal: Goal, within goals: [Goal]) async throws -> CalendarService.ActivationPlan {
        guard await calendarService.requestAccess() else {
            throw LifecycleError.calendarAccessDenied
        }

        return try await calendarService.generateSmartSchedule(for: goal, goals: goals)
    }

    private func finalizeActivation(
        goal: Goal,
        plan: CalendarService.ActivationPlan,
        within goals: [Goal],
        modelContext: ModelContext
    ) async throws {
        guard calendarService.isAuthorized else {
            throw LifecycleError.calendarAccessDenied
        }

        guard !plan.events.isEmpty else {
            throw LifecycleError.activationFailed("No sessions selected for activation.")
        }

        var links: [ScheduledEventLink] = []

        for event in plan.events {
            let composedNotes: String
            if let detail = event.notes, !detail.isEmpty {
                composedNotes = "\(detail)\n\nScheduled via YOU AND GOALS"
            } else {
                composedNotes = "YOU AND GOALS — \(goal.title)"
            }

            let identifier = try await calendarService.createEvent(
                title: event.title,
                startDate: event.startDate,
                duration: event.duration,
                notes: composedNotes
            )

            let link = ScheduledEventLink(
                eventIdentifier: identifier,
                status: .confirmed,
                startDate: event.startDate,
                endDate: event.startDate.addingTimeInterval(event.duration)
            )
            link.goalID = goal.id
            modelContext.insert(link)
            links.append(link)
        }

        goal.activate(at: .now, rationale: "Scheduled \(links.count) focus sessions")
        links.forEach { goal.linkScheduledEvent($0) }
        goal.updatedAt = .now

        await refreshMirrorCard(for: goal, within: goals, modelContext: modelContext, tips: plan.tips)
    }

    // MARK: - Schedule Maintenance

    func startScheduleMaintenance(goalsProvider: @escaping () -> [Goal], modelContext: ModelContext) {
        stopScheduleMaintenance()

        scheduleMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let snapshot = goalsProvider()
                await self.syncActiveSchedules(goals: snapshot, modelContext: modelContext)

                do {
                    try await Task.sleep(nanoseconds: UInt64(self.scheduleMaintenanceInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    func stopScheduleMaintenance() {
        scheduleMaintenanceTask?.cancel()
        scheduleMaintenanceTask = nil
    }

    func syncActiveSchedules(goals: [Goal], modelContext: ModelContext) async {
        guard await calendarService.requestAccess() else {
            lastError = LifecycleError.calendarAccessDenied.errorDescription
            return
        }

        let now = Date()
        let activeGoals = goals.filter { $0.activationState == .active && $0.progress < 1.0 }

        for goal in activeGoals {
            var upcomingLinks: [ScheduledEventLink] = []
            var expiredLinks: [ScheduledEventLink] = []

            for link in goal.scheduledEvents {
                if linkHasConcluded(link, relativeTo: now) {
                    expiredLinks.append(link)
                } else {
                    upcomingLinks.append(link)
                }
            }

            if !expiredLinks.isEmpty {
                for link in expiredLinks {
                    try? await calendarService.deleteEvent(with: link.eventIdentifier)
                    goal.unlinkScheduledEvent(withIdentifier: link.eventIdentifier)
                    modelContext.delete(link)
                }
                goal.updatedAt = .now
            }

            let needed = max(0, minimumUpcomingSessions - upcomingLinks.count)
            if needed > 0 {
                await scheduleAdditionalSessions(
                    for: goal,
                    neededCount: needed,
                    within: goals,
                    modelContext: modelContext,
                    referenceDate: now
                )
            }
        }
    }

    private func linkHasConcluded(_ link: ScheduledEventLink, relativeTo now: Date) -> Bool {
        if let endDate = link.endDate {
            return endDate <= now
        }

        if let startDate = link.startDate {
            return startDate <= now
        }

        return true
    }

    private func scheduleAdditionalSessions(
        for goal: Goal,
        neededCount: Int,
        within goals: [Goal],
        modelContext: ModelContext,
        referenceDate now: Date
    ) async {
        do {
            let plan = try await calendarService.generateSmartSchedule(for: goal, goals: goals)
            guard !plan.events.isEmpty else { return }

            var existingStartKeys = Set(
                goal.scheduledEvents.compactMap { link -> Int? in
                    guard let date = link.startDate else { return nil }
                    return Int(date.timeIntervalSinceReferenceDate / 60.0)
                }
            )

            var created = 0

            for event in plan.events.sorted(by: { $0.startDate < $1.startDate }) {
                guard event.startDate > now else { continue }

                let startKey = Int(event.startDate.timeIntervalSinceReferenceDate / 60.0)
                if existingStartKeys.contains(startKey) {
                    continue
                }

                let identifier = try await calendarService.createEvent(
                    title: event.title,
                    startDate: event.startDate,
                    duration: event.duration,
                    notes: event.notes
                )

                let link = ScheduledEventLink(
                    eventIdentifier: identifier,
                    status: .confirmed,
                    startDate: event.startDate,
                    endDate: event.startDate.addingTimeInterval(event.duration)
                )
                link.goalID = goal.id
                modelContext.insert(link)
                goal.linkScheduledEvent(link)

                existingStartKeys.insert(startKey)
                created += 1

                if created >= neededCount {
                    break
                }
            }

            if created > 0 {
                goal.updatedAt = .now
            }
        } catch {
            lastError = error.localizedDescription
            print("❌ Failed to top up schedule for '\(goal.title)': \(error.localizedDescription)")
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

        // Remove any scheduled events
        for link in goal.scheduledEvents {
            try? await calendarService.deleteEvent(with: link.eventIdentifier)
            modelContext.delete(link)
        }

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

        // Remove scheduled events (goal is done)
        for link in goal.scheduledEvents {
            try? await calendarService.deleteEvent(with: link.eventIdentifier)
            modelContext.delete(link)
        }
        goal.scheduledEvents.removeAll()

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

