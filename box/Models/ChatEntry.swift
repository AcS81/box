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

    init(content: String, isUser: Bool, scope: Scope, timestamp: Date = .now) {
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.scopeData = (try? JSONEncoder().encode(scope)) ?? Data()
    }

    init(systemEvent summary: String, scope: Scope, revisionId: UUID? = nil, timestamp: Date = .now) {
        self.content = summary
        self.isUser = false
        self.isSystemEvent = true
        self.changeSummary = summary
        self.relatedRevisionId = revisionId
        self.timestamp = timestamp
        self.scopeData = (try? JSONEncoder().encode(scope)) ?? Data()
    }

    var scope: Scope {
        get {
            (try? JSONDecoder().decode(Scope.self, from: scopeData)) ?? .general
        }
        set {
            scopeData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
