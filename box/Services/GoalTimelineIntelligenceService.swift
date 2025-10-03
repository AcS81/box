//
//  GoalTimelineIntelligenceService.swift
//  box
//
//  Created on 02.10.2025.
//

import Foundation

@MainActor
final class GoalTimelineIntelligenceService {
    static let shared = GoalTimelineIntelligenceService(
        aiService: AIService.shared,
        contextService: UserContextService.shared
    )

    private let aiService: AIService
    private let contextService: UserContextService
    private let highlightLimit = 4

    init(aiService: AIService, contextService: UserContextService) {
        self.aiService = aiService
        self.contextService = contextService
    }

    func enrichEntries(
        _ entries: [GoalTimelineEntry],
        for goal: Goal,
        horizon: DateInterval,
        portfolio: [Goal]
    ) async throws -> GoalTimelineInsightsResult {
        guard !entries.isEmpty else {
            return GoalTimelineInsightsResult(entries: [], portfolioHeadline: nil)
        }

        let context = await contextService.buildContext(from: portfolio)
        let response = try await aiService.processRequest(
            .generateTimelineInsights(
                goal: goal,
                entries: entries,
                horizon: horizon,
                context: context
            ),
            responseType: TimelineInsightsResponse.self
        )

        var insightMap: [String: TimelineInsightsResponse.Insight] = [:]
        for insight in response.insights {
            insightMap[insight.entryId] = insight
        }

        let enrichedEntries = entries.map { entry in
            guard let insight = insightMap[entry.id.uuidString] else { return entry }

            let highlights = insight.subtaskHighlights.map { Array($0.prefix(highlightLimit)) } ?? []

            let intelligence = GoalTimelineEntryIntelligence(
                outcomeSummary: insight.outcomeSummary,
                subtaskHighlights: highlights,
                recommendedAction: insight.recommendedAction,
                completionLikelihood: insight.completionLikelihood,
                readyToMarkGoalComplete: insight.readyToMarkGoalComplete ?? false
            )

            return entry.enriched(with: intelligence)
        }

        return GoalTimelineInsightsResult(
            entries: enrichedEntries,
            portfolioHeadline: response.portfolioHeadline
        )
    }
}

struct TimelineInsightsResponse: Codable {
    struct Insight: Codable {
        let entryId: String
        let outcomeSummary: String
        let subtaskHighlights: [String]?
        let recommendedAction: String?
        let completionLikelihood: Double?
        let readyToMarkGoalComplete: Bool?
    }

    let insights: [Insight]
    let portfolioHeadline: String?
}

struct GoalTimelineInsightsResult {
    let entries: [GoalTimelineEntry]
    let portfolioHeadline: String?
}

