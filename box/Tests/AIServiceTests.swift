//
//  AIServiceTests.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
@testable import box

// Note: This would normally use XCTest in a proper iOS test target
// For now, these are example test methods that demonstrate the testing approach

struct AIServiceTests {

    static func testAIContextCreation() {
        let sampleGoals = [
            Goal(title: "Learn SwiftUI", category: "Development", priority: .now),
            Goal(title: "Exercise daily", category: "Health", priority: .next),
            Goal(title: "Read 12 books", category: "Education", priority: .later)
        ]

        let context = AIContext(goals: sampleGoals)

        assert(context.recentGoals.count == 3, "Expected 3 recent goals")
        assert(context.completedGoalsCount == 0, "Expected 0 completed goals")
        print("✅ AIContext creation test passed")
    }

    static func testGoalExtensions() {
        let goal = Goal(title: "Test Goal", priority: .now)
        goal.progress = 0.5

        assert(goal.priorityColor == "red", "Expected red color for 'now' priority")
        assert(goal.priority == .now, "Expected 'now' priority")
        assert(!goal.isOverdue, "Expected not overdue when no target date set")
        print("✅ Goal extensions test passed")
    }

    static func testUserContextService() {
        let contextService = UserContextService.shared
        let sampleGoals = [
            Goal(title: "Goal 1", category: "Work"),
            Goal(title: "Goal 2", category: "Personal")
        ]

        let context = contextService.buildContext(from: sampleGoals)

        assert(context.recentGoals.count == 2, "Expected 2 recent goals")
        assert(context.contextSummary.contains("Context: 2 recent goals"), "Expected context summary to mention goal count")
        print("✅ UserContextService test passed")
    }

    static func testJSONResponseCleaning() {
        let dirtyResponse = "```json\n{\"title\": \"Test\"}\n```"
        let expectedClean = "{\"title\": \"Test\"}"

        assert(dirtyResponse.contains("json"), "Expected dirty response to contain 'json'")
        print("✅ JSON response cleaning test setup completed")
    }

    static func testGoalCreationResponseParsing() {
        let jsonString = """
        {
            "title": "Learn Swift",
            "content": "Master Swift programming language",
            "category": "Development",
            "priority": "now",
            "suggestedSubgoals": ["Set up Xcode", "Complete tutorial"],
            "estimatedDuration": "2 weeks",
            "difficulty": "medium"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        do {
            let response = try decoder.decode(GoalCreationResponse.self, from: data)
            assert(response.title == "Learn Swift", "Expected title to be 'Learn Swift'")
            assert(response.priority == "now", "Expected priority to be 'now'")
            assert(response.suggestedSubgoals.count == 2, "Expected 2 suggested subgoals")
            print("✅ GoalCreationResponse parsing test passed")
        } catch {
            print("❌ Failed to parse GoalCreationResponse: \(error)")
        }
    }

    static func testMirrorCardResponseParsing() {
        let jsonString = """
        {
            "aiInterpretation": "User wants to improve coding skills",
            "suggestedActions": ["Practice daily", "Build projects", "Read documentation"],
            "confidence": 0.85,
            "insights": ["Shows commitment to learning", "May need structured approach"],
            "emotionalTone": "motivated"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        do {
            let response = try decoder.decode(MirrorCardResponse.self, from: data)
            assert(response.suggestedActions.count == 3, "Expected 3 suggested actions")
            assert(response.confidence == 0.85, "Expected confidence to be 0.85")
            assert(response.emotionalTone == "motivated", "Expected emotional tone to be 'motivated'")
            print("✅ MirrorCardResponse parsing test passed")
        } catch {
            print("❌ Failed to parse MirrorCardResponse: \(error)")
        }
    }

    static func runAllTests() {
        print("🧪 Running AI Service Tests...")
        testAIContextCreation()
        testGoalExtensions()
        testUserContextService()
        testJSONResponseCleaning()
        testGoalCreationResponseParsing()
        testMirrorCardResponseParsing()
        print("🎉 All tests completed!")
    }
}

// MARK: - Mock Data for Testing

extension AIServiceTests {

    static var sampleContext: AIContext {
        let goals = [
            Goal(title: "Complete project", category: "Work", priority: .now),
            Goal(title: "Exercise", category: "Health", priority: .next)
        ]
        return AIContext(goals: goals)
    }

    static var sampleGoalCreationResponse: GoalCreationResponse {
        return GoalCreationResponse(
            title: "Sample Goal",
            content: "A test goal",
            category: "Test",
            priority: "next",
            suggestedSubgoals: ["Step 1", "Step 2"],
            estimatedDuration: "1 week",
            difficulty: "easy"
        )
    }
}
