//
//  AIService.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import SwiftUI
import Combine
import SwiftData

struct AIContext {
    let recentGoals: [Goal]
    let userPatterns: [String: Any]
    let currentTime: Date
    let preferredWorkingHours: (start: Int, end: Int)?
    let completedGoalsCount: Int
    let averageCompletionTime: TimeInterval?

    init(goals: [Goal] = [], patterns: [String: Any] = [:], preferredHours: (Int, Int)? = nil) {
        self.recentGoals = Array(goals.prefix(10))
        self.userPatterns = patterns
        self.currentTime = Date()
        self.preferredWorkingHours = preferredHours
        self.completedGoalsCount = goals.filter { $0.progress >= 1.0 }.count
        self.averageCompletionTime = AIContext.calculateAverageCompletionTime(goals: goals)
    }

    private static func calculateAverageCompletionTime(goals: [Goal]) -> TimeInterval? {
        let completedGoals = goals.filter { $0.progress >= 1.0 }
        guard !completedGoals.isEmpty else { return nil }

        let totalTime = completedGoals.reduce(0.0) { sum, goal in
            sum + goal.updatedAt.timeIntervalSince(goal.createdAt)
        }
        return totalTime / Double(completedGoals.count)
    }
}

@MainActor
class AIService: ObservableObject {
    static let shared = AIService(secretsService: SecretsService.shared)

    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let requestTimeout: TimeInterval = 30.0
    private var requestCache: [String: CachedResponse] = [:]
    private let cacheTimeout: TimeInterval = 300
    private let secretsService: SecretsService
    private var cancellables: Set<AnyCancellable> = []

    private struct CachedResponse {
        let response: String
        let timestamp: Date
    }

    enum AIFunction {
        case createGoal(input: String, context: AIContext)
        case breakdownGoal(goal: Goal, context: AIContext)
        case chatWithGoal(message: String, goal: Goal, context: AIContext)
        case generateCalendarEvents(goal: Goal, context: AIContext)
        case summarizeProgress(goal: Goal, context: AIContext)
        case reorderCards(goals: [Goal], instruction: String, context: AIContext)
        case generateMirrorCard(goal: Goal, context: AIContext)
    }

    private init(secretsService: SecretsService) {
        self.secretsService = secretsService

        secretsService.$openAIKey
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.clearCache()
            }
            .store(in: &cancellables)
    }

    private var currentAPIKey: String {
        if let key = secretsService.openAIKey, !key.isEmpty {
            return key
        }
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    func processRequest<T: Codable>(_ function: AIFunction, responseType: T.Type) async throws -> T {
        let cacheKey = generateCacheKey(for: function)

        if let cachedResponse = getCachedResponse(for: cacheKey) {
            return try parseJSONResponse(cachedResponse, as: responseType)
        }

        let response = try await makeAPIRequest(for: function)
        cacheResponse(response, for: cacheKey)

        return try parseJSONResponse(response, as: responseType)
    }

    func processRequest(_ function: AIFunction) async throws -> String {
        let cacheKey = generateCacheKey(for: function)

        if let cachedResponse = getCachedResponse(for: cacheKey) {
            return cachedResponse
        }

        let response = try await makeAPIRequest(for: function)
        cacheResponse(response, for: cacheKey)

        return response
    }

    private func makeAPIRequest(for function: AIFunction) async throws -> String {
        let apiKey = currentAPIKey

        guard !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        return try await retryWithExponentialBackoff(maxRetries: 3) {
            try await performSingleAPIRequest(for: function, apiKey: apiKey)
        }
    }

    private func performSingleAPIRequest(for function: AIFunction, apiKey: String) async throws -> String {
        let prompt = buildContextualPrompt(for: function)
        let (systemPrompt, temperature, maxTokens) = getRequestParameters(for: function)

        var request = URLRequest(url: URL(string: baseURL)!, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.networkError
            }

            switch httpResponse.statusCode {
            case 200:
                let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                guard let content = apiResponse.choices.first?.message.content, !content.isEmpty else {
                    throw AIError.invalidResponse
                }
                return content
            case 429:
                throw AIError.rateLimited
            case 401:
                throw AIError.noAPIKey
            case 400:
                print("❌ Bad request to OpenAI API - check prompt formatting")
                throw AIError.invalidFormat
            default:
                print("❌ OpenAI API error: \(httpResponse.statusCode)")
                throw AIError.invalidResponse
            }
        } catch is DecodingError {
            throw AIError.invalidResponse
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError
        }
    }

    private func retryWithExponentialBackoff<T>(maxRetries: Int, operation: () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch AIError.rateLimited {
                lastError = AIError.rateLimited
                if attempt < maxRetries - 1 {
                    let delay = min(pow(2.0, Double(attempt)), 30.0)
                    print("🔄 Rate limited, retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch AIError.networkError {
                lastError = AIError.networkError
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    print("🔄 Network error, retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? AIError.networkError
    }

    private func parseJSONResponse<T: Codable>(_ response: String, as type: T.Type) throws -> T {
        let cleanedResponse = cleanJSONResponse(response)
        let jsonData = cleanedResponse.data(using: .utf8) ?? Data()

        do {
            return try JSONDecoder().decode(type, from: jsonData)
        } catch let decodingError {
            print("❌ JSON parsing failed for response: \(cleanedResponse)")
            print("❌ Decoding error: \(decodingError)")
            throw AIError.invalidResponse
        }
    }

    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[firstBrace...lastBrace])
        }

        return cleaned
    }

    func clearCache() {
        requestCache.removeAll()
        print("🧹 AI request cache cleared")
    }

    func getCacheSize() -> Int {
        return requestCache.count
    }

    private func generateCacheKey(for function: AIFunction) -> String {
        switch function {
        case .createGoal(let input, _):
            return "create_\(input.hashValue)"
        case .breakdownGoal(let goal, _):
            return "breakdown_\(goal.id.uuidString)"
        case .chatWithGoal(let message, let goal, _):
            return "chat_\(goal.id.uuidString)_\(message.hashValue)"
        case .generateCalendarEvents(let goal, _):
            return "calendar_\(goal.id.uuidString)"
        case .summarizeProgress(let goal, _):
            return "summary_\(goal.id.uuidString)_\(Int(goal.progress * 100))"
        case .reorderCards(let goals, let instruction, _):
            return "reorder_\(goals.map { $0.id.uuidString }.joined())_\(instruction.hashValue)"
        case .generateMirrorCard(let goal, _):
            return "mirror_\(goal.id.uuidString)"
        }
    }

    private func getCachedResponse(for key: String) -> String? {
        guard let cached = requestCache[key],
              Date().timeIntervalSince(cached.timestamp) < cacheTimeout else {
            requestCache.removeValue(forKey: key)
            return nil
        }
        return cached.response
    }

    private func cacheResponse(_ response: String, for key: String) {
        requestCache[key] = CachedResponse(response: response, timestamp: Date())
    }

    private func getRequestParameters(for function: AIFunction) -> (systemPrompt: String, temperature: Double, maxTokens: Int) {
        switch function {
        case .createGoal, .breakdownGoal, .generateCalendarEvents, .reorderCards, .generateMirrorCard:
            return (structuredSystemPrompt, 0.3, 1000)
        case .chatWithGoal, .summarizeProgress:
            return (conversationalSystemPrompt, 0.7, 800)
        }
    }

    private func buildContextualPrompt(for function: AIFunction) -> String {
        let context = extractContext(from: function)
        let contextSection = buildContextSection(context)

        switch function {
        case .createGoal(let input, _):
            return """
            \(contextSection)

            Create a goal from this input: "\(input)"

            Return as JSON with the following structure:
            {
                "title": "Clear, actionable goal title",
                "content": "Detailed description with context",
                "category": "Appropriate category based on content",
                "priority": "now|next|later",
                "suggestedSubgoals": ["subgoal1", "subgoal2"],
                "estimatedDuration": "time estimate in hours",
                "difficulty": "easy|medium|hard"
            }
            """

        case .breakdownGoal(let goal, _):
            return """
            \(contextSection)

            Break down this goal into actionable steps:
            Title: "\(goal.title)"
            Context: \(goal.content)
            Current Progress: \(Int(goal.progress * 100))%
            Priority: \(goal.priority.rawValue)

            Return as JSON:
            {
                "subtasks": [
                    {
                        "title": "Specific actionable task",
                        "description": "Clear description of what needs to be done",
                        "estimatedHours": 2,
                        "dependencies": ["other task titles if any"],
                        "difficulty": "easy|medium|hard"
                    }
                ],
                "recommendedOrder": ["task1", "task2"],
                "totalEstimatedHours": 10
            }
            """

        case .chatWithGoal(let message, let goal, _):
            let recentChat = goal.chatHistory?.suffix(5).map { "\($0.isUser ? "User" : "AI"): \($0.content)" }.joined(separator: "\n") ?? "No previous conversation"

            return """
            \(contextSection)

            You are the dedicated AI assistant for this specific goal:
            Goal: "\(goal.title)"
            Description: \(goal.content)
            Progress: \(Int(goal.progress * 100))%
            Priority: \(goal.priority.rawValue)

            Recent conversation:
            \(recentChat)

            User's current message: "\(message)"

            Respond conversationally as this goal's personal coach. Be specific, actionable, and encouraging.
            Reference the goal's context and previous conversation when relevant.
            """

        case .generateCalendarEvents(let goal, _):
            let workingHours = context.preferredWorkingHours.map { "Preferred working hours: \($0.start):00 - \($0.end):00" } ?? "No preferred working hours specified"

            return """
            \(contextSection)
            \(workingHours)

            Generate calendar events for this goal:
            Title: "\(goal.title)"
            Description: \(goal.content)
            Priority: \(goal.priority.rawValue)
            Progress: \(Int(goal.progress * 100))%

            Return as JSON:
            {
                "events": [
                    {
                        "title": "Focused work session title",
                        "duration": 90,
                        "suggestedTimeSlot": "morning|afternoon|evening",
                        "recurring": false,
                        "description": "What will be accomplished in this session",
                        "preparation": ["things to prepare beforehand"]
                    }
                ],
                "schedulingTips": ["tip1", "tip2"]
            }
            """

        case .summarizeProgress(let goal, _):
            return """
            \(contextSection)

            Summarize progress for this goal:
            Title: "\(goal.title)"
            Description: \(goal.content)
            Progress: \(Int(goal.progress * 100))%
            Priority: \(goal.priority.rawValue)
            Created: \(goal.createdAt.formatted(date: .abbreviated, time: .omitted))

            Create a brief, encouraging progress summary. Focus on achievements and next steps.
            Keep it motivational but honest about remaining work.
            """

        case .reorderCards(let goals, let instruction, _):
            let goalsList = goals.enumerated().map { index, goal in
                "\(index + 1). \(goal.title) (Priority: \(goal.priority.rawValue), Progress: \(Int(goal.progress * 100))%)"
            }.joined(separator: "\n")

            return """
            \(contextSection)

            Reorder these goals based on: "\(instruction)"

            Current goals:
            \(goalsList)

            Return as JSON:
            {
                "reorderedGoals": ["goal_id_1", "goal_id_2", "goal_id_3"],
                "reasoning": "Explanation of the reordering logic",
                "recommendations": ["specific suggestions for the user"]
            }
            """

        case .generateMirrorCard(let goal, _):
            return """
            \(contextSection)

            Analyze this user's goal from an AI perspective:
            Title: "\(goal.title)"
            Description: \(goal.content)
            Priority: \(goal.priority.rawValue)
            Progress: \(Int(goal.progress * 100))%
            Time since creation: \(Int(Date().timeIntervalSince(goal.createdAt) / 86400)) days

            Return as JSON:
            {
                "aiInterpretation": "What I understand the user really wants to achieve",
                "suggestedActions": [
                    "Specific action 1",
                    "Specific action 2",
                    "Specific action 3"
                ],
                "confidence": 0.85,
                "insights": [
                    "Pattern or observation about this goal",
                    "Potential challenge or opportunity"
                ],
                "emotionalTone": "motivated|overwhelmed|focused|uncertain"
            }
            """
        }
    }

    private func extractContext(from function: AIFunction) -> AIContext {
        switch function {
        case .createGoal(_, let context),
             .breakdownGoal(_, let context),
             .chatWithGoal(_, _, let context),
             .generateCalendarEvents(_, let context),
             .summarizeProgress(_, let context),
             .reorderCards(_, _, let context),
             .generateMirrorCard(_, let context):
            return context
        }
    }

    private func buildContextSection(_ context: AIContext) -> String {
        var sections: [String] = []

        if !context.recentGoals.isEmpty {
            let recentGoalsList = context.recentGoals.prefix(5).map { goal in
                "- \(goal.title) (\(goal.priority.rawValue), \(Int(goal.progress * 100))% complete)"
            }.joined(separator: "\n")
            sections.append("Recent goals context:\n\(recentGoalsList)")
        }

        if context.completedGoalsCount > 0 {
            sections.append("User has completed \(context.completedGoalsCount) goals so far.")
        }

        if let avgTime = context.averageCompletionTime {
            let days = Int(avgTime / 86400)
            sections.append("Average goal completion time: \(days) days.")
        }

        if let workingHours = context.preferredWorkingHours {
            sections.append("User prefers working between \(workingHours.start):00 and \(workingHours.end):00.")
        }

        sections.append("Current time: \(context.currentTime.formatted(date: .abbreviated, time: .shortened))")

        return sections.isEmpty ? "" : "USER CONTEXT:\n" + sections.joined(separator: "\n") + "\n"
    }

    private var structuredSystemPrompt: String {
        """
        You are an AI assistant for YOU AND GOALS, a conversational goal management app.

        Core capabilities:
        1. Create and decompose goals into actionable steps
        2. Generate intelligent calendar events without overwhelming the user
        3. Analyze patterns and suggest improvements
        4. Provide structured data for the app interface

        CRITICAL REQUIREMENTS:
        - ALWAYS respond with valid JSON only
        - NO additional text outside the JSON structure
        - Use the exact field names specified in prompts
        - Ensure all JSON is properly formatted and parseable
        - Consider the user's context and patterns when making suggestions
        - Keep suggestions practical and achievable
        - Respect user's working hours and preferences

        Remember: This is a calendar-mindset app without calendar UI. Focus on time-aware, context-sensitive recommendations.
        """
    }

    private var conversationalSystemPrompt: String {
        """
        You are an AI assistant for YOU AND GOALS, a conversational goal management app.

        Core capabilities:
        1. Provide coaching and motivation for specific goals
        2. Give actionable advice based on goal context
        3. Maintain encouraging but honest communication
        4. Reference user's progress and history when relevant

        Communication style:
        - Be conversational and personable
        - Keep responses concise but helpful (2-4 sentences)
        - Reference the specific goal and its context
        - Acknowledge progress and challenges
        - Provide specific next steps when possible
        - Be encouraging but realistic about obstacles

        Remember: You are this goal's dedicated assistant, not a general chatbot.
        """
    }
}

// MARK: - Error Handling
enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case rateLimited
    case networkError
    case jsonParsingFailed
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "AI service not configured. Please check API key."
        case .invalidResponse: return "Unable to process AI response. Please try again."
        case .rateLimited: return "Too many requests. Please wait a moment."
        case .networkError: return "Network error. Check your internet connection."
        case .jsonParsingFailed: return "Failed to parse AI response format."
        case .invalidFormat: return "AI response format is invalid."
        }
    }
}

// MARK: - Response Models
struct OpenAIResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}

struct GoalCreationResponse: Codable {
    let title: String
    let content: String
    let category: String
    let priority: String
    let suggestedSubgoals: [String]
    let estimatedDuration: String?
    let difficulty: String?
}

struct GoalBreakdownResponse: Codable {
    let subtasks: [Subtask]
    let recommendedOrder: [String]
    let totalEstimatedHours: Int

    struct Subtask: Codable {
        let title: String
        let description: String
        let estimatedHours: Int
        let dependencies: [String]?
        let difficulty: String?
    }
}

struct CalendarEventsResponse: Codable {
    let events: [CalendarEvent]
    let schedulingTips: [String]?

    struct CalendarEvent: Codable {
        let title: String
        let duration: Int
        let suggestedTimeSlot: String
        let recurring: Bool
        let description: String?
        let preparation: [String]?
    }
}

struct GoalReorderResponse: Codable {
    let reorderedGoals: [String]
    let reasoning: String
    let recommendations: [String]?
}

struct MirrorCardResponse: Codable {
    let aiInterpretation: String
    let suggestedActions: [String]
    let confidence: Double
    let insights: [String]?
    let emotionalTone: String?
}