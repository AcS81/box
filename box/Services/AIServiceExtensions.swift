//
//  AIServiceExtensions.swift
//  box
//
//  Created on 29.09.2025.
//

import Foundation
import SwiftData

extension AIService {

    func createGoal(from input: String, context: AIContext) async throws -> GoalCreationResponse {
        let function = AIFunction.createGoal(input: input, context: context)
        return try await processRequest(function, responseType: GoalCreationResponse.self)
    }

    // MARK: - Proactive Analysis

    func analyzeNewGoalForActions(_ goal: Goal, context: AIContext) async throws -> ProactiveGoalAnalysis {
        // Analyze the newly created goal and determine if proactive actions should be taken
        let analysisPrompt = buildProactiveAnalysisPrompt(for: goal, context: context)
        let response = try await makeProactiveAnalysisRequest(prompt: analysisPrompt)
        return try parseProactiveAnalysis(response)
    }

    private func buildProactiveAnalysisPrompt(for goal: Goal, context: AIContext) -> String {
        let contextSection = buildContextSection(context)

        return """
        \(contextSection)

        PROACTIVE GOAL ANALYSIS

        Analyze this newly created goal and determine if automatic actions should be taken:

        Goal Title: "\(goal.title)"
        Description: \(goal.content.isEmpty ? "No description" : goal.content)
        Priority: \(goal.priority.rawValue)
        Category: \(goal.category)

        ANALYSIS CRITERIA:

        1. COMPLEXITY CHECK:
           - Does this goal mention multiple steps, phases, or stages?
           - Does it contain words like: "and then", "first", "second", "finally", numbered lists?
           - Does it span multiple time periods or require sequential actions?
           → If YES: Suggest "breakdown" action

        2. ACTIVATION CHECK:
           - Is this a "Now" priority goal?
           - Is there urgency in the language?
           → If YES: Suggest "activate_goal" action

        3. CLARITY CHECK:
           - Is the goal vague or too broad?
           - Could it benefit from AI refinement?
           → If YES: Note in reasoning (but don't auto-execute)

        Return as JSON:
        {
            "shouldTakeAction": true|false,
            "confidence": 0.0-1.0,
            "reasoning": "Clear explanation of why actions are suggested",
            "suggestedActions": [
                {"type": "breakdown", "reason": "Goal mentions multiple phases"},
                {"type": "suggest_activation", "reason": "High priority goal needs scheduling"}
            ],
            "userMessage": "Friendly message explaining what AI will do"
        }

        IMPORTANT:
        - Only suggest actions with high confidence (>0.7)
        - Explain reasoning clearly
        - Be conservative - when in doubt, don't suggest actions
        - "breakdown" should only be suggested for clearly multi-step goals
        - "suggest_activation" (not auto-activate) for Now priority goals
        """
    }

    private func makeProactiveAnalysisRequest(prompt: String) async throws -> String {
        let apiKey = currentAPIKey
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        var request = URLRequest(url: URL(string: baseURL)!, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": proactiveAnalysisSystemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIError.networkError
        }

        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content, !content.isEmpty else {
            throw AIError.invalidResponse
        }

        return content
    }

    private func parseProactiveAnalysis(_ response: String) throws -> ProactiveGoalAnalysis {
        let cleanedResponse = cleanJSONResponse(response)
        let jsonData = cleanedResponse.data(using: .utf8) ?? Data()

        do {
            return try JSONDecoder().decode(ProactiveGoalAnalysis.self, from: jsonData)
        } catch {
            print("❌ Failed to parse proactive analysis: \(error)")
            // Return safe default
            return ProactiveGoalAnalysis(
                shouldTakeAction: false,
                confidence: 0.0,
                reasoning: "Could not analyze goal",
                suggestedActions: [],
                userMessage: nil
            )
        }
    }

    private var proactiveAnalysisSystemPrompt: String {
        """
        You are a proactive AI assistant analyzing goals to determine if automatic actions should be taken.

        Your role:
        - Analyze goal complexity and structure
        - Suggest helpful actions ONLY when confident they will benefit the user
        - Be conservative - it's better to do nothing than to be wrong
        - Explain your reasoning clearly

        Return valid JSON only, no additional text.
        """
    }

    func breakdownGoal(_ goal: Goal, context: AIContext) async throws -> GoalBreakdownResponse {
        let function = AIFunction.breakdownGoal(goal: goal, context: context)
        return try await processRequest(function, responseType: GoalBreakdownResponse.self)
    }

    // MARK: - Unified Sequential Step Generation

    /// Generate initial roadmap (3-7 steps) for a new goal
    func generateInitialRoadmap(for goal: Goal, context: AIContext) async throws -> InitialRoadmapResponse {
        let prompt = buildInitialRoadmapPrompt(for: goal, context: context)
        let response = try await makeRoadmapRequest(prompt: prompt)
        return try parseInitialRoadmapResponse(response)
    }

    func generateNextSequentialStep(for goal: Goal, completedStep: Goal, context: AIContext) async throws -> NextSequentialStepResponse {
        let prompt = buildNextSequentialStepPrompt(for: goal, completedStep: completedStep, context: context)
        let response = try await makeRoadmapRequest(prompt: prompt)
        return try parseNextSequentialStepResponse(response)
    }

    private func buildNextSequentialStepPrompt(for goal: Goal, completedStep: Goal, context: AIContext) -> String {
        let contextSection = buildContextSection(context)
        let allSteps = goal.sequentialSteps
        let completedSteps = goal.completedSequentialSteps

        // All previous step titles to prevent duplicates
        let allStepTitles = allSteps.map { "- \"\($0.title)\"" }.joined(separator: "\n")

        let historySection = completedSteps.map { step in
            let userInputsList = step.userInputs.isEmpty ? "N/A" : step.userInputs.map { "• \($0)" }.joined(separator: "\n              ")
            return """
            - Step \(step.orderIndexInParent + 1): "\(step.title)"
              Outcome: \(step.outcome)
              User Inputs: \(userInputsList)
              Progress: \(Int(step.progress * 100))%
            """
        }.joined(separator: "\n")

        let stepCountWarning = allSteps.count >= 10
            ? "\n⚠️ WARNING: This goal already has \(allSteps.count) steps. This is above the recommended maximum of 10. Consider if the goal is becoming too complex and if completion is truly necessary.\n"
            : ""

        return """
        \(contextSection)

        NEXT SEQUENTIAL STEP GENERATION

        Generate the NEXT logical step for this goal:

        Goal Title: "\(goal.title)"
        Description: \(goal.content)
        Current Progress: \(completedSteps.count)/\(allSteps.count) steps completed\(stepCountWarning)

        ALL EXISTING STEP TITLES (DO NOT DUPLICATE ANY OF THESE):
        \(allStepTitles)

        COMPLETED STEPS:
        \(historySection.isEmpty ? "None yet" : historySection)

        JUST COMPLETED:
        - Title: "\(completedStep.title)"
        - Outcome: \(completedStep.outcome)
        - Progress: \(Int(completedStep.progress * 100))%

        INSTRUCTIONS:

        1. Review ALL existing step titles above and ensure your new step title is UNIQUE
        2. DO NOT repeat, rephrase, or create variations of existing step titles
        3. If you find yourself wanting to repeat a step (like "Evaluate", "Review", "Assess"), the goal may be complete instead
        4. Consider what was just completed and the overall goal
        5. Generate the NEXT logical step in the sequence (must be different from all previous)
        6. Make the step achievable and concrete
        7. Focus on one clear outcome
        8. Suggest a realistic timeframe (days from now)
        9. CRITICAL DECISION: Determine if the goal will be COMPLETE after this next step
           - If this is the FINAL step needed to achieve the goal, set isGoalComplete: true
           - If more steps will be needed after this one, set isGoalComplete: false
           - If the goal already has 10+ steps, strongly consider marking it complete
           - Provide your confidence level (0.0 to 1.0) in this assessment

        DUPLICATE PREVENTION RULES:
        - Never use the same title as an existing step
        - Avoid generic repeated actions like "Review again", "Evaluate once more", "Final check"
        - If you're tempted to add a duplicate-sounding step, set isGoalComplete: true instead
        - Each step should represent meaningful NEW progress toward the goal

        TREE GROUPING ANALYSIS:
        Look at all completed and pending steps and identify logical groupings/phases/sections.
        Consider:
        - Which steps naturally belong together? (e.g., multiple competitor analyses)
        - What phases emerged from the work? (e.g., "Research Phase", "Competitive Analysis")
        - How would you organize these steps into a hierarchical tree structure?
        - Mark sections as complete if all their steps are completed

        PROACTIVE GUIDANCE (CRITICAL):
        Don't just tell the user HOW to find information - GIVE THEM THE INFORMATION DIRECTLY.
        Don't say "research X" - actually provide the key knowledge about X.
        Don't say "identify your goals" - propose specific goals based on context.
        Don't say "create a plan" - provide the actual plan.

        BE PROACTIVE. ANSWER YOUR OWN QUESTIONS. DO THE THINKING FOR THE USER.

        Use the user's previous inputs and context to make suggestions EVEN MORE SPECIFIC:
        - If they said "Budget: $340k" - use that number in your recommendations
        - If they said "Prefer mornings" - schedule activities in morning
        - If they said "8pm-10pm study" - incorporate that into the plan
        - Adapt your suggestions to THEIR specific situation

        Include in "aiSuggestion":
        - Actual knowledge, facts, or recommendations (not just "how to learn it")
        - Specific examples, numbers, data points
        - Concrete next actions with details filled in
        - Your best judgment on what they should do
        - Actual content, not meta-advice
        - Personalized to their inputs when available

        ❌ BAD examples (too meta, not helpful enough):
        - "Research nutrition concepts by reading articles and taking notes on macros and calories"
        - "Identify your main goals and prioritize them by importance"
        - "Create a weekly schedule by blocking out time for each activity"

        ✅ GOOD examples (proactive, specific, actually helpful):
        - "Nutrition basics: Proteins build muscle (aim 0.8g per lb bodyweight), Carbs fuel energy (focus on complex carbs like oats, rice), Fats support hormones (need healthy fats like avocado, nuts). Calories = energy units. Eat 500 cal deficit to lose 1lb/week, surplus to gain. Track with MyFitnessPal first week to learn portions."
        - "Based on typical goals: Career (advance to senior role within 2 years), Health (workout 3x/week, lose 15lbs), Relationships (date night weekly, call family 2x/month), Learning (complete Python course by June). Prioritize health first since energy affects everything else."
        - "Weekly plan: Mon/Wed/Fri 7am workout 45min. Tue/Thu deep work 9-11am on biggest project. Every evening 8-9pm learning time. Sat morning meal prep 2hrs. Sun rest + social. Block these in calendar now, protect the time, adjust after 2 weeks based on what stuck."

        Return as JSON:
        {
            "title": "Build core prototype",
            "outcome": "Working demo of main features ready for testing",
            "aiSuggestion": "Core features for MVP: (1) User signup/login, (2) Create/edit goals, (3) View progress dashboard, (4) Mark tasks complete, (5) Basic notifications. Build with React + Supabase (fastest). Day 1-2: Setup + auth page. Day 3-4: Goal CRUD. Day 5: Dashboard with charts. Day 6-7: Polish + test with 3 friends. Deploy on Vercel (free). Skip: Settings, themes, advanced filters - add later based on feedback. This gets you to testable product in 1 week.",
            "daysFromNow": 14,
            "reasoning": "Research is complete - now we apply those insights to build a testable prototype",
            "estimatedEffortHours": 35,
            "isGoalComplete": false,
            "confidenceLevel": 0.85,
            "treeGrouping": {
                "sections": [
                    {
                        "title": "Research Phase",
                        "stepIndices": [0, 1],
                        "isComplete": true
                    },
                    {
                        "title": "Competitive Analysis",
                        "stepIndices": [2, 3, 4],
                        "isComplete": true
                    }
                ]
            }
        }

        NOTE: stepIndices use 0-based indexing (0 = first step, 1 = second step, etc.)
        NOTE: treeGrouping is OPTIONAL - only include if you identify meaningful groupings
        NOTE: aiSuggestion is REQUIRED - always provide helpful guidance

        CRITICAL: Return ONLY the JSON object. No additional text.
        """
    }

    private func parseNextSequentialStepResponse(_ responseText: String) throws -> NextSequentialStepResponse {
        let cleaned = cleanJSONResponse(responseText)
        guard let data = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        do {
            let response = try JSONDecoder().decode(NextSequentialStepResponse.self, from: data)
            return response
        } catch {
            throw AIError.invalidResponse
        }
    }

    private func makeRoadmapRequest(prompt: String) async throws -> String {
        let apiKey = currentAPIKey
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        var request = URLRequest(url: URL(string: baseURL)!, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": roadmapSystemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.5,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIError.networkError
        }

        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content, !content.isEmpty else {
            throw AIError.invalidResponse
        }

        return content
    }

    private var roadmapSystemPrompt: String {
        """
        You are an expert project planner helping users break down goals into achievable milestones.

        Your role:
        - Create realistic, sequential roadmaps
        - Balance ambition with achievability
        - Provide clear, actionable milestones
        - Distribute timeline appropriately based on goal complexity

        Return valid JSON only, no additional text.
        """
    }

    // MARK: - Initial Roadmap Generation

    private func buildInitialRoadmapPrompt(for goal: Goal, context: AIContext) -> String {
        let contextSection = buildContextSection(context)

        return """
        \(contextSection)

        INITIAL ROADMAP GENERATION

        Create a complete roadmap for achieving this goal:

        Goal Title: "\(goal.title)"
        Description: \(goal.content.isEmpty ? "No additional description" : goal.content)
        Priority: \(goal.priority.rawValue)
        Category: \(goal.category)
        \(goal.targetDate != nil ? "Target Date: \(goal.targetDate!.formatted(date: .abbreviated, time: .omitted))" : "No specific deadline")

        INSTRUCTIONS:

        1. Break down the goal into 3-7 sequential steps
        2. Each step should be a meaningful milestone
        3. Steps build on each other logically
        4. Make steps concrete and achievable
        5. Distribute timeline realistically based on priority:
           - Now priority: aggressive timeline (days to weeks)
           - Next priority: moderate timeline (weeks to months)
           - Later priority: relaxed timeline (months)

        Return as JSON:
        {
            "steps": [
                {
                    "order": 1,
                    "title": "Research and define requirements",
                    "outcome": "Clear understanding of what needs to be done",
                    "daysFromStart": 7,
                    "reasoning": "Starting with research ensures we build the right thing",
                    "estimatedEffortHours": 12
                },
                {
                    "order": 2,
                    "title": "Create initial prototype",
                    "outcome": "Basic working version ready for feedback",
                    "daysFromStart": 21,
                    "reasoning": "Prototype validates assumptions before full build",
                    "estimatedEffortHours": 35
                }
                // ... 3-7 steps total
            ],
            "totalEstimatedDays": 90,
            "approach": "Brief explanation of the overall strategy"
        }

        IMPORTANT:
        - Generate 3-7 steps (not more, not less)
        - Final step should achieve the stated goal
        - Be realistic about timeframes
        - Each step must have clear outcome

        CRITICAL: Return ONLY the JSON object. No additional text.
        """
    }

    private func parseInitialRoadmapResponse(_ responseText: String) throws -> InitialRoadmapResponse {
        let cleaned = cleanJSONResponse(responseText)
        guard let data = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        do {
            let response = try JSONDecoder().decode(InitialRoadmapResponse.self, from: data)
            guard response.steps.count >= 3 && response.steps.count <= 7 else {
                print("⚠️ AI returned \(response.steps.count) steps, expected 3-7")
                throw AIError.invalidResponse
            }
            return response
        } catch {
            print("❌ Failed to parse initial roadmap: \(error)")
            throw AIError.invalidResponse
        }
    }

    func chatWithGoal(message: String, goal: Goal, context: AIContext) async throws -> String {
        let function = AIFunction.chatWithGoal(message: message, goal: goal, context: context)
        return try await processRequest(function)
    }

    // NEW: Chat with actions
    func chatWithGoalWithActions(message: String, goal: Goal, context: AIContext) async throws -> ChatResponse {
        let function = AIFunction.chatWithGoal(message: message, goal: goal, context: context)
        return try await processWithActions(function)
    }

    // NEW: General chat with actions (for bulk operations)
    func generalChatWithActions(message: String, context: AIContext, history: [GeneralChatMessage]) async throws -> ChatResponse {
        let function = AIFunction.generalChat(message: message, history: history, context: context)
        return try await processWithActions(function)
    }

    // MARK: - Unified Scope-Based Chat

    /// Unified scope-based chat method - works for general, goal, and subtask contexts
    func chatWithScope(
        message: String,
        scope: ChatEntry.Scope,
        history: [ChatEntry],
        context: AIContext
    ) async throws -> ChatResponse {
        let scopeContext = buildScopeContext(scope, context)
        let historyFormatted = formatChatHistory(history)

        let prompt = """
        \(scopeContext)

        CONVERSATION HISTORY:
        \(historyFormatted)

        User's current message: "\(message)"

        Act as the user's intelligent goal management assistant. Reference the context and history appropriately. Provide conversational responses and suggest actions when appropriate.

        CRITICAL: You MUST respond with valid JSON in this exact format:
        {
            "reply": "Your conversational response here",
            "actions": [],
            "requiresConfirmation": false
        }

        Do NOT include any text before or after the JSON. ONLY return the JSON object.
        """

        let apiKey = currentAPIKey
        guard !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        let response = try await performScopedAPIRequest(
            prompt: prompt,
            systemPrompt: actionAwareSystemPrompt,
            apiKey: apiKey
        )

        do {
            let chatResponse = try parseJSONResponse(response, as: ChatResponse.self)
            return chatResponse
        } catch {
            print("❌ Chat parsing error: \(error)")
            print("📄 Response: \(response)")
            throw error
        }
    }

    private func buildScopeContext(_ scope: ChatEntry.Scope, _ context: AIContext) -> String {
        let portfolioSection = buildGoalPortfolioSection(context)
        let contextSection = buildContextSection(context)

        switch scope {
        case .general:
            return """
            \(contextSection)

            CONVERSATION SCOPE: GENERAL CHAT
            You are the user's command center. Create new goals instantly, take decisive actions on any goal or subtask listed below, run bulk operations, and deliver portfolio-wide insights without asking clarifying questions.

            GOAL PORTFOLIO:
            \(portfolioSection)

            Capabilities from this scope:
            - Instant goal creation (no goalId needed)
            - Single-goal operations using the goalId from this portfolio
            - Subtask micromanagement when the user specifies goal + subtask IDs
            - Bulk actions across any combination of goals (bulk_delete, bulk_archive, bulk_complete, reorder_goals, merge_goals when available)
            - Portfolio queries, prioritization advice, and cross-goal recommendations
            """

        case .goal(let goalId):
            guard let snapshot = context.goalSnapshots.first(where: { $0.id == goalId.uuidString }) else {
                return """
                \(contextSection)

                CONVERSATION SCOPE: GOAL-SPECIFIC CHAT
                Goal not found in current context.
                """
            }

            let goalStructure = buildGoalStructureFromSnapshot(snapshot)

            return """
            \(contextSection)

            CONVERSATION SCOPE: GOAL-SPECIFIC CHAT
            User is chatting with this specific goal: "\(snapshot.title)"

            \(goalStructure)

            This is the dedicated assistant for this goal. Focus on helping the user make progress on THIS specific goal.
            Reference subtasks, parent context, and siblings when relevant.
            """

        case .subgoal(let subgoalId):
            guard let snapshot = context.goalSnapshots.first(where: { $0.id == subgoalId.uuidString }) else {
                return """
                \(contextSection)

                CONVERSATION SCOPE: SUBTASK CHAT
                Subtask not found in current context.
                """
            }

            let goalStructure = buildGoalStructureFromSnapshot(snapshot)

            let parentInfo: String
            if let parent = snapshot.parent {
                parentInfo = "Parent goal: \(parent.title) [status: \(parent.activationState), progress: \(Int(parent.progress * 100))%]"
            } else {
                parentInfo = "No parent goal"
            }

            let siblingsInfo: String
            if !snapshot.siblings.isEmpty {
                let siblingList = snapshot.siblings.prefix(3).map { "• \($0.title) (\(Int($0.progress * 100))%)" }.joined(separator: "\n")
                siblingsInfo = "Sibling subtasks:\n\(siblingList)"
            } else {
                siblingsInfo = "No sibling subtasks"
            }

            return """
            \(contextSection)

            CONVERSATION SCOPE: SUBTASK CHAT
            User is chatting with this subtask: "\(snapshot.title)"

            \(goalStructure)

            \(parentInfo)
            \(siblingsInfo)

            This is a subtask assistant. Help the user complete this specific subtask while being aware of the parent goal context.
            """
        }
    }

    private func buildGoalStructureFromSnapshot(_ snapshot: ChatGoalSnapshot) -> String {
        var structure = """
        GOAL DETAILS:
        - Goal ID: \(snapshot.id) (USE THIS EXACT ID IN ALL ACTIONS for this goal)
        - Title: \(snapshot.title)
        - Status: \(snapshot.activationState)
        - Locked: \(snapshot.isLocked ? "Yes (cannot modify)" : "No")
        - Progress: \(Int(snapshot.progress * 100))%
        - Priority: \(snapshot.priority)
        - Category: \(snapshot.category)
        - Calendar Events: \(snapshot.eventCount)
        """

        if !snapshot.content.isEmpty {
            structure += "\n- Description: \(snapshot.content)"
        }

        if snapshot.totalSubgoalCount > 0 {
            structure += "\n\nSUBTASK TREE: \(snapshot.totalSubgoalCount) total (\(snapshot.atomicSubgoalCount) atomic, depth \(snapshot.maxSubgoalDepth))"
            let (description, displayed) = renderSubtaskTreeDescription(for: snapshot, limit: 24)
            if !description.isEmpty {
                structure += "\n" + description
            }

            let remaining = snapshot.totalSubgoalCount - displayed
            if remaining > 0 {
                structure += "\n  ... +\(remaining) more nodes"
            }
        }

        structure += "\n\nAVAILABLE ACTIONS:\n" + snapshot.availableActions.prefix(12).joined(separator: ", ")
        if snapshot.availableActions.count > 12 {
            structure += ", +\(snapshot.availableActions.count - 12) more"
        }

        return structure
    }

    private func formatChatHistory(_ history: [ChatEntry]) -> String {
        guard !history.isEmpty else {
            return "No previous conversation yet."
        }

        let recentMessages = history.suffix(12)
        return recentMessages.map { entry in
            let role = entry.isUser ? "User" : "AI"
            let timestamp = entry.timestamp.formatted(date: .omitted, time: .shortened)
            let scopeLabel = entry.scope.scopeLabel
            return "\(timestamp) [\(scopeLabel)] \(role): \(entry.content)"
        }.joined(separator: "\n")
    }

    private func performScopedAPIRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String
    ) async throws -> String {
        return try await retryWithExponentialBackoff(maxRetries: 3) {
            var request = URLRequest(url: URL(string: self.baseURL)!, timeoutInterval: self.requestTimeout)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": "gpt-4",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.4,
                "max_tokens": 1500
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
                print("❌ Bad request to OpenAI API")
                throw AIError.invalidFormat
            default:
                print("❌ OpenAI API error: \(httpResponse.statusCode)")
                throw AIError.invalidResponse
            }
        }
    }

    // REMOVED: generateCalendarEvents (calendar integration removed)

    func summarizeProgress(for goal: Goal, context: AIContext) async throws -> String {
        let function = AIFunction.summarizeProgress(goal: goal, context: context)
        return try await processRequest(function)
    }

    func reorderCards(_ goals: [Goal], instruction: String, context: AIContext) async throws -> GoalReorderResponse {
        let function = AIFunction.reorderCards(goals: goals, instruction: instruction, context: context)
        return try await processRequest(function, responseType: GoalReorderResponse.self)
    }

    func generateMirrorCard(for goal: Goal, context: AIContext) async throws -> MirrorCardResponse {
        let function = AIFunction.generateMirrorCard(goal: goal, context: context)
        return try await processRequest(function, responseType: MirrorCardResponse.self)
    }

    // MARK: - Intent Routing

    func processUnifiedMessage(_ message: String, goal: Goal? = nil, context: AIContext) async throws -> UnifiedChatResponse {
        // Parse the message for intents
        let intent = parseIntent(from: message, goal: goal)

        switch intent {
        case .deleteGoal(let targetGoal):
            return UnifiedChatResponse(
                message: "I'll delete the goal '\(targetGoal.title)' for you.",
                intent: .delete(targetGoal),
                requiresConfirmation: true
            )

        case .completeGoal(let targetGoal):
            return UnifiedChatResponse(
                message: "Great! I'll mark '\(targetGoal.title)' as completed.",
                intent: .complete(targetGoal),
                requiresConfirmation: false
            )

        case .editGoal(let targetGoal, let changes):
            return UnifiedChatResponse(
                message: "I'll update '\(targetGoal.title)' with your changes.",
                intent: .edit(targetGoal, changes),
                requiresConfirmation: false
            )

        case .chat:
            // Regular chat - route to appropriate chat function
            if let goal = goal {
                let response = try await chatWithGoal(message: message, goal: goal, context: context)
                return UnifiedChatResponse(message: response, intent: nil, requiresConfirmation: false)
            } else {
                // General management chat
                let response = try await processGeneralManagement(message: message, context: context)
                return UnifiedChatResponse(message: response, intent: nil, requiresConfirmation: false)
            }
        }
    }

    private func parseIntent(from message: String, goal: Goal?) -> ChatIntent {
        let lowercased = message.lowercased()

        // Delete intents
        if lowercased.contains("delete") || lowercased.contains("remove") || lowercased.contains("trash") {
            if lowercased.contains("this") || lowercased.contains("goal"), let goal = goal {
                return .deleteGoal(goal)
            }
        }

        // Complete intents
        if lowercased.contains("complete") || lowercased.contains("done") || lowercased.contains("finish") {
            if lowercased.contains("this") || lowercased.contains("goal"), let goal = goal {
                return .completeGoal(goal)
            }
        }

        // Edit intents
        if lowercased.contains("edit") || lowercased.contains("change") || lowercased.contains("update") || lowercased.contains("modify") {
            if let goal = goal {
                let changes = extractEditChanges(from: message)
                return .editGoal(goal, changes)
            }
        }

        return .chat
    }

    private func extractEditChanges(from message: String) -> GoalEditChanges {
        // Simple extraction logic - could be made more sophisticated
        var changes = GoalEditChanges()

        let lowercased = message.lowercased()

        // Extract title changes
        if let titleMatch = message.range(of: "title to \"([^\"]+)\"", options: .regularExpression) {
            changes.title = String(message[titleMatch]).replacingOccurrences(of: "title to \"", with: "").replacingOccurrences(of: "\"", with: "")
        }

        // Extract priority changes
        if lowercased.contains("priority") {
            if lowercased.contains("now") {
                changes.priority = .now
            } else if lowercased.contains("next") {
                changes.priority = .next
            } else if lowercased.contains("later") {
                changes.priority = .later
            }
        }

        return changes
    }

    private func processGeneralManagement(message: String, context: AIContext) async throws -> String {
        // For now, use the existing reorder logic or general chat
        // This could be expanded to handle various management tasks
        if message.lowercased().contains("reorder") || message.lowercased().contains("sort") {
            let response = try await reorderCards(context.recentGoals, instruction: message, context: context)
            return response.reasoning
        } else {
            // Generic management response - this could be expanded
            return "I understand you want to manage your goals. Could you be more specific about what you'd like me to help you with?"
        }
    }
}

enum ChatIntent {
    case deleteGoal(Goal)
    case completeGoal(Goal)
    case editGoal(Goal, GoalEditChanges)
    case chat
}

struct UnifiedChatResponse {
    let message: String
    let intent: LifecycleIntent?
    let requiresConfirmation: Bool
}

enum LifecycleIntent {
    case delete(Goal)
    case complete(Goal)
    case edit(Goal, GoalEditChanges)
}

struct GoalEditChanges {
    var title: String?
    var content: String?
    var category: String?
    var priority: Goal.Priority?
}

// MARK: - Proactive Analysis Models

struct ProactiveGoalAnalysis: Codable {
    let shouldTakeAction: Bool
    let confidence: Double
    let reasoning: String
    let suggestedActions: [ProactiveSuggestedAction]
    let userMessage: String?
}

struct ProactiveSuggestedAction: Codable {
    let type: String
    let reason: String
}

extension Goal {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "title": title,
            "content": content,
            "category": category,
            "priority": priority.rawValue,
            "isActive": isActive,
            "progress": progress,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "sortOrder": effectiveSortOrder
        ]
    }

    var timeToCompletion: String {
        guard progress < 1.0 else { return "Completed" }

        let timeElapsed = Date().timeIntervalSince(createdAt)
        let progressRate = progress / timeElapsed

        guard progressRate > 0 else { return "No progress yet" }

        let remainingWork = 1.0 - progress
        let estimatedTimeRemaining = remainingWork / progressRate

        let days = Int(estimatedTimeRemaining / 86400)
        let hours = Int((estimatedTimeRemaining.truncatingRemainder(dividingBy: 86400)) / 3600)

        if days > 0 {
            return "\(days) days, \(hours) hours"
        } else if hours > 0 {
            return "\(hours) hours"
        } else {
            return "Less than an hour"
        }
    }

    var priorityColor: String {
        switch priority {
        case .now: return "red"
        case .next: return "orange"
        case .later: return "blue"
        }
    }

    var isOverdue: Bool {
        guard let targetDate = targetDate else { return false }
        return Date() > targetDate && progress < 1.0
    }
}

extension AIContext {
    static func create(from goals: [Goal]) async -> AIContext {
        await UserContextService.shared.buildContext(from: goals)
    }

    var contextSummary: String {
        var summary = "Context: \(recentGoals.count) recent goals"

        if completedGoalsCount > 0 {
            summary += ", \(completedGoalsCount) completed"
        }

        if let avgTime = averageCompletionTime {
            let days = Int(avgTime / 86400)
            summary += ", avg completion: \(days) days"
        }

        if let hours = preferredWorkingHours {
            summary += ", work hours: \(hours.start):00-\(hours.end):00"
        }

        return summary
    }
}