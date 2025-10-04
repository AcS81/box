import Foundation
import SwiftData

enum GoalCreationMapper {

    static func apply(
        _ response: GoalCreationResponse,
        to goal: Goal,
        referenceDate: Date = .now,
        modelContext: ModelContext
    ) {
        // Configure kind
        if let kindRaw = response.kind?.lowercased(), let mappedKind = Goal.Kind(rawValue: kindRaw) {
            goal.kind = mappedKind
        }

        // Target metric
        if let metricPayload = response.targetMetric {
            let metric = goal.targetMetric ?? GoalTargetMetric(label: metricPayload.label)
            metric.label = metricPayload.label
            metric.targetValue = metricPayload.targetValue
            metric.unit = metricPayload.unit
            metric.baselineValue = metricPayload.baselineValue
            metric.measurementWindowDays = metricPayload.measurementWindowDays
            metric.lowerBound = metricPayload.lowerBound
            metric.upperBound = metricPayload.upperBound
            metric.notes = metricPayload.notes
            metric.lastUpdatedAt = referenceDate
            metric.goalID = goal.id
            metric.goal = goal

            if goal.targetMetric == nil {
                modelContext.insert(metric)
                goal.targetMetric = metric
            }
        } else if let existingMetric = goal.targetMetric {
            modelContext.delete(existingMetric)
            goal.targetMetric = nil
        }

        // Phases
        if let phasePayloads = response.phases {
            // Clear existing
            goal.phases.forEach { modelContext.delete($0) }
            goal.phases = []

            for payload in phasePayloads.sorted(by: { $0.order < $1.order }) {
                let phase = GoalPhase(
                    title: payload.title,
                    summary: payload.summary ?? "",
                    order: payload.order
                )
                phase.goalID = goal.id
                phase.goal = goal
                modelContext.insert(phase)
                goal.phases.append(phase)
            }
        }

        // Projections / roadmap slices (14-day horizon)
        if let slices = response.roadmapSlices {
            goal.projections.forEach { modelContext.delete($0) }
            goal.projections = []

            for payload in slices {
                let start = Calendar.current.date(byAdding: .day, value: payload.startOffsetDays, to: referenceDate) ?? referenceDate
                let end = Calendar.current.date(byAdding: .day, value: payload.endOffsetDays, to: referenceDate) ?? start
                let projection = GoalProjection(
                    title: payload.title,
                    detail: payload.detail,
                    startDate: start,
                    endDate: max(start, end),
                    expectedMetricDelta: payload.expectedMetricDelta,
                    metricUnit: payload.metricUnit,
                    confidence: clampConfidence(payload.confidence)
                )
                projection.goalID = goal.id
                projection.goal = goal
                modelContext.insert(projection)
                goal.projections.append(projection)
            }
        }

        goal.updatedAt = referenceDate
    }

    /// Generate the first sequential step for a newly created goal
    static func generateFirstStep(
        for goal: Goal,
        context: AIContext,
        modelContext: ModelContext
    ) async throws {
        guard !goal.hasSequentialSteps else { return }

        let nextStepResponse = try await AIService.shared.generateNextSequentialStep(
            for: goal,
            completedStep: goal, // Use goal itself as placeholder for first step
            context: context
        )

        // Create the first sequential step
        let firstStep = goal.createSequentialStep(
            title: nextStepResponse.title,
            outcome: nextStepResponse.outcome,
            targetDate: Calendar.current.date(
                byAdding: .day,
                value: nextStepResponse.daysFromNow ?? 7,
                to: goal.createdAt
            ) ?? Date().addingTimeInterval(TimeInterval((nextStepResponse.daysFromNow ?? 7) * 86400))
        )
        firstStep.stepStatus = .current
        firstStep.content = nextStepResponse.aiSuggestion ?? ""  // Set AI's proactive guidance
        goal.updatedAt = Date()

        try modelContext.save()
    }

    private static func clampConfidence(_ value: Double?) -> Double {
        guard let value else { return 0.75 }
        return min(max(value, 0.05), 0.99)
    }
}

