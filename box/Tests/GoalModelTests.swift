#if canImport(XCTest)
import XCTest
@testable import box

final class GoalModelTests: XCTestCase {

    func testGoalDefaultsIncludeKindAndCollections() {
        let goal = Goal(title: "Write a book")

        XCTAssertEqual(goal.kind, .campaign)
        XCTAssertTrue(goal.phases.isEmpty)
        XCTAssertTrue(goal.projections.isEmpty)
        XCTAssertNil(goal.targetMetric)
    }

    func testGoalProjectionLifecycleFields() {
        let interval = DateInterval(start: .now, duration: 86_400)
        let projection = GoalProjection(
            title: "Draft outline",
            detail: "Create chapter scaffolding",
            startDate: interval.start,
            endDate: interval.end,
            expectedMetricDelta: 0.2,
            metricUnit: "chapters",
            confidence: 0.8
        )

        XCTAssertEqual(projection.status, .upcoming)
        XCTAssertEqual(projection.metricUnit, "chapters")
        XCTAssertEqual(projection.expectedMetricDelta, 0.2)
    }

    func testGoalTimelineBuilderProducesProjectionMetric() {
        let goal = Goal(title: "Lose weight", kind: .campaign)

        let metric = GoalTargetMetric(label: "Body fat", targetValue: 5, unit: "kg", baselineValue: 8)
        metric.goal = goal
        goal.targetMetric = metric

        let projection = GoalProjection(
            title: "Cut refined carbs",
            detail: "Dial in macro split",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86_400 * 5),
            expectedMetricDelta: 2.5,
            metricUnit: "kg",
            confidence: 0.8
        )
        projection.goal = goal
        goal.projections = [projection]

        let horizon = DateInterval(
            start: Date().addingTimeInterval(-86_400),
            end: Date().addingTimeInterval(86_400 * 14)
        )

        let entries = GoalTimelineBuilder.entries(for: goal, in: horizon)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .projection)
        XCTAssertEqual(entries.first?.metricSummary, "Δ2.5 kg body fat")
    }
}
#endif

