//
//  ProactiveAIService.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import SwiftData
import Combine

/// Background service for proactive AI intelligence
@MainActor
class ProactiveAIService: ObservableObject {
    static let shared = ProactiveAIService()

    @Published var stagnantGoals: [Goal] = []
    @Published var insights: [ProactiveInsight] = []
    @Published var lastAnalysisDate: Date?

    private let aiService: AIService
    private let userContextService: UserContextService
    private let stagnationThresholdDays = 7

    private init() {
        self.aiService = AIService.shared
        self.userContextService = UserContextService.shared
    }

    // MARK: - Stagnation Detection

    func detectStagnantGoals(from goals: [Goal]) -> [Goal] {
        let now = Date()
        let threshold = TimeInterval(stagnationThresholdDays * 24 * 60 * 60)

        return goals.filter { goal in
            // Only check active goals that aren't complete
            guard goal.activationState == .active || goal.activationState == .draft else {
                return false
            }

            guard goal.progress < 1.0 else {
                return false
            }

            // Check if goal hasn't been updated in threshold days
            let timeSinceUpdate = now.timeIntervalSince(goal.updatedAt)
            return timeSinceUpdate >= threshold
        }
    }

    func analyzeStagnantGoals(_ goals: [Goal]) async {
        let stagnant = detectStagnantGoals(from: goals)

        await MainActor.run {
            self.stagnantGoals = stagnant
        }

        // Generate insights for stagnant goals
        for goal in stagnant {
            await generateStagnationInsight(for: goal, allGoals: goals)
        }

        await MainActor.run {
            self.lastAnalysisDate = Date()
        }

        print("🔍 Detected \(stagnant.count) stagnant goals")
    }

    private func generateStagnationInsight(for goal: Goal, allGoals: [Goal]) async {
        let context = await userContextService.buildContext(from: allGoals)
        let daysSinceUpdate = Int(Date().timeIntervalSince(goal.updatedAt) / 86400)

        let peerGoals = context.goalSnapshots
            .filter { snapshot in
                snapshot.category.caseInsensitiveCompare(goal.category) == .orderedSame
            }

        let peerCompletionRate: Int
        if peerGoals.isEmpty {
            peerCompletionRate = 0
        } else {
            let completedPeers = peerGoals.filter { $0.progress >= 1.0 }
            peerCompletionRate = Int((Double(completedPeers.count) / Double(peerGoals.count)) * 100)
        }

        var message = "Consider breaking it down further or adjusting the timeline."
        if peerCompletionRate > 0 {
            message = "Peers in \(goal.category.lowercased()) complete at a \(peerCompletionRate)% rate—let's reclaim momentum."
        }

        let insight = ProactiveInsight(
            goalId: goal.id,
            type: .stagnation,
            priority: .medium,
            title: "'\(goal.title)' hasn't moved in \(daysSinceUpdate) days",
            message: message,
            suggestedActions: [
                ProactiveInsightAction(type: "breakdown", label: "Break Down Further"),
                ProactiveInsightAction(type: "reschedule", label: "Adjust Timeline"),
                ProactiveInsightAction(type: "archive", label: "Archive This Goal")
            ],
            createdAt: Date()
        )

        await MainActor.run {
            // Only add if not already present
            if !self.insights.contains(where: { $0.goalId == goal.id && $0.type == .stagnation }) {
                self.insights.append(insight)
            }
        }
    }

    // MARK: - Pattern Analysis

    func analyzeCompletionPatterns(from goals: [Goal]) -> CompletionPatternInsight {
        let completed = goals.filter { $0.progress >= 1.0 }
        let active = goals.filter { $0.activationState == .active && $0.progress < 1.0 }

        // Calculate average completion time
        let completionTimes = completed.compactMap { goal -> TimeInterval? in
            let elapsed = goal.updatedAt.timeIntervalSince(goal.createdAt)
            return elapsed > 0 ? elapsed : nil
        }

        let avgCompletionDays = completionTimes.isEmpty ? 0 : completionTimes.reduce(0, +) / Double(completionTimes.count) / 86400

        // Identify slow-moving goals
        let slowGoals = active.filter { goal in
            let elapsed = Date().timeIntervalSince(goal.createdAt)
            let elapsedDays = elapsed / 86400
            return elapsedDays > avgCompletionDays * 1.5 && goal.progress < 0.5
        }

        return CompletionPatternInsight(
            averageCompletionDays: Int(avgCompletionDays),
            completedCount: completed.count,
            activeCount: active.count,
            slowMovingGoals: slowGoals.map { $0.id }
        )
    }

    // MARK: - Daily Insights

    func generateDailyInsights(from goals: [Goal]) async {
        // Clear old insights
        await MainActor.run {
            insights.removeAll()
        }

        // Stagnation check
        await analyzeStagnantGoals(goals)

        // Pattern analysis
        let patterns = analyzeCompletionPatterns(from: goals)

        // Generate "quick wins" insight
        let nearComplete = goals.filter { $0.progress >= 0.8 && $0.progress < 1.0 }
        if !nearComplete.isEmpty {
            let insight = ProactiveInsight(
                goalId: nil,
                type: .quickWin,
                priority: .high,
                title: "\(nearComplete.count) goal\(nearComplete.count == 1 ? " is" : "s are") almost done!",
                message: "Finish them today for quick wins: \(nearComplete.map { $0.title }.joined(separator: ", "))",
                suggestedActions: [
                    ProactiveInsightAction(type: "bulk_complete", label: "Complete All")
                ],
                createdAt: Date()
            )

            await MainActor.run {
                self.insights.insert(insight, at: 0)
            }
        }

        // Generate "now goals not activated" insight
        let nowGoalsNotActive = goals.filter { $0.priority == .now && $0.activationState != .active }
        if !nowGoalsNotActive.isEmpty {
            let insight = ProactiveInsight(
                goalId: nil,
                type: .unactivated,
                priority: .high,
                title: "\(nowGoalsNotActive.count) 'Now' goal\(nowGoalsNotActive.count == 1 ? "" : "s") not activated",
                message: "These need scheduling: \(nowGoalsNotActive.map { $0.title }.joined(separator: ", "))",
                suggestedActions: [
                    ProactiveInsightAction(type: "activate_all", label: "Activate All")
                ],
                createdAt: Date()
            )

            await MainActor.run {
                self.insights.insert(insight, at: 0)
            }
        }

        if patterns.averageCompletionDays > 0 {
            let slowGoals = goals.filter { patterns.slowMovingGoals.contains($0.id) }
            let slowTitles = slowGoals.map { $0.title }.joined(separator: ", ")
            let hasSlowGoals = !slowGoals.isEmpty

            let title = hasSlowGoals
                ? "Momentum check: \(slowGoals.count) goal\(slowGoals.count == 1 ? "" : "s") drifting"
                : "Great pace — goals completing in \(patterns.averageCompletionDays) days on average"
            let message = hasSlowGoals
                ? "These are falling behind average pace: \(slowTitles)."
                : "Keep the streak going. Average completion pace sits at \(patterns.averageCompletionDays) days."

            let pacingInsight = ProactiveInsight(
                goalId: slowGoals.first?.id,
                type: hasSlowGoals ? .overdue : .suggestion,
                priority: hasSlowGoals ? .medium : .low,
                title: title,
                message: message,
                suggestedActions: hasSlowGoals
                    ? [ProactiveInsightAction(type: "reschedule", label: "Refresh Plan")]
                    : [],
                createdAt: Date()
            )

            await MainActor.run {
                self.insights.append(pacingInsight)
            }
        }

        print("💡 Generated \(insights.count) daily insights")
    }

    // MARK: - Smart Progress Calculation (Read-Only)

    func calculateSmartProgress(for goal: Goal) -> Double {
        // If goal has subgoals, progress is average of subgoal progress
        if let subgoals = goal.subgoals, !subgoals.isEmpty {
            let totalProgress = subgoals.reduce(0.0) { $0 + $1.progress }
            return totalProgress / Double(subgoals.count)
        }

        // Otherwise, use manual progress
        return goal.progress
    }

    // Note: Progress updates are now handled by AutopilotService to maintain
    // separation of concerns (ProactiveAI = read-only, AutopilotAI = write)

    // MARK: - Clear Insights

    func clearInsights() {
        insights.removeAll()
    }

    func dismissInsight(_ insight: ProactiveInsight) {
        insights.removeAll { $0.id == insight.id }
    }
}

// MARK: - Models

struct ProactiveInsight: Identifiable, Equatable {
    let id = UUID()
    let goalId: UUID?
    let type: InsightType
    let priority: InsightPriority
    let title: String
    let message: String
    let suggestedActions: [ProactiveInsightAction]
    let createdAt: Date

    enum InsightType {
        case stagnation
        case quickWin
        case unactivated
        case overdue
        case suggestion
    }

    enum InsightPriority {
        case low
        case medium
        case high
    }
}

struct ProactiveInsightAction: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let label: String
}

struct CompletionPatternInsight {
    let averageCompletionDays: Int
    let completedCount: Int
    let activeCount: Int
    let slowMovingGoals: [UUID]
}