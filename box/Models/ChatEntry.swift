//
//  ChatEntry.swift
//  box
//
//  Unified conversation model for all chat contexts
//

import Foundation
import SwiftData

@Model
final class ChatEntry {
    enum Scope: Codable, Equatable, Hashable {
        case general
        case goal(UUID)
        case subgoal(UUID)

        var goalId: UUID? {
            switch self {
            case .goal(let id), .subgoal(let id): return id
            case .general: return nil
            }
        }

        var scopeLabel: String {
            switch self {
            case .general: return "General"
            case .goal: return "Goal"
            case .subgoal: return "Subtask"
            }
        }

        var isGoalScoped: Bool {
            switch self {
            case .goal, .subgoal: return true
            case .general: return false
            }
        }
    }

    var id = UUID()
    var content: String
    var isUser: Bool
    var timestamp: Date
    var scopeData: Data  // Encoded Scope

    // Optional: for system events (e.g., "Goal locked", "Progress updated")
    var isSystemEvent: Bool = false
    var changeSummary: String?

    // Link to richer revision if this is a system event
    var relatedRevisionId: UUID?

    // Memory system enhancements
    var importance: Double = 0.5  // 0.0 to 1.0, default medium importance
    var isSummarized: Bool = false  // Has this been included in a summary?
    var referencedGoalIds: [String] = []  // Goal IDs mentioned in this message
    var extractedInsights: [String] = []  // Key insights extracted from this message

    init(content: String, isUser: Bool, scope: Scope, timestamp: Date = .now) {
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.scopeData = (try? JSONEncoder().encode(scope)) ?? Data()

        // Auto-calculate importance
        self.importance = Self.calculateImportance(content: content, isUser: isUser)
    }

    init(systemEvent summary: String, scope: Scope, revisionId: UUID? = nil, timestamp: Date = .now) {
        self.content = summary
        self.isUser = false
        self.isSystemEvent = true
        self.changeSummary = summary
        self.relatedRevisionId = revisionId
        self.timestamp = timestamp
        self.scopeData = (try? JSONEncoder().encode(scope)) ?? Data()
        self.importance = 0.8  // System events are important
    }

    var scope: Scope {
        get {
            (try? JSONDecoder().decode(Scope.self, from: scopeData)) ?? .general
        }
        set {
            scopeData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Importance Calculation

    static func calculateImportance(content: String, isUser: Bool) -> Double {
        let lower = content.lowercased()
        var score: Double = 0.5

        // High importance indicators
        if lower.contains("important") || lower.contains("critical") || lower.contains("urgent") {
            score += 0.2
        }

        // Decision indicators
        if lower.contains("decide") || lower.contains("choose") || lower.contains("will") || lower.contains("going to") {
            score += 0.15
        }

        // Preference/constraint indicators
        if lower.contains("prefer") || lower.contains("need") || lower.contains("must") || lower.contains("budget") {
            score += 0.15
        }

        // Action indicators
        if lower.contains("delete") || lower.contains("complete") || lower.contains("activate") || lower.contains("create") {
            score += 0.1
        }

        // Question indicators (user questions are important)
        if isUser && (lower.contains("?") || lower.hasPrefix("how") || lower.hasPrefix("what") || lower.hasPrefix("why")) {
            score += 0.1
        }

        // Length indicates detail
        if content.count > 200 {
            score += 0.05
        }

        return min(1.0, max(0.0, score))
    }

    // MARK: - Helper Methods

    func relatesTo(scope: Scope) -> Bool {
        // Check if this message is relevant to given scope
        switch (self.scope, scope) {
        case (.general, _):
            // General messages relate to everything
            return true

        case (.goal(let id1), .goal(let id2)):
            return id1 == id2

        case (.subgoal(let id1), .subgoal(let id2)):
            return id1 == id2

        case (.goal, .subgoal(let subgoalId)):
            // Check if goal is parent of subgoal
            return referencedGoalIds.contains(subgoalId.uuidString)

        case (.subgoal, .goal(let goalId)):
            // Check if subgoal belongs to goal
            return referencedGoalIds.contains(goalId.uuidString)

        default:
            return false
        }
    }

    var isHighImportance: Bool {
        importance >= 0.7
    }

    var isVoiceInput: Bool {
        content.hasPrefix("🎤")
    }
}
