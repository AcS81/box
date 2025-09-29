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