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

struct ChatSubgoalSnapshot: Codable {
    let id: String
    let title: String
    let progress: Double
    let isComplete: Bool
    let isAtomic: Bool
    let blockedBy: [String]
    let unblocks: [String]
    let children: [ChatSubgoalSnapshot]

    var hasChildren: Bool { !children.isEmpty }
}

struct ChatGoalRelationSnapshot: Codable {
    let id: String
    let title: String
    let activationState: String
    let progress: Double
    let priority: String
    let relation: String
}

struct ChatGoalSnapshot: Codable {
    let id: String
    let title: String
    let content: String
    let activationState: String
    let isLocked: Bool
    let progress: Double
    let priority: String
    let category: String
    let subgoals: [ChatSubgoalSnapshot]
    let availableActions: [String]
    let eventCount: Int
    let revisionCount: Int
    let hasParent: Bool
    let parent: ChatGoalRelationSnapshot?
    let siblings: [ChatGoalRelationSnapshot]
    let uncles: [ChatGoalRelationSnapshot]
    let totalSubgoalCount: Int
    let atomicSubgoalCount: Int
    let maxSubgoalDepth: Int
}

struct AIContext {
    let recentGoals: [Goal]
    let userPatterns: [String: Any]
    let currentTime: Date
    let preferredWorkingHours: (start: Int, end: Int)?
    let completedGoalsCount: Int
    let averageCompletionTime: TimeInterval?
    var goalSnapshots: [ChatGoalSnapshot]

    // Memory system additions
    var userFacts: [String] = []  // Persistent facts about user
    var userPreferences: [String: String] = [:]  // User preferences
    var conversationSummaries: [String] = []  // Recent conversation summaries
    var crossScopeContext: String = ""  // Context from other scopes

    init(goals: [Goal] = [], patterns: [String: Any] = [:], preferredHours: (Int, Int)? = nil, existingEvents: [String] = []) {
        self.recentGoals = Array(goals.prefix(10))
        self.userPatterns = patterns
        self.currentTime = Date()
        self.preferredWorkingHours = preferredHours
        self.completedGoalsCount = goals.filter { $0.progress >= 1.0 }.count
        self.averageCompletionTime = AIContext.calculateAverageCompletionTime(goals: goals)
        self.goalSnapshots = [] // Will be populated by UserContextService
        // Calendar removed - existingEvents parameter kept for compatibility but ignored
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

    let baseURL = "https://api.openai.com/v1/chat/completions"
    let requestTimeout: TimeInterval = 30.0
    private var requestCache: [String: CachedResponse] = [:]
    private let cacheTimeout: TimeInterval = 1800 // Increased from 300s (5min) to 1800s (30min)
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
        case generalChat(message: String, history: [GeneralChatMessage], context: AIContext)
        case summarizeProgress(goal: Goal, context: AIContext)
        case reorderCards(goals: [Goal], instruction: String, context: AIContext)
        case generateMirrorCard(goal: Goal, context: AIContext)
        case generateTimelineInsights(goal: Goal, entries: [GoalTimelineEntry], horizon: DateInterval, context: AIContext)
        case suggestEmoji(goal: Goal, context: AIContext)
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

    var currentAPIKey: String {
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

    func processWithActions(_ function: AIFunction) async throws -> ChatResponse {
        let cacheKey = generateCacheKey(for: function) + "_actions"

        if let cachedResponse = getCachedResponse(for: cacheKey) {
            return try parseJSONResponse(cachedResponse, as: ChatResponse.self)
        }

        let response = try await makeAPIRequestWithActions(for: function)
        cacheResponse(response, for: cacheKey)

        return try parseJSONResponse(response, as: ChatResponse.self)
    }

    private func makeAPIRequestWithActions(for function: AIFunction) async throws -> String {
        let apiKey = currentAPIKey

        guard !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        return try await retryWithExponentialBackoff(maxRetries: 3) {
            try await performSingleAPIRequestWithActions(for: function, apiKey: apiKey)
        }
    }

    /// OPTIMIZATION: Determine if we should use GPT-4 (expensive) or GPT-3.5-turbo (fast & cheap)
    private func shouldUseGPT4(for function: AIFunction) -> Bool {
        switch function {
        case .breakdownGoal, .generateTimelineInsights:
            // Only complex reasoning needs GPT-4
            return true
        default:
            // Everything else works fine with GPT-3.5-turbo (10x cheaper, 3x faster)
            return false
        }
    }

    private func performSingleAPIRequestWithActions(for function: AIFunction, apiKey: String) async throws -> String {
        let prompt = buildContextualPrompt(for: function)
        // Use action-aware system prompt for chat functions
        let systemPrompt = actionAwareSystemPrompt
        let temperature = 0.4 // Lower temperature for more consistent action generation
        let maxTokens = 1500

        var request = URLRequest(url: URL(string: baseURL)!, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // OPTIMIZATION: Use GPT-3.5-turbo for action-aware operations (faster, cheaper)
        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
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

        // OPTIMIZATION: Use GPT-3.5-turbo for most operations (10x cheaper, 3x faster)
        let model = shouldUseGPT4(for: function) ? "gpt-4" : "gpt-3.5-turbo"

        let body: [String: Any] = [
            "model": model,
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

    func retryWithExponentialBackoff<T>(maxRetries: Int, operation: () async throws -> T) async throws -> T {
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

    func parseJSONResponse<T: Codable>(_ response: String, as type: T.Type) throws -> T {
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

    internal func cleanJSONResponse(_ response: String) -> String {
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
        case .generalChat(let message, let history, _):
            let signature = history.suffix(8).reduce(into: 0) { partialResult, entry in
                partialResult ^= entry.content.hashValue
                partialResult ^= entry.timestamp.hashValue
            }
            return "general_chat_\(message.hashValue)_\(signature)"
        case .summarizeProgress(let goal, _):
            return "summary_\(goal.id.uuidString)_\(Int(goal.progress * 100))"
        case .reorderCards(let goals, let instruction, _):
            return "reorder_\(goals.map { $0.id.uuidString }.joined())_\(instruction.hashValue)"
        case .generateMirrorCard(let goal, _):
            return "mirror_\(goal.id.uuidString)"
        case .generateTimelineInsights(let goal, let entries, let horizon, _):
            let entrySignature = entries
                .map { entry in
                    "\(entry.id.uuidString):\(Int(entry.startDate.timeIntervalSince1970)):\(Int(entry.endDate.timeIntervalSince1970))"
                }
                .joined(separator: "|")
            let signatureHash = String(entrySignature.hashValue)
            let startKey = Int(horizon.start.timeIntervalSince1970)
            let endKey = Int(horizon.end.timeIntervalSince1970)
            return "timeline_ai_\(goal.id.uuidString)_\(startKey)_\(endKey)_\(signatureHash)"
        case .suggestEmoji(let goal, _):
            let timestamp = Int(goal.updatedAt.timeIntervalSince1970)
            return "emoji_\(goal.id.uuidString)_\(timestamp)"
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
        case .createGoal, .breakdownGoal, .reorderCards, .generateMirrorCard, .suggestEmoji:
            return (structuredSystemPrompt, 0.3, 800) // Reduced from 1000
        case .generateTimelineInsights:
            return (structuredSystemPrompt, 0.35, 1200) // Reduced from 1400
        case .generalChat:
            return (actionAwareSystemPrompt, 0.4, 1200) // Reduced from 1500
        case .chatWithGoal, .summarizeProgress:
            return (conversationalSystemPrompt, 0.7, 600) // Reduced from 800
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
                "kind": "event|campaign|hybrid",
                "targetMetric": {
                    "label": "Primary measurable outcome",
                    "targetValue": 5.0,
                    "unit": "kg|%|pages|sessions",
                    "baselineValue": 0.0,
                    "measurementWindowDays": 14,
                    "lowerBound": 2.0,
                    "upperBound": 6.0,
                    "notes": "Constraints or context"
                },
                "phases": [
                    {
                        "title": "Phase name",
                        "summary": "What this phase covers",
                        "order": 1
                    }
                ],
                "roadmapSlices": [
                    {
                        "title": "Concrete milestone",
                        "detail": "What will be delivered",
                        "startOffsetDays": 0,
                        "endOffsetDays": 7,
                        "expectedMetricDelta": 1.5,
                        "metricUnit": "kg",
                        "confidence": 0.75
                    }
                ],
                "suggestedSubgoals": ["subgoal1", "subgoal2"],
                "estimatedDuration": "time estimate in hours",
                "difficulty": "easy|medium|hard"
            }

            Rules:
            - Choose "event" when the goal is a single happening with a specific target date.
            - Choose "campaign" when the user seeks a transformation tracked by measurable change over time.
            - Use "hybrid" sparingly when both a fixed deadline and ongoing metrics are mandatory.
            - Omit targetMetric if no honest measurement exists; never fabricate impossible numbers.
            - Roadmap slices should map the next ~14 days, each with a tangible, verifiable outcome.
            - Always ensure confidence values are between 0 and 1 and match the realism of the milestone.
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
                        "id": "unique-slug",
                        "title": "Phase or atomic task",
                        "description": "What will be accomplished",
                        "estimatedHours": 2.5,
                        "difficulty": "easy|medium|hard",
                        "dependencies": ["id-of-prerequisite"],
                        "isAtomic": false,
                        "children": [
                            {
                                "id": "child-slug",
                                "title": "Atomic task",
                                "description": "Precise instruction",
                                "estimatedHours": 1,
                                "difficulty": "easy",
                                "dependencies": [],
                                "isAtomic": true,
                                "children": []
                            }
                        ]
                    }
                ],
                "recommendedOrder": ["id-1", "id-2"],
                "totalEstimatedHours": 10.5
            }

            Rules:
            - Keep decomposing each subtask until it is truly atomic (isAtomic = true and children = []).
            - Any node that is not atomic must include 2-7 children that break the work into the next actionable layer. Never return a mid-sized task without children.
            - Set "isAtomic": false for every node that still has children so the client can keep asking you to go deeper if needed.
            - Use kebab-case slugs for every id and ensure they are unique across the tree.
            - Always include the children array (use an empty array for atomic tasks) and the dependencies array (empty array if none).
            - Dependencies must reference ids that exist in this response and should primarily link atomic tasks to the precise prerequisites they rely on.
            - recommendedOrder should list top-level ids in the sequence they should be tackled, respecting dependencies.
            - totalEstimatedHours must reflect the sum of every atomic task's estimate.
            """

        case .chatWithGoal(let message, let goal, _):
            // Note: Chat history is now handled via ChatEntry in the unified system
            // This legacy method is being replaced by chatWithScope
            let goalStructure = buildGoalStructureSection(context, goalId: goal.id)

            return """
            \(contextSection)

            You are the dedicated AI assistant for this specific goal:
            Goal: "\(goal.title)"
            Description: \(goal.content)
            Progress: \(Int(goal.progress * 100))%
            Priority: \(goal.priority.rawValue)

            \(goalStructure)

            User's current message: "\(message)"

            Note: This method is being phased out in favor of scope-based chat with unified history.

            Respond conversationally as this goal's personal coach. Be specific, actionable, and encouraging.
            Reference the goal's context and previous conversation when relevant.
            """
        case .generalChat(let message, let history, _):
            var transcriptHistory = history
            if let last = transcriptHistory.last, last.isUser, last.content == message {
                transcriptHistory.removeLast()
            }

            let transcriptSection = buildGeneralTranscriptSection(transcriptHistory)
            let portfolioSection = buildGoalPortfolioSection(context)

            return """
            \(contextSection)

            GENERAL GOAL PORTFOLIO SNAPSHOT:
            \(portfolioSection)

            RECENT CONVERSATION:
            \(transcriptSection)

            User's current message: "\(message)"

            Act as the conductor for the user's entire goal board. Reference ongoing commitments, highlight dependencies, and propose coordinated actions when it helps. Mark requiresConfirmation as true for destructive or bulk operations such as delete_goal, bulk_delete, bulk_archive, merge_goals, or anything irreversible. If no action is needed, return an empty actions array but still provide a helpful reply rooted in the conversation history.
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

        case .generateTimelineInsights(let goal, let entries, let horizon, let context):
            let contextBlock = contextSection.isEmpty ? "" : contextSection + "\n"
            let goalStructure = buildGoalStructureSection(context, goalId: goal.id)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let sanitizedDescription = goal.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No description provided."
                : goal.content

            let entryDescriptions = entries.map { entry -> String in
                let start = isoFormatter.string(from: entry.startDate)
                let end = isoFormatter.string(from: entry.endDate)
                let detail = entry.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
                let baselineDetail = (detail?.isEmpty ?? true) ? "No detail provided" : (detail ?? "No detail provided")
                let metric = entry.metricSummary ?? "None"
                let confidence = entry.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"

                return "- id: \(entry.id.uuidString)\n  kind: \(entry.kind.rawValue)\n  title: \(entry.title)\n  start: \(start)\n  end: \(end)\n  baselineDetail: \(baselineDetail)\n  metric: \(metric)\n  confidence: \(confidence)"
            }.joined(separator: "\n\n")

            var request = """
            \(contextBlock)TIMELINE INSIGHT REQUEST

            Goal: "\(goal.title)"
            Kind: \(goal.kind.rawValue)
            Priority: \(goal.priority.rawValue)
            Progress: \(Int(goal.progress * 100))%
            Description: \(sanitizedDescription)
            """

            if !goalStructure.isEmpty {
                request.append("\n\(goalStructure)\n")
            }

            request.append(
                """
            Horizon:
            - start: \(isoFormatter.string(from: horizon.start))
            - end: \(isoFormatter.string(from: horizon.end))

            Baseline entries:
            \(entryDescriptions)

            Task:
            - For each entry, infer what tangible outcome the user could realistically achieve within that window.
            - Reference subgoals, projections, and the goal's intent to stay specific.
            - Translate vague labels into concrete deliverables (e.g., \"Research session\" -> \"Capture 5 journal sources\").
            - Identify which subtasks could be completed or advanced.
            - Flag if the window could realistically complete the entire goal.

            Respond in JSON using this schema:
            {
                "insights": [
                    {
                        "entryId": "UUID from baseline entries",
                        "outcomeSummary": "Concise outcome (≤140 chars)",
                        "subtaskHighlights": ["Optional list of subtasks or wins"],
                        "recommendedAction": "Optional concrete next action",
                        "completionLikelihood": 0.0-1.0,
                        "readyToMarkGoalComplete": true|false
                    }
                ],
                "portfolioHeadline": "Optional one-line observation across the horizon"
            }

            Rules:
            - Maintain JSON validity (no comments).
            - Use only entryIds provided above.
            - Keep outcomeSummary motivational but grounded in the window length.
            - Limit subtaskHighlights to at most 4 short bullets.
            - Set recommendedAction to null when nothing new to add.
            - Only set readyToMarkGoalComplete true if the window can reasonably finish the overall goal.
            - If data is insufficient, still return an insight with honest guidance.
            """
            )

            return request

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
        case .suggestEmoji(let goal, _):
            let description = goal.content.trimmed.isEmpty ? "No description provided." : goal.content.trimmed
            return """
            \(contextSection)

            Choose a single emoji that captures the personality, energy, or vibe of this goal.

            Goal title: "\(goal.title)"
            Description: \(description)
            Category: \(goal.category)
            Priority: \(goal.priority.rawValue)
            Activation state: \(goal.activationState.rawValue)

            Respond with JSON using this shape:
            {
                "emoji": "🧠",
                "reason": "One short sentence explaining the choice"
            }

            Rules:
            - Use exactly one emoji character in the emoji field.
            - Avoid the generic lightning bolt. Prefer something that feels tailored to the goal.
            - Pick an emoji that would motivate the user when they glance at the card.
            - If nothing else fits, choose a neutral motivation emoji such as 🎯 or 🚀.
            """
        }
    }

    private func extractContext(from function: AIFunction) -> AIContext {
        switch function {
        case .createGoal(_, let context),
             .breakdownGoal(_, let context),
             .chatWithGoal(_, _, let context),
             .generalChat(_, _, let context),
             .summarizeProgress(_, let context),
             .reorderCards(_, _, let context),
             .generateMirrorCard(_, let context),
             .generateTimelineInsights(_, _, _, let context),
             .suggestEmoji(_, let context):
            return context
        }
    }

    internal func buildContextSection(_ context: AIContext) -> String {
        var sections: [String] = []

        // Memory: User facts
        if !context.userFacts.isEmpty {
            sections.append("WHAT I KNOW ABOUT YOU:\n" + context.userFacts.map { "• \($0)" }.joined(separator: "\n"))
        }

        // Memory: User preferences
        if !context.userPreferences.isEmpty {
            let prefs = context.userPreferences.map { key, value in "• \(key): \(value)" }.joined(separator: "\n")
            sections.append("YOUR PREFERENCES:\n\(prefs)")
        }

        // Memory: Conversation summaries
        if !context.conversationSummaries.isEmpty {
            sections.append("PREVIOUS CONVERSATIONS:\n" + context.conversationSummaries.map { "• \($0)" }.joined(separator: "\n"))
        }

        // Memory: Cross-scope context
        if !context.crossScopeContext.isEmpty {
            sections.append(context.crossScopeContext)
        }

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

    private func buildGoalStructureSection(_ context: AIContext, goalId: UUID) -> String {
        guard let snapshot = context.goalSnapshots.first(where: { $0.id == goalId.uuidString }) else {
            return ""
        }

        var section = """
        GOAL STRUCTURE:
        - Status: \(snapshot.activationState)
        - Locked: \(snapshot.isLocked ? "Yes (cannot modify)" : "No")
        - Progress: \(Int(snapshot.progress * 100))%
        - Category: \(snapshot.category)
        """

        if let parent = snapshot.parent {
            section += "\n- Parent: \(parent.title) [status: \(parent.activationState), progress: \(Int(parent.progress * 100))%, priority: \(parent.priority)]"
        }

        if !snapshot.siblings.isEmpty {
            let siblingList = snapshot.siblings.prefix(4).map { sibling in
                "• \(sibling.title) (\(Int(sibling.progress * 100))%, \(sibling.priority))"
            }.joined(separator: "\n  ")
            section += "\n- Sibling subtasks: \n  \(siblingList)"
            if snapshot.siblings.count > 4 {
                section += "\n  ...and \(snapshot.siblings.count - 4) more"
            }
        }

        if !snapshot.uncles.isEmpty {
            let uncleList = snapshot.uncles.prefix(3).map { uncle in
                "• \(uncle.title) (\(Int(uncle.progress * 100))%, \(uncle.priority))"
            }.joined(separator: "\n  ")
            section += "\n- Related parent-level cards: \n  \(uncleList)"
            if snapshot.uncles.count > 3 {
                section += "\n  ...and \(snapshot.uncles.count - 3) more"
            }
        }

        // Add subgoals if present
        if snapshot.totalSubgoalCount > 0 {
            section += "\n- Subtasks: \(snapshot.totalSubgoalCount) total (\(snapshot.atomicSubgoalCount) atomic, depth \(snapshot.maxSubgoalDepth))"
            let (treeDescription, displayedCount) = renderSubtaskTreeDescription(for: snapshot, limit: 18)
            if !treeDescription.isEmpty {
                section += "\n" + treeDescription
            }

            let remaining = snapshot.totalSubgoalCount - displayedCount
            if remaining > 0 {
                section += "\n  ... +\(remaining) more nodes"
            }
        } else {
            section += "\n- No subtasks yet"
        }

        // Add available actions
        section += "\n\nAVAILABLE ACTIONS for this goal:"
        section += "\n" + snapshot.availableActions.prefix(12).joined(separator: ", ")
        if snapshot.availableActions.count > 12 {
            section += ", +\(snapshot.availableActions.count - 12) more"
        }

        return section
    }

    func renderSubtaskTreeDescription(for snapshot: ChatGoalSnapshot, limit: Int = 18) -> (description: String, displayed: Int) {
        guard snapshot.totalSubgoalCount > 0 else { return ("", 0) }

        var lines: [String] = []
        var displayed = 0

        func walk(_ nodes: [ChatSubgoalSnapshot], depth: Int) {
            guard displayed < limit else { return }

            for node in nodes {
                guard displayed < limit else { return }

                let indent = String(repeating: "  ", count: depth)
                var line = "\(indent)\(node.isComplete ? "✓" : "○") \(node.title) (\(Int(node.progress * 100))%) [ID: \(node.id)]"

                if !node.blockedBy.isEmpty {
                    let blockers = node.blockedBy.prefix(3).joined(separator: ", ")
                    line += " • waits for \(blockers)"
                }

                if !node.unblocks.isEmpty {
                    let dependents = node.unblocks.prefix(3).joined(separator: ", ")
                    line += " • unlocks \(dependents)"
                }

                lines.append("  " + line)
                displayed += 1

                if displayed < limit && node.hasChildren {
                    walk(node.children, depth: depth + 1)
                }
            }
        }

        walk(snapshot.subgoals, depth: 0)

        return (lines.joined(separator: "\n"), displayed)
    }

    private func buildGeneralTranscriptSection(_ history: [GeneralChatMessage]) -> String {
        guard !history.isEmpty else {
            return "No previous conversation yet."
        }

        let recentMessages = history.suffix(12)
        return recentMessages.map { message in
            let role = message.isUser ? "User" : "AI"
            let timestamp = message.timestamp.formatted(date: .omitted, time: .shortened)
            return "\(timestamp) \(role): \(message.content)"
        }.joined(separator: "\n")
    }

    func buildGoalPortfolioSection(_ context: AIContext) -> String {
        guard !context.goalSnapshots.isEmpty else {
            return "No goals yet. Invite the user to create one."
        }

        let totalGoals = context.goalSnapshots.count
        let activeCount = context.goalSnapshots.filter { $0.activationState == Goal.ActivationState.active.rawValue }.count
        let draftCount = context.goalSnapshots.filter { $0.activationState == Goal.ActivationState.draft.rawValue }.count
        let completedCount = context.goalSnapshots.filter { $0.activationState == Goal.ActivationState.completed.rawValue }.count
        let archivedCount = context.goalSnapshots.filter { $0.activationState == Goal.ActivationState.archived.rawValue }.count

        var section = "Total: \(totalGoals) • Active: \(activeCount) • Draft: \(draftCount) • Completed: \(completedCount) • Archived: \(archivedCount)\n\nIMPORTANT: When creating actions, use the exact Goal ID shown below for each goal.\n"

        let highlightedGoals = context.goalSnapshots.prefix(12).map { snapshot -> String in
            let lockStatus = snapshot.isLocked ? "locked" : "flexible"
            let progress = Int(snapshot.progress * 100)
            return "- ID: \(snapshot.id) | \(snapshot.title) [priority: \(snapshot.priority), status: \(snapshot.activationState), \(lockStatus), progress: \(progress)%]"
        }

        section += highlightedGoals.joined(separator: "\n")

        if context.goalSnapshots.count > 12 {
            section += "\n...and \(context.goalSnapshots.count - 12) more goals."
        }

        return section
    }

    func suggestEmoji(for goal: Goal, context: AIContext) async throws -> GoalEmojiResponse {
        try await processRequest(.suggestEmoji(goal: goal, context: context), responseType: GoalEmojiResponse.self)
    }

    private var structuredSystemPrompt: String {
        """
        You are an AI assistant for YOU AND GOALS, a conversational goal management app.

        Core capabilities:
        1. Create and decompose goals into actionable steps
        2. Manage goal activation and lifecycle states
        3. Analyze patterns and suggest improvements
        4. Provide structured data for the app interface

        CRITICAL REQUIREMENTS:
        - ALWAYS respond with valid JSON only
        - NO additional text outside the JSON structure
        - Use the exact field names specified in prompts
        - Ensure all JSON is properly formatted and parseable
        - Consider the user's context and patterns when making suggestions
        - Keep suggestions practical and achievable
        - Focus on clear goal structure and actionable sequential steps

        Remember: Help users break down goals into manageable steps they can complete one at a time.
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

    var actionAwareSystemPrompt: String {
        """
        You are the AI assistant for YOU AND GOALS. You can execute actions to help users manage their goals.

        RESPONSE FORMAT:
        ALWAYS return JSON with this exact structure:
        {
            "reply": "Your conversational response to the user",
            "actions": [
                {
                    "type": "action_type",
                    "goalId": "uuid-string",
                    "parameters": { "key": "value" }
                }
            ],
            "requiresConfirmation": false
        }

        AVAILABLE ACTIONS - GENERAL CHAT IS THE COMMAND CENTER:

        1. GOAL CREATION (general chat specialty):
           - create_goal: Create new goal instantly
             Parameters: {title: "goal title", content?: "details", priority?: "now|next|later", category?: "Work|Health|Personal|Finance|Learning|..."}
             Philosophy: BE DECISIVE. Infer reasonable defaults from context. Don't ask clarifying questions.
             Examples:
               • "create work goal for Q1 report" → priority="next", category="Work"
               • "add fitness goal" → priority="next", category="Health"
               • "create goal to learn Swift" → priority="next", category="Learning"

        2. SINGLE-GOAL OPERATIONS (works in both general AND goal chat):
           LIFECYCLE:
           - activate_goal: Activate goal (changes state to active, no params)
           - deactivate_goal: Deactivate goal (changes state to draft, no params)
           - delete_goal: Permanently delete (no params, requires confirmation)
           - complete_goal: Mark as 100% done (no params)
           - lock_goal: Prevent modifications (no params)
           - unlock_goal: Allow modifications (no params)
           - regenerate_goal: AI rewrites goal content (no params)

           MODIFICATIONS:
           - edit_title: {title: "new title"}
           - edit_content: {content: "new description"}
           - edit_category: {category: "Work"}
           - set_progress: {progress: 0.75}  // 0.0 to 1.0
           - change_priority: {priority: "now"|"next"|"later"}
           - mark_incomplete: Set progress back to 0 (no params)
           - reactivate: Reactivate archived/completed goal (no params)

        3. SUBTASK MICROMANAGEMENT (YES, from general chat too!):
           - breakdown: AI creates subtasks (no params)
           - create_subgoal: {title: "name", content?: "details"}
           - update_subgoal: {subgoalId: "uuid", title?: "new", progress?: 0.5}
           - complete_subgoal: {subgoalId: "uuid"}
           - delete_subgoal: {subgoalId: "uuid"}

           CRITICAL: Subtasks shown with [ID: uuid] in the subtask tree - use exact UUID
           Example: "○ Research phase (30%) [ID: 123e4567-e89b-12d3-a456-426614174000]"
           → Use "123e4567-e89b-12d3-a456-426614174000" as subgoalId
           → User can say "delete research subtask from Swift goal" - you handle it from general chat!

        4. BULK OPERATIONS (general chat specialty):
           - bulk_delete: {goalIds: ["id1", "id2", ...]} (requires confirmation)
           - bulk_archive: {goalIds: ["id1", "id2", ...]}
           - bulk_complete: {goalIds: ["id1", "id2", ...]}
           - reorder_goals: {orderedIds: ["id1", "id2", ...]} (not yet implemented)
           - merge_goals: {goalIds: ["id1", "id2"]} (requires confirmation, not yet implemented)

        5. QUERY/INSIGHTS (no actions, conversational only):
           - view_subgoals: Show subtasks (return in reply)
           - view_history: Show revisions (return in reply)
           - summarize: Provide summary (return in reply)
           - chat: Just conversation
           - Portfolio analysis: "what's overdue?", "show health goals", "what should I focus on?"

        CRITICAL RULES FOR ACTIONS:
        1. Check goal's availableActions list BEFORE suggesting any action
        2. NEVER suggest unavailable actions (e.g., don't unlock unlocked goals)
        3. For locked goals, ONLY unlock, view, or chat actions are available
        4. Set requiresConfirmation: true for delete, merge, bulk operations
        5. For read-only queries (view_subgoals, view_history), return info in reply with actions: []
        6. **GOALID IS CRITICAL**:
           - For GOAL-SPECIFIC chat: Use the exact Goal ID shown in "GOAL DETAILS" above
           - For GENERAL chat: Use the exact ID from the goal portfolio list
           - For subgoal operations: Use parent goal ID in goalId, child ID in parameters.subgoalId
           - For bulk operations: goalId should be null/omitted, use goalIds array in parameters
           - For create_goal: No goalId needed (it doesn't exist yet!)
        7. Be conversational in reply, technical in actions
        8. If user just wants to chat, return empty actions array
        9. Multiple actions can be executed in sequence - add them all to the actions array
        10. Always check the GOAL STRUCTURE section to understand current state

        COMMAND CENTER PHILOSOPHY - WHEN TO USE GENERAL VS GOAL CHAT:

        GENERAL CHAT (You are here - be the Command Center!):
        ✅ CREATE new goals instantly (don't ask questions, infer defaults)
        ✅ Quick actions on ANY goal ("activate fitness goals", "complete task X")
        ✅ Bulk operations ("archive all completed", "delete draft goals")
        ✅ Portfolio queries ("what's overdue?", "what should I focus on?")
        ✅ Micromanage any goal's subtasks IF user specifies which goal
        ✅ Cross-goal insights and recommendations
        BE DECISIVE: User comes here for SPEED. Infer context, make assumptions, take action.
        Example: "create work goal" → Just do it with priority="next", category="Work"

        GOAL-SPECIFIC CHAT (User opened a goal card):
        ✅ Extended conversation about ONE specific goal
        ✅ Iterative subtask refinement and planning
        ✅ Detailed breakdown and restructuring
        ✅ Deep focus work on that goal's details

        KEY INSIGHT: User doesn't need to switch contexts! General chat can do everything if they specify the goal.
        Example: "delete research subtask from my Swift goal" → Handle it right here in general chat!

        EXAMPLES:

        User: "delete this goal"
        Response (for goal-specific chat, use the exact Goal ID from GOAL DETAILS):
        {
            "reply": "I'll delete this goal for you.",
            "actions": [{
                "type": "delete_goal",
                "goalId": "actual-uuid-from-goal-details"
            }],
            "requiresConfirmation": true
        }

        User: "set progress to 75%"
        Response (IMPORTANT: Use exact UUID from context):
        {
            "reply": "Setting progress to 75%.",
            "actions": [{
                "type": "set_progress",
                "goalId": "actual-uuid-from-goal-details",
                "parameters": {"progress": 0.75}
            }],
            "requiresConfirmation": false
        }

        User: "show me the subtasks"
        Response:
        {
            "reply": "Here are the subtasks:\\n1. ○ First task (20%)\\n2. ✓ Second task (100%)\\n3. ○ Third task (0%)",
            "actions": [],
            "requiresConfirmation": false
        }

        User: "break this down and activate it"
        Response (CRITICAL: goalId must be the exact UUID from GOAL DETAILS):
        {
            "reply": "I'll break this down into subtasks and activate it for scheduling.",
            "actions": [
                {"type": "breakdown", "goalId": "actual-uuid-from-goal-details"},
                {"type": "activate_goal", "goalId": "actual-uuid-from-goal-details"}
            ],
            "requiresConfirmation": false
        }

        User: "what should I work on?"
        Response:
        {
            "reply": "Based on your progress, I'd recommend focusing on [specific subtask]. You're making good progress!",
            "actions": [],
            "requiresConfirmation": false
        }

        User: "delete the research phase subtask"
        Response (use exact ID from subtask tree):
        {
            "reply": "I'll delete the research phase subtask.",
            "actions": [{
                "type": "delete_subgoal",
                "goalId": "parent-goal-uuid",
                "parameters": {"subgoalId": "123e4567-e89b-12d3-a456-426614174000"}
            }],
            "requiresConfirmation": false
        }

        COMMAND CENTER EXAMPLES (General Chat - showcase full power!):

        User: "create a goal to finish my tax return"
        Response (BE DECISIVE - infer category and priority):
        {
            "reply": "Created 'Finish Tax Return' with Next priority under Finance. Would you like me to break it down into steps?",
            "actions": [{
                "type": "create_goal",
                "parameters": {"title": "Finish Tax Return", "priority": "next", "category": "Finance"}
            }],
            "requiresConfirmation": false
        }

        User: "delete the research subtask from my Swift learning goal"
        Response (micromanage from general chat - use IDs from portfolio):
        {
            "reply": "I'll delete the Research subtask from 'Learn Swift'.",
            "actions": [{
                "type": "delete_subgoal",
                "goalId": "swift-goal-uuid-from-portfolio",
                "parameters": {"subgoalId": "research-subtask-uuid-from-tree"}
            }],
            "requiresConfirmation": false
        }

        User: "activate all my health goals"
        Response (bulk operation on filtered goals):
        {
            "reply": "Activating 3 health goals: Morning Run, Yoga Practice, and Meal Prep.",
            "actions": [
                {"type": "activate_goal", "goalId": "run-uuid"},
                {"type": "activate_goal", "goalId": "yoga-uuid"},
                {"type": "activate_goal", "goalId": "meal-uuid"}
            ],
            "requiresConfirmation": false
        }

        User: "what should I work on today?"
        Response (portfolio analysis - no actions):
        {
            "reply": "Focus priorities:\\n1. Client Presentation (tomorrow, 60% done) - push to finish!\\n2. Website Launch (Now priority, 85%) - almost there!\\n3. Tax Return (deadline approaching)\\n\\nRecommendation: Finish the website first, then rehearse your presentation.",
            "actions": [],
            "requiresConfirmation": false
        }

        User: "create a work goal for Q1 report and activate it"
        Response (chain multiple actions):
        {
            "reply": "Created 'Q1 Report' and activating it now.",
            "actions": [
                {"type": "create_goal", "parameters": {"title": "Q1 Report", "category": "Work", "priority": "next"}},
                {"type": "activate_goal", "goalId": "newly-created-id"}
            ],
            "requiresConfirmation": false
        }

        User: "show me my overdue goals"
        Response (query and suggest action):
        {
            "reply": "You have 2 goals that need attention:\\n• Marketing Campaign (40% complete, stalled)\\n• Team Meeting Prep (0% complete, high priority)\\n\\nWould you like me to help prioritize or break them down?",
            "actions": [],
            "requiresConfirmation": false
        }

        Remember: The GOAL STRUCTURE section shows what the AI can see about this goal, including all available actions and subtask IDs.
        In general chat, you see the full GOAL PORTFOLIO - use it to take decisive action across all goals!
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
    let kind: String?
    let targetMetric: TargetMetric?
    let phases: [Phase]?
    let roadmapSlices: [RoadmapSlice]?
    let suggestedSubgoals: [String]?  // FIX: Made optional - AI doesn't always return this
    let estimatedDuration: String?
    let difficulty: String?

    struct TargetMetric: Codable {
        let label: String
        let targetValue: Double?
        let unit: String?
        let baselineValue: Double?
        let measurementWindowDays: Int?
        let lowerBound: Double?
        let upperBound: Double?
        let notes: String?
    }

    struct Phase: Codable {
        let title: String
        let summary: String?
        let order: Int
    }

    struct RoadmapSlice: Codable {
        let title: String
        let detail: String?
        let startOffsetDays: Int
        let endOffsetDays: Int
        let expectedMetricDelta: Double?
        let metricUnit: String?
        let confidence: Double?
    }
}

struct GoalBreakdownResponse: Codable {
    let subtasks: [Node]
    let recommendedOrder: [String]
    let totalEstimatedHours: Double?

    struct Node: Codable {
        let id: String?
        let title: String
        let description: String
        let estimatedHours: Double?
        let dependencies: [String]?
        let difficulty: String?
        let children: [Node]?
        let isAtomic: Bool?
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

struct GoalEmojiResponse: Codable {
    let emoji: String
    let reason: String?
}

struct RoadmapResponse: Codable {
    let stops: [StopData]
    let totalDuration: String
    let approach: String

    struct StopData: Codable {
        let order: Int
        let title: String
        let outcome: String
        let daysFromStart: Int
    }
}

struct FirstStopResponse: Codable {
    let stop: StopData
    let estimatedTotalStops: Int
    let rationale: String

    struct StopData: Codable {
        let title: String
        let outcome: String
        let daysFromStart: Int
        let percentageOfGoal: Double
    }
}

struct NextStopResponse: Codable {
    let stop: StopData
    let adjustedTotalStops: Int?
    let reasoning: String

    struct StopData: Codable {
        let title: String
        let outcome: String
        let daysFromStart: Int
        let percentageOfGoal: Double
    }
}

struct NextSequentialStepResponse: Codable {
    let title: String
    let outcome: String
    let aiSuggestion: String?  // AI's proactive guidance on HOW to accomplish this step
    let daysFromNow: Int?
    let reasoning: String?  // WHY this step is necessary
    let isGoalComplete: Bool?  // AI decides if goal is finished after this step
    let confidenceLevel: Double?  // AI's confidence in completion assessment (0-1)
    let estimatedEffortHours: Int?  // Hours of work for timeline visualization
    let treeGrouping: TreeGrouping?  // Emergent structure/sections from AI analysis
}

struct TreeGrouping: Codable {
    let sections: [TreeGroupingSection]

    struct TreeGroupingSection: Codable {
        let title: String              // e.g. "Competitive Analysis"
        let stepIndices: [Int]         // e.g. [2, 3, 4] - which steps belong to this section
        let isComplete: Bool           // true if all steps in section are completed
    }
}

struct InitialRoadmapResponse: Codable {
    let steps: [RoadmapStep]
    let totalEstimatedDays: Int?
    let approach: String?
}

struct RoadmapStep: Codable {
    let order: Int
    let title: String
    let outcome: String
    let daysFromStart: Int
    let reasoning: String?  // WHY this step exists
    let estimatedEffortHours: Int?  // Hours of effort for timeline visualization
}