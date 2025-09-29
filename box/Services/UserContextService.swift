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

    private init() {
        loadUserPreferences()
    }

    func buildContext(from goals: [Goal]) -> AIContext {
        let recentGoals = goals.sorted { $0.updatedAt > $1.updatedAt }
        let patterns = extractUserPatterns(from: goals)

        return AIContext(
            goals: recentGoals,
            patterns: patterns,
            preferredHours: workingHours
        )
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