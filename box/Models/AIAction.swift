//
//  AIAction.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation

// MARK: - Action Types

enum AIActionType: String, Codable, CaseIterable {
    // Creation
    case create_goal

    // Lifecycle Operations
    case activate_goal
    case deactivate_goal
    case delete_goal
    case complete_goal
    case regenerate_goal
    case lock_goal
    case unlock_goal

    // Goal Modification
    case edit_title
    case edit_content
    case edit_category
    case set_progress
    case change_priority
    case mark_incomplete
    case reactivate

    // Subgoal Operations
    case breakdown
    case create_subgoal
    case update_subgoal
    case complete_subgoal
    case delete_subgoal

    // Bulk Operations
    case merge_goals
    case reorder_goals
    case bulk_delete
    case bulk_archive
    case bulk_complete

    // Query/View Operations (read-only)
    case view_subgoals
    case view_history
    case summarize
    case chat
}

// MARK: - AI Action

struct AIAction: Codable, Identifiable {
    var id = UUID()
    let type: AIActionType
    let goalId: String?
    let parameters: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, goalId, parameters
    }

    init(type: AIActionType, goalId: String? = nil, parameters: [String: AnyCodable]? = nil) {
        self.type = type
        self.goalId = goalId
        self.parameters = parameters
    }
}

// MARK: - Chat Response

struct ChatResponse: Codable {
    let reply: String
    let actions: [AIAction]
    let requiresConfirmation: Bool

    enum CodingKeys: String, CodingKey {
        case reply, actions, requiresConfirmation
    }

    init(reply: String, actions: [AIAction] = [], requiresConfirmation: Bool = false) {
        self.reply = reply
        self.actions = actions
        self.requiresConfirmation = requiresConfirmation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)

        // Make actions optional with default empty array
        actions = (try? container.decode([AIAction].self, forKey: .actions)) ?? []

        // Make requiresConfirmation optional with default false
        requiresConfirmation = (try? container.decode(Bool.self, forKey: .requiresConfirmation)) ?? false
    }
}

// MARK: - Flexible JSON Parameter Support

enum AnyCodable: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodable"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    // Convenience accessors
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var arrayValue: [AnyCodable]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var dictionaryValue: [String: AnyCodable]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }
}

// MARK: - Action Result

struct ActionResult {
    let success: Bool
    let message: String
    let data: [String: Any]?

    init(success: Bool, message: String, data: [String: Any]? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }
}

// MARK: - Action Errors

enum ActionError: LocalizedError {
    case goalNotFound
    case subgoalNotFound
    case actionNotAvailable(String)
    case invalidParameters
    case insufficientGoals
    case notImplemented(String)
    case executionFailed(String)
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .goalNotFound:
            return "Goal not found"
        case .subgoalNotFound:
            return "Subtask not found"
        case .actionNotAvailable(let action):
            return "\(action) is not available for this goal"
        case .invalidParameters:
            return "Invalid action parameters"
        case .insufficientGoals:
            return "Need at least 2 goals for this operation"
        case .notImplemented(let action):
            return "\(action) not yet implemented"
        case .executionFailed(let reason):
            return "Action failed: \(reason)"
        case .confirmationRequired:
            return "This action requires confirmation"
        }
    }
}