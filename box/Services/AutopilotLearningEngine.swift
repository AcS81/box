//
//  AutopilotLearningEngine.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import Combine

/// Broad-thinking learning system that observes all app behavior and adapts autopilot intelligence
@MainActor
class AutopilotLearningEngine: ObservableObject {
    static let shared = AutopilotLearningEngine()

    @Published var learningProfile = LearningProfile()

    private let storageKey = "autopilot_learning_profile"

    private init() {
        loadProfile()
    }

    // MARK: - Learning Dimensions

    struct LearningProfile: Codable {
        // Aggressiveness (0.0 = conservative, 1.0 = very proactive)
        var aggressiveness: Double = 0.5

        // Preferred subtask count (learned from user's manual breakdowns)
        var preferredSubtaskCount: Int = 4

        // Category success rates
        var categoryCompletionRates: [String: Double] = [:]

        // Time-of-day preferences (hour -> productivity score)
        var timeOfDayPreferences: [Int: Double] = [:]

        // User override patterns
        var autopilotAcceptanceRate: Double = 1.0 // Starts optimistic
        var totalAutopilotActions: Int = 0
        var userOverrides: Int = 0

        // Goal complexity preferences
        var preferredBreakdownThreshold: Int = 3 // Words in title before suggesting breakdown

        // Calendar preferences
        var preferredSessionDuration: Int = 90 // minutes

        // Last learning update
        var lastUpdated: Date = Date()
    }

    // MARK: - Observation Methods

    func observeAutopilotAction(accepted: Bool) {
        learningProfile.totalAutopilotActions += 1

        if !accepted {
            learningProfile.userOverrides += 1
        }

        // Recalculate acceptance rate
        learningProfile.autopilotAcceptanceRate = Double(learningProfile.totalAutopilotActions - learningProfile.userOverrides) / Double(learningProfile.totalAutopilotActions)

        // Adjust aggressiveness based on acceptance
        if learningProfile.autopilotAcceptanceRate > 0.8 {
            // User rarely overrides → increase aggressiveness
            learningProfile.aggressiveness = min(1.0, learningProfile.aggressiveness + 0.05)
        } else if learningProfile.autopilotAcceptanceRate < 0.5 {
            // User frequently overrides → decrease aggressiveness
            learningProfile.aggressiveness = max(0.2, learningProfile.aggressiveness - 0.1)
        }

        saveProfile()
        print("🧠 Learning: Acceptance rate: \(Int(learningProfile.autopilotAcceptanceRate * 100))%, Aggressiveness: \(Int(learningProfile.aggressiveness * 100))%")
    }

    func observeGoalCompletion(goal: Goal, timeTaken: TimeInterval) {
        // Learn category success patterns
        let category = goal.category
        let currentRate = learningProfile.categoryCompletionRates[category] ?? 0.5
        let newRate = (currentRate * 0.8) + 0.2 // Weighted average, favoring recent success
        learningProfile.categoryCompletionRates[category] = newRate

        // Learn time-of-day patterns
        let hour = Calendar.current.component(.hour, from: Date())
        let currentScore = learningProfile.timeOfDayPreferences[hour] ?? 0.5
        learningProfile.timeOfDayPreferences[hour] = (currentScore * 0.7) + 0.3

        saveProfile()
        print("🧠 Learning: Category '\(category)' success rate: \(Int(newRate * 100))%")
    }

    func observeManualBreakdown(goal: Goal, subtaskCount: Int) {
        // Learn preferred subtask granularity
        learningProfile.preferredSubtaskCount = Int((Double(learningProfile.preferredSubtaskCount) * 0.7) + (Double(subtaskCount) * 0.3))

        saveProfile()
        print("🧠 Learning: Preferred subtask count updated to \(learningProfile.preferredSubtaskCount)")
    }

    func observeSchedulingPreference(sessionDuration: Int) {
        // Learn preferred work session length
        learningProfile.preferredSessionDuration = Int((Double(learningProfile.preferredSessionDuration) * 0.7) + (Double(sessionDuration) * 0.3))

        saveProfile()
        print("🧠 Learning: Preferred session duration: \(learningProfile.preferredSessionDuration) minutes")
    }

    func observeAutopilotToggle(enabled: Bool, forGoalCategory category: String) {
        // If user disables autopilot on specific category, adjust aggressiveness for that category
        if !enabled {
            let currentRate = learningProfile.categoryCompletionRates[category] ?? 0.5
            learningProfile.categoryCompletionRates[category] = currentRate * 0.8 // Reduce confidence
            print("🧠 Learning: User disabled autopilot for '\(category)' - reducing confidence")
        }

        saveProfile()
    }

    // MARK: - Decision Support

    func shouldTakeAutopilotAction(confidence: Double) -> Bool {
        // Adjust confidence threshold based on learned aggressiveness
        let threshold = 0.7 - (learningProfile.aggressiveness * 0.2) // Range: 0.5-0.7

        let shouldAct = confidence >= threshold
        print("🧠 Decision: Confidence \(Int(confidence * 100))% vs threshold \(Int(threshold * 100))% → \(shouldAct ? "EXECUTE" : "SKIP")")

        return shouldAct
    }

    func recommendedSubtaskCount(for goal: Goal) -> Int {
        // Use learned preference, adjusted by goal complexity
        let titleWords = goal.title.split(separator: " ").count

        if titleWords > learningProfile.preferredBreakdownThreshold * 2 {
            return learningProfile.preferredSubtaskCount + 2 // More complex = more subtasks
        } else if titleWords < learningProfile.preferredBreakdownThreshold {
            return max(3, learningProfile.preferredSubtaskCount - 1)
        }

        return learningProfile.preferredSubtaskCount
    }

    func recommendedSessionDuration(for goal: Goal) -> Int {
        // Use learned preference, adjusted by priority
        switch goal.priority {
        case .now:
            return max(60, learningProfile.preferredSessionDuration - 15) // Shorter for urgent
        case .next:
            return learningProfile.preferredSessionDuration
        case .later:
            return learningProfile.preferredSessionDuration + 30 // Longer for deep work
        }
    }

    func categorySuccessScore(for category: String) -> Double {
        return learningProfile.categoryCompletionRates[category] ?? 0.5
    }

    func optimalTimeOfDay() -> Int {
        // Find hour with highest productivity score
        guard !learningProfile.timeOfDayPreferences.isEmpty else {
            return 9 // Default to 9 AM
        }

        let sorted = learningProfile.timeOfDayPreferences.sorted { $0.value > $1.value }
        return sorted.first?.key ?? 9
    }

    // MARK: - Persistence

    private func saveProfile() {
        learningProfile.lastUpdated = Date()

        if let encoded = try? JSONEncoder().encode(learningProfile) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(LearningProfile.self, from: data) else {
            return
        }

        learningProfile = decoded
        print("🧠 Loaded learning profile: \(Int(learningProfile.aggressiveness * 100))% aggressive, \(learningProfile.totalAutopilotActions) actions observed")
    }

    func reset() {
        learningProfile = LearningProfile()
        saveProfile()
        print("🧠 Learning profile reset")
    }

    // MARK: - Insights

    func generateInsights() -> [String] {
        var insights: [String] = []

        // Aggressiveness insight
        if learningProfile.aggressiveness > 0.7 {
            insights.append("Autopilot is highly proactive based on your acceptance rate")
        } else if learningProfile.aggressiveness < 0.4 {
            insights.append("Autopilot is conservative - increase acceptance to make it more proactive")
        }

        // Category insights
        let topCategories = learningProfile.categoryCompletionRates.sorted { $0.value > $1.value }.prefix(3)
        if !topCategories.isEmpty {
            let categoryNames = topCategories.map { $0.key }.joined(separator: ", ")
            insights.append("Your most successful categories: \(categoryNames)")
        }

        // Time insights
        let optimalHour = optimalTimeOfDay()
        insights.append("Your most productive hour: \(optimalHour):00")

        // Action count
        insights.append("Autopilot has taken \(learningProfile.totalAutopilotActions) actions, with \(Int(learningProfile.autopilotAcceptanceRate * 100))% acceptance")

        return insights
    }
}