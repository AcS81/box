#if canImport(XCTest)
//
//  AIServiceTests.swift
//  box
//
//  Created on 29.09.2025.
//

import XCTest
import SwiftData
@testable import box

@MainActor
final class GoalBreakdownBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Goal.self,
                 GoalDependency.self,
                 GoalSnapshot.self,
                 GoalRevision.self,
                 ScheduledEventLink.self,
                 AIMirrorCard.self,
                 AIMirrorSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testApplyBuildsHierarchyAndDependencies() throws {
        let parent = Goal(title: "Launch macOS AI workspace", content: "Ship the nested task orchestration flow", category: "Product", priority: .now)
        context.insert(parent)

        let response = GoalBreakdownResponse(
            subtasks: [
                GoalBreakdownResponse.Node(
                    id: "design-phase",
                    title: "Design phase",
                    description: "Plan the Liquid Glass UI and dependency map",
                    estimatedHours: 6,
                    dependencies: [],
                    difficulty: "medium",
                    children: [
                        GoalBreakdownResponse.Node(
                            id: "design-wireframes",
                            title: "Create wireframes",
                            description: "Sketch the multi-level task explorer",
                            estimatedHours: 2,
                            dependencies: [],
                            difficulty: "easy",
                            children: [],
                            isAtomic: true
                        ),
                        GoalBreakdownResponse.Node(
                            id: "design-copy",
                            title: "Draft prompts and copy",
                            description: "Write AI instructions for subtask generation",
                            estimatedHours: 1.5,
                            dependencies: [],
                            difficulty: "easy",
                            children: [],
                            isAtomic: true
                        )
                    ],
                    isAtomic: false
                ),
                GoalBreakdownResponse.Node(
                    id: "implementation",
                    title: "Implementation",
                    description: "Build the AI-driven subtask tree with dependency tracking",
                    estimatedHours: 12,
                    dependencies: ["design-phase"],
                    difficulty: "hard",
                    children: [
                        GoalBreakdownResponse.Node(
                            id: "implementation-core",
                            title: "Build core flow",
                            description: "Hook GoalBreakdownBuilder into the workspace",
                            estimatedHours: 5,
                            dependencies: ["design-wireframes"],
                            difficulty: "medium",
                            children: [],
                            isAtomic: true
                        ),
                        GoalBreakdownResponse.Node(
                            id: "implementation-qa",
                            title: "QA nested breakdowns",
                            description: "Validate dependency visualisation and editing",
                            estimatedHours: 3,
                            dependencies: ["implementation-core"],
                            difficulty: "medium",
                            children: [],
                            isAtomic: true
                        )
                    ],
                    isAtomic: false
                )
            ],
            recommendedOrder: ["design-phase", "implementation"],
            totalEstimatedHours: 17.5
        )

        let result = GoalBreakdownBuilder.apply(response: response, to: parent, in: context)

        XCTAssertEqual(result.createdGoals.count, 6, "Expected all nodes in the tree to become persistent goals")
        XCTAssertEqual(result.atomicTaskCount, 4, "Expected four atomic leaves")
        XCTAssertEqual(result.dependencyCount, 3, "Expected three dependency links across the graph")
        XCTAssertEqual(Set(result.assignedIdentifiers.values).count, result.assignedIdentifiers.count, "Assigned identifiers should be unique per goal")

        let topLevel = parent.sortedSubgoals
        XCTAssertEqual(topLevel.map { $0.title }, ["Design phase", "Implementation"], "Top-level ordering should match recommended order")

        guard
            let designGoal = topLevel.first(where: { $0.title == "Design phase" }),
            let implementationGoal = topLevel.first(where: { $0.title == "Implementation" })
        else {
            return XCTFail("Missing expected top-level goals")
        }

        XCTAssertTrue(designGoal.hasBeenBrokenDown)
        XCTAssertTrue(implementationGoal.hasBeenBrokenDown)
        XCTAssertEqual(implementationGoal.incomingDependencies.count, 1)
        XCTAssertEqual(implementationGoal.incomingDependencies.first?.prerequisite?.title, "Design phase")

        let implementationChildren = implementationGoal.sortedSubgoals
        XCTAssertEqual(implementationChildren.count, 2)
        XCTAssertEqual(implementationChildren.first?.incomingDependencies.first?.prerequisite?.title, "Create wireframes")
        XCTAssertEqual(implementationChildren.last?.incomingDependencies.first?.prerequisite?.title, "Build core flow")
    }

    func testAggregatedProgressUsesLeafAverage() throws {
        let parent = Goal(title: "Aggregate progress", content: "")
        context.insert(parent)

        let response = GoalBreakdownResponse(
            subtasks: [
                GoalBreakdownResponse.Node(
                    id: "phase-a",
                    title: "Phase A",
                    description: "High-level step",
                    estimatedHours: 2,
                    dependencies: [],
                    difficulty: "easy",
                    children: [
                        GoalBreakdownResponse.Node(
                            id: "leaf-1",
                            title: "Leaf 1",
                            description: "",
                            estimatedHours: 1,
                            dependencies: [],
                            difficulty: "easy",
                            children: [],
                            isAtomic: true
                        ),
                        GoalBreakdownResponse.Node(
                            id: "leaf-2",
                            title: "Leaf 2",
                            description: "",
                            estimatedHours: 1,
                            dependencies: [],
                            difficulty: "easy",
                            children: [],
                            isAtomic: true
                        )
                    ],
                    isAtomic: false
                ),
                GoalBreakdownResponse.Node(
                    id: "phase-b",
                    title: "Phase B",
                    description: "Another high-level step",
                    estimatedHours: 3,
                    dependencies: ["phase-a"],
                    difficulty: "medium",
                    children: [
                        GoalBreakdownResponse.Node(
                            id: "leaf-3",
                            title: "Leaf 3",
                            description: "",
                            estimatedHours: 1,
                            dependencies: [],
                            difficulty: "medium",
                            children: [],
                            isAtomic: true
                        )
                    ],
                    isAtomic: false
                )
            ],
            recommendedOrder: ["phase-a", "phase-b"],
            totalEstimatedHours: 5
        )

        _ = GoalBreakdownBuilder.apply(response: response, to: parent, in: context)

        let leaves = parent.leafDescendants()
        XCTAssertEqual(leaves.count, 3)

        leaves.first(where: { $0.title == "Leaf 1" })?.progress = 1.0
        leaves.first(where: { $0.title == "Leaf 2" })?.progress = 0.5
        leaves.first(where: { $0.title == "Leaf 3" })?.progress = 0.0

        XCTAssertEqual(parent.aggregatedProgress(), 0.5, accuracy: 0.001, "Average progress should reflect leaf progress only")
    }

    func testTimeToCompletionHandlesNoProgressAndCompletion() {
        let idleGoal = Goal(title: "Idle")
        idleGoal.progress = 0.0
        XCTAssertEqual(idleGoal.timeToCompletion, "No progress yet")

        let doneGoal = Goal(title: "Done")
        doneGoal.progress = 1.0
        XCTAssertEqual(doneGoal.timeToCompletion, "Completed")
    }

}

#endif
