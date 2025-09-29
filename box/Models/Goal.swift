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

    var id = UUID()
    var title: String = ""
    var content: String = ""
    var category: String = "General"
    var priority: Priority = Priority.next
    var isActive: Bool = false
    var activationState: ActivationState = ActivationState.draft
    var isLocked: Bool = false
    var progress: Double = 0.0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var targetDate: Date?
    var lastRegeneratedAt: Date?
    var activatedAt: Date?
    
    @Relationship(deleteRule: .cascade) var subgoals: [Goal]?
    @Relationship(inverse: \Goal.subgoals) var parent: Goal?
    @Relationship(deleteRule: .cascade) var chatHistory: [ChatMessage]?
    @Relationship(deleteRule: .cascade) var lockedSnapshot: GoalSnapshot?
    @Relationship(deleteRule: .cascade) var revisionHistory: [GoalRevision]
    @Relationship(deleteRule: .cascade) var scheduledEvents: [ScheduledEventLink]
    
    enum Priority: String, Codable, CaseIterable {
        case now = "Now"
        case next = "Next"
        case later = "Later"
    }
    
    init(title: String, content: String = "", category: String = "General", priority: Priority = Priority.next, targetDate: Date? = nil) {
        self.title = title
        self.content = content
        self.category = category
        self.priority = priority
        self.targetDate = targetDate
        self.revisionHistory = []
        self.scheduledEvents = []
    }

    var isDraft: Bool {
        activationState == .draft
    }

    var isActivated: Bool {
        activationState == .active
    }

    func lock(with snapshot: GoalSnapshot) {
        guard !isLocked else { return }
        snapshot.goalID = id
        lockedSnapshot = snapshot
        isLocked = true
        appendRevision(summary: "Card locked", rationale: snapshot.aiSummary)
    }

    func unlock(reason: String? = nil) {
        guard isLocked else { return }
        lockedSnapshot = nil
        isLocked = false
        appendRevision(summary: "Card unlocked", rationale: reason)
    }

    func activate(at date: Date = .now, rationale: String? = nil) {
        guard activationState != .active else { return }
        activationState = .active
        activatedAt = date
        isActive = true
        appendRevision(summary: "Card activated", rationale: rationale)
    }

    func deactivate(to state: ActivationState = .draft, rationale: String? = nil) {
        guard activationState != state else { return }
        activationState = state
        if state != .active {
            isActive = false
        }
        appendRevision(summary: "Card moved to \(state.rawValue)", rationale: rationale)
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

    private func appendRevision(summary: String, rationale: String?) {
        let revision = GoalRevision(
            summary: summary,
            rationale: rationale,
            snapshot: lockedSnapshot
        )
        revision.goalID = id
        revisionHistory.append(revision)
    }
}

@Model
class ChatMessage {
    var id = UUID()
    var content: String = ""
    var isUser: Bool = true
    var timestamp: Date = Date()
    var goalId: UUID?
    
    init(content: String, isUser: Bool = true, goalId: UUID? = nil) {
        self.content = content
        self.isUser = isUser
        self.goalId = goalId
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
    
    init(title: String, interpretation: String = "", relatedGoalId: UUID? = nil) {
        self.title = title
        self.aiInterpretation = interpretation
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
    var goalID: UUID?

    init(title: String, content: String, aiSummary: String? = nil) {
        self.title = title
        self.content = content
        self.aiSummary = aiSummary
    }
}

@Model
final class GoalRevision {
    var id = UUID()
    var createdAt: Date = Date()
    var summary: String
    var rationale: String?
    @Relationship(deleteRule: .nullify) var snapshot: GoalSnapshot?
    var goalID: UUID?

    init(summary: String, rationale: String? = nil, snapshot: GoalSnapshot? = nil) {
        self.summary = summary
        self.rationale = rationale
        self.snapshot = snapshot
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
    var status: Status = Status.proposed
    var startDate: Date?
    var endDate: Date?
    var lastSyncedAt: Date = Date()
    var goalID: UUID?

    init(eventIdentifier: String, status: Status = .proposed, startDate: Date? = nil, endDate: Date? = nil) {
        self.eventIdentifier = eventIdentifier
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
    }
}
