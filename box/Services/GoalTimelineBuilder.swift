//
//  GoalTimelineBuilder.swift
//  box
//
//  Created on 02.10.2025.
//

import Foundation

struct GoalTimelineEntry: Identifiable {
    enum Kind: String {
        case event
        case projection
        case phase
        case metricCheckpoint
    }

    let id: UUID
    let goalID: UUID
    let goalTitle: String
    let kind: Kind
    let title: String
    let detail: String?
    let startDate: Date
    let endDate: Date
    let metricSummary: String?
    let confidence: Double?
    let intelligence: GoalTimelineEntryIntelligence?

    init(
        id: UUID,
        goalID: UUID,
        goalTitle: String,
        kind: Kind,
        title: String,
        detail: String?,
        startDate: Date,
        endDate: Date,
        metricSummary: String?,
        confidence: Double?,
        intelligence: GoalTimelineEntryIntelligence? = nil
    ) {
        self.id = id
        self.goalID = goalID
        self.goalTitle = goalTitle
        self.kind = kind
        self.title = title
        self.detail = detail
        self.startDate = startDate
        self.endDate = endDate
        self.metricSummary = metricSummary
        self.confidence = confidence
        self.intelligence = intelligence
    }

    func enriched(with intelligence: GoalTimelineEntryIntelligence?) -> GoalTimelineEntry {
        GoalTimelineEntry(
            id: id,
            goalID: goalID,
            goalTitle: goalTitle,
            kind: kind,
            title: title,
            detail: detail,
            startDate: startDate,
            endDate: endDate,
            metricSummary: metricSummary,
            confidence: confidence,
            intelligence: intelligence
        )
    }
}

struct GoalTimelineEntryIntelligence: Equatable {
    let outcomeSummary: String
    let subtaskHighlights: [String]
    let recommendedAction: String?
    let completionLikelihood: Double?
    let readyToMarkGoalComplete: Bool
}

enum GoalTimelineBuilder {

    static func entries(
        for goal: Goal,
        in horizon: DateInterval,
        referenceDate: Date = .now
    ) -> [GoalTimelineEntry] {
        var results: [GoalTimelineEntry] = []

        // Goal projections (roadmap slices)
        for projection in goal.projections {
            let interval = DateInterval(start: projection.startDate, end: projection.endDate)
            guard horizon.intersects(interval) else { continue }

            let metric = formattedMetric(
                delta: projection.expectedMetricDelta,
                unit: projection.metricUnit,
                label: goal.targetMetric?.label
            )

            results.append(
                GoalTimelineEntry(
                    id: projection.id,
                    goalID: goal.id,
                    goalTitle: goal.title,
                    kind: .projection,
                    title: projection.title,
                    detail: projection.detail,
                    startDate: projection.startDate,
                    endDate: projection.endDate,
                    metricSummary: metric,
                    confidence: projection.confidence
                )
            )
        }

        // Goal phases (use planned window to anchor if available)
        for phase in goal.phases {
            let anchor = phase.startedAt ?? phase.goal?.activatedAt ?? goal.activatedAt ?? goal.createdAt
            let end = phase.completedAt ?? Calendar.current.date(byAdding: .day, value:  phase.status == .planned ? 3 : 0, to: anchor) ?? anchor
            let interval = DateInterval(start: anchor, end: max(anchor, end))
            guard horizon.intersects(interval) else { continue }

            results.append(
                GoalTimelineEntry(
                    id: phase.id,
                    goalID: goal.id,
                    goalTitle: goal.title,
                    kind: .phase,
                    title: phase.title,
                    detail: phase.summary,
                    startDate: interval.start,
                    endDate: interval.end,
                    metricSummary: nil,
                    confidence: nil
                )
            )
        }

        // Scheduled events (single or multi-hour blocks)
        for link in goal.scheduledEvents {
            guard let start = link.startDate ?? link.endDate else { continue }
            let end = link.endDate ?? start.addingTimeInterval(3600)
            let interval = DateInterval(start: start, end: end)
            guard horizon.intersects(interval) else { continue }

            let confidence: Double = {
                switch link.status {
                case .confirmed: return 0.95
                case .proposed: return 0.6
                case .cancelled: return 0.2
                }
            }()

            results.append(
                GoalTimelineEntry(
                    id: link.id,
                    goalID: goal.id,
                    goalTitle: goal.title,
                    kind: .event,
                    title: eventHeadline(for: link),
                    detail: link.status == .cancelled ? "Session cancelled" : link.status == .confirmed ? "Confirmed focus block" : "Awaiting confirmation",
                    startDate: start,
                    endDate: end,
                    metricSummary: nil,
                    confidence: confidence
                )
            )
        }

        // Campaign metric checkpoint when no projections exist
        if goal.kind != .event, goal.projections.isEmpty, let metric = goal.targetMetric {
            let spanDays = metric.measurementWindowDays ?? Int(horizon.duration / 86_400.0)
            let start = referenceDate
            let end = Calendar.current.date(byAdding: .day, value: max(spanDays, 1), to: start) ?? start.addingTimeInterval(horizon.duration)
            let summary = formattedMetric(
                delta: deltaValue(target: metric.targetValue, baseline: metric.baselineValue),
                unit: metric.unit,
                label: metric.label
            )

            results.append(
                GoalTimelineEntry(
                    id: UUID(),
                    goalID: goal.id,
                    goalTitle: goal.title,
                    kind: .metricCheckpoint,
                    title: summary ?? metric.label,
                    detail: metric.notes,
                    startDate: start,
                    endDate: max(start, end),
                    metricSummary: summary,
                    confidence: nil
                )
            )
        }

        return results.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.startDate < rhs.startDate
        }
    }

    private static func deltaValue(target: Double?, baseline: Double?) -> Double? {
        guard let target else { return nil }
        guard let baseline else { return target }
        return abs(target - baseline)
    }

    private static func formattedMetric(delta: Double?, unit: String?, label: String?) -> String? {
        guard let delta else { return nil }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = delta.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        let value = formatter.string(from: NSNumber(value: delta)) ?? String(format: "%.1f", delta)
        let unitText = unit.map { " \($0)" } ?? ""
        let labelText = label.map { " \($0.lowercased())" } ?? ""
        return "Δ\(value)\(unitText)\(labelText)".trimmingCharacters(in: .whitespaces)
    }

    private static func eventHeadline(for link: ScheduledEventLink) -> String {
        switch link.status {
        case .confirmed:
            return "Confirmed session"
        case .proposed:
            return "Proposed slot"
        case .cancelled:
            return "Cancelled session"
        }
    }
}

