//
//  AIServiceExtensions.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import SwiftData

extension AIService {

    func createGoal(from input: String, context: AIContext) async throws -> GoalCreationResponse {
        let function = AIFunction.createGoal(input: input, context: context)
        return try await processRequest(function, responseType: GoalCreationResponse.self)
    }

    func breakdownGoal(_ goal: Goal, context: AIContext) async throws -> GoalBreakdownResponse {
        let function = AIFunction.breakdownGoal(goal: goal, context: context)
        return try await processRequest(function, responseType: GoalBreakdownResponse.self)
    }

    func chatWithGoal(message: String, goal: Goal, context: AIContext) async throws -> String {
        let function = AIFunction.chatWithGoal(message: message, goal: goal, context: context)
        return try await processRequest(function)
    }

    func generateCalendarEvents(for goal: Goal, context: AIContext) async throws -> CalendarEventsResponse {
        let function = AIFunction.generateCalendarEvents(goal: goal, context: context)
        return try await processRequest(function, responseType: CalendarEventsResponse.self)
    }

    func summarizeProgress(for goal: Goal, context: AIContext) async throws -> String {
        let function = AIFunction.summarizeProgress(goal: goal, context: context)
        return try await processRequest(function)
    }

    func reorderCards(_ goals: [Goal], instruction: String, context: AIContext) async throws -> GoalReorderResponse {
        let function = AIFunction.reorderCards(goals: goals, instruction: instruction, context: context)
        return try await processRequest(function, responseType: GoalReorderResponse.self)
    }

    func generateMirrorCard(for goal: Goal, context: AIContext) async throws -> MirrorCardResponse {
        let function = AIFunction.generateMirrorCard(goal: goal, context: context)
        return try await processRequest(function, responseType: MirrorCardResponse.self)
    }

    // MARK: - Intent Routing

    func processUnifiedMessage(_ message: String, goal: Goal? = nil, context: AIContext) async throws -> UnifiedChatResponse {
        // Parse the message for intents
        let intent = parseIntent(from: message, goal: goal)

        switch intent {
        case .deleteGoal(let targetGoal):
            return UnifiedChatResponse(
                message: "I'll delete the goal '\(targetGoal.title)' for you.",
                intent: .delete(targetGoal),
                requiresConfirmation: true
            )

        case .completeGoal(let targetGoal):
            return UnifiedChatResponse(
                message: "Great! I'll mark '\(targetGoal.title)' as completed.",
                intent: .complete(targetGoal),
                requiresConfirmation: false
            )

        case .editGoal(let targetGoal, let changes):
            return UnifiedChatResponse(
                message: "I'll update '\(targetGoal.title)' with your changes.",
                intent: .edit(targetGoal, changes),
                requiresConfirmation: false
            )

        case .chat:
            // Regular chat - route to appropriate chat function
            if let goal = goal {
                let response = try await chatWithGoal(message: message, goal: goal, context: context)
                return UnifiedChatResponse(message: response, intent: nil, requiresConfirmation: false)
            } else {
                // General management chat
                let response = try await processGeneralManagement(message: message, context: context)
                return UnifiedChatResponse(message: response, intent: nil, requiresConfirmation: false)
            }
        }
    }

    private func parseIntent(from message: String, goal: Goal?) -> ChatIntent {
        let lowercased = message.lowercased()

        // Delete intents
        if lowercased.contains("delete") || lowercased.contains("remove") || lowercased.contains("trash") {
            if lowercased.contains("this") || lowercased.contains("goal"), let goal = goal {
                return .deleteGoal(goal)
            }
        }

        // Complete intents
        if lowercased.contains("complete") || lowercased.contains("done") || lowercased.contains("finish") {
            if lowercased.contains("this") || lowercased.contains("goal"), let goal = goal {
                return .completeGoal(goal)
            }
        }

        // Edit intents
        if lowercased.contains("edit") || lowercased.contains("change") || lowercased.contains("update") || lowercased.contains("modify") {
            if let goal = goal {
                let changes = extractEditChanges(from: message)
                return .editGoal(goal, changes)
            }
        }

        return .chat
    }

    private func extractEditChanges(from message: String) -> GoalEditChanges {
        // Simple extraction logic - could be made more sophisticated
        var changes = GoalEditChanges()

        let lowercased = message.lowercased()

        // Extract title changes
        if let titleMatch = message.range(of: "title to \"([^\"]+)\"", options: .regularExpression) {
            changes.title = String(message[titleMatch]).replacingOccurrences(of: "title to \"", with: "").replacingOccurrences(of: "\"", with: "")
        }

        // Extract priority changes
        if lowercased.contains("priority") {
            if lowercased.contains("now") {
                changes.priority = .now
            } else if lowercased.contains("next") {
                changes.priority = .next
            } else if lowercased.contains("later") {
                changes.priority = .later
            }
        }

        return changes
    }

    private func processGeneralManagement(message: String, context: AIContext) async throws -> String {
        // For now, use the existing reorder logic or general chat
        // This could be expanded to handle various management tasks
        if message.lowercased().contains("reorder") || message.lowercased().contains("sort") {
            let response = try await reorderCards(context.recentGoals, instruction: message, context: context)
            return response.reasoning
        } else {
            // Generic management response - this could be expanded
            return "I understand you want to manage your goals. Could you be more specific about what you'd like me to help you with?"
        }
    }
}

enum ChatIntent {
    case deleteGoal(Goal)
    case completeGoal(Goal)
    case editGoal(Goal, GoalEditChanges)
    case chat
}

struct UnifiedChatResponse {
    let message: String
    let intent: LifecycleIntent?
    let requiresConfirmation: Bool
}

enum LifecycleIntent {
    case delete(Goal)
    case complete(Goal)
    case edit(Goal, GoalEditChanges)
}

struct GoalEditChanges {
    var title: String?
    var content: String?
    var category: String?
    var priority: Goal.Priority?
}

extension Goal {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "title": title,
            "content": content,
            "category": category,
            "priority": priority.rawValue,
            "isActive": isActive,
            "progress": progress,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
    }

    var timeToCompletion: String {
        guard progress < 1.0 else { return "Completed" }

        let timeElapsed = Date().timeIntervalSince(createdAt)
        let progressRate = progress / timeElapsed

        guard progressRate > 0 else { return "No progress yet" }

        let remainingWork = 1.0 - progress
        let estimatedTimeRemaining = remainingWork / progressRate

        let days = Int(estimatedTimeRemaining / 86400)
        let hours = Int((estimatedTimeRemaining.truncatingRemainder(dividingBy: 86400)) / 3600)

        if days > 0 {
            return "\(days) days, \(hours) hours"
        } else if hours > 0 {
            return "\(hours) hours"
        } else {
            return "Less than an hour"
        }
    }

    var priorityColor: String {
        switch priority {
        case .now: return "red"
        case .next: return "orange"
        case .later: return "blue"
        }
    }

    var isOverdue: Bool {
        guard let targetDate = targetDate else { return false }
        return Date() > targetDate && progress < 1.0
    }
}

extension AIContext {
    static func create(from goals: [Goal]) -> AIContext {
        return UserContextService.shared.buildContext(from: goals)
    }

    var contextSummary: String {
        var summary = "Context: \(recentGoals.count) recent goals"

        if completedGoalsCount > 0 {
            summary += ", \(completedGoalsCount) completed"
        }

        if let avgTime = averageCompletionTime {
            let days = Int(avgTime / 86400)
            summary += ", avg completion: \(days) days"
        }

        if let hours = preferredWorkingHours {
            summary += ", work hours: \(hours.start):00-\(hours.end):00"
        }

        return summary
    }
}