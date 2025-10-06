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

    /// Generate initial roadmap (3-7 steps) for a newly created goal
    static func generateInitialRoadmap(
        for goal: Goal,
        context: AIContext,
        modelContext: ModelContext
    ) async throws {
        guard !goal.hasSequentialSteps else { return }

        // Call AI ONCE to get 3-7 steps upfront
        let roadmapResponse = try await AIService.shared.generateInitialRoadmap(
            for: goal,
            context: context
        )

        // Create all steps at once
        for (index, stepData) in roadmapResponse.steps.enumerated() {
            let step = goal.createSequentialStep(
                title: stepData.title,
                outcome: stepData.outcome,
                targetDate: Calendar.current.date(
                    byAdding: .day,
                    value: stepData.daysFromStart,
                    to: goal.createdAt
                ) ?? Date().addingTimeInterval(TimeInterval(stepData.daysFromStart * 86400))
            )

            // First step is current, rest are pending
            step.stepStatus = index == 0 ? .current : .pending
            step.aiReasoning = stepData.reasoning ?? ""
            step.estimatedEffortHours = stepData.estimatedEffortHours ?? 0
            step.updatedAt = Date()
        }

        goal.updatedAt = Date()
        try modelContext.save()

        print("✅ Generated \(roadmapResponse.steps.count) steps upfront - no more API calls until user adds input or steps run out")
    }

    private static func clampConfidence(_ value: Double?) -> Double {
        guard let value else { return 0.75 }
        return min(max(value, 0.05), 0.99)
    }
}

