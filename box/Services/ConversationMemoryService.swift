//
//  ConversationMemoryService.swift
//  box
//
//  Manages conversation summarization and fact extraction
//

import Foundation
import SwiftData

@MainActor
class ConversationMemoryService {
    static let shared = ConversationMemoryService()

    private let aiService: AIService
    private let summarizationThreshold = 20  // Summarize every 20 messages

    private init() {
        self.aiService = AIService.shared
    }

    // MARK: - Main Entry Point

    func processConversation(
        scope: ChatEntry.Scope,
        entries: [ChatEntry],
        userMemory: UserMemory,
        modelContext: ModelContext
    ) async {
        // Get unsummarized messages for this scope
        let unsummarized = entries
            .filter { $0.scope == scope && !$0.isSummarized }
            .sorted { $0.timestamp < $1.timestamp }

        guard unsummarized.count >= summarizationThreshold else {
            print("📊 Only \(unsummarized.count) unsummarized messages, threshold is \(summarizationThreshold)")
            return
        }

        print("🔄 Summarizing \(unsummarized.count) messages for scope: \(scope.scopeLabel)")

        do {
            // Generate summary
            let summary = try await generateSummary(for: unsummarized, scope: scope)
            modelContext.insert(summary)
            userMemory.addSummary(summary)

            // Extract facts
            let facts = try await extractFacts(from: unsummarized, scope: scope)
            for fact in facts {
                modelContext.insert(fact)
                userMemory.addFact(fact)
            }

            // Mark messages as summarized
            for entry in unsummarized {
                entry.isSummarized = true
            }

            print("✅ Created summary with \(summary.keyPoints.count) key points and extracted \(facts.count) facts")

        } catch {
            print("❌ Failed to process conversation: \(error)")
        }
    }

    // MARK: - Summary Generation

    private func generateSummary(
        for messages: [ChatEntry],
        scope: ChatEntry.Scope
    ) async throws -> ConversationSummary {
        let prompt = buildSummaryPrompt(for: messages, scope: scope)
        let response = try await aiService.processRequest(
            .generalChat(message: prompt, history: [], context: AIContext()),
            responseType: SummaryResponse.self
        )

        return ConversationSummary(
            scope: scope,
            summary: response.summary,
            keyPoints: response.keyPoints,
            decisions: response.decisions,
            messageCount: messages.count,
            startTimestamp: messages.first?.timestamp ?? Date(),
            endTimestamp: messages.last?.timestamp ?? Date()
        )
    }

    private func buildSummaryPrompt(for messages: [ChatEntry], scope: ChatEntry.Scope) -> String {
        let transcript = messages.map { entry in
            let role = entry.isUser ? "User" : "AI"
            let time = entry.timestamp.formatted(date: .omitted, time: .shortened)
            return "\(time) \(role): \(entry.content)"
        }.joined(separator: "\n")

        return """
        Summarize this conversation segment from \(scope.scopeLabel) context.

        CONVERSATION TRANSCRIPT (\(messages.count) messages):
        \(transcript)

        Create a comprehensive summary that captures:
        1. Main topics discussed
        2. Key decisions made
        3. Important preferences or constraints mentioned
        4. Action items or commitments

        Return as JSON:
        {
            "summary": "2-3 sentence overview of what happened in this conversation",
            "keyPoints": [
                "First key point or topic",
                "Second key point",
                "Third key point"
            ],
            "decisions": [
                "User decided to X",
                "Agreed to prioritize Y"
            ]
        }

        Keep it concise but informative. Focus on what the AI needs to remember for future context.
        """
    }

    // MARK: - Fact Extraction

    private func extractFacts(
        from messages: [ChatEntry],
        scope: ChatEntry.Scope
    ) async throws -> [UserFact] {
        let prompt = buildFactExtractionPrompt(for: messages, scope: scope)
        let response = try await aiService.processRequest(
            .generalChat(message: prompt, history: [], context: AIContext()),
            responseType: FactExtractionResponse.self
        )

        return response.facts.map { factData in
            UserFact(
                fact: factData.fact,
                confidence: factData.confidence,
                scope: scope,
                category: factData.category
            )
        }
    }

    private func buildFactExtractionPrompt(for messages: [ChatEntry], scope: ChatEntry.Scope) -> String {
        let userMessages = messages.filter { $0.isUser }.map { $0.content }
        let transcript = userMessages.joined(separator: "\n")

        return """
        Extract persistent user facts from these messages.

        USER MESSAGES:
        \(transcript)

        Look for:
        - Preferences: "I prefer mornings", "I like detailed explanations"
        - Constraints: "Budget is $340k", "Available 8-10pm only"
        - Patterns: "Usually breaks tasks into 3-5 steps"
        - Decisions: "Will focus on health goals first"

        Return as JSON:
        {
            "facts": [
                {
                    "fact": "Prefers morning workouts",
                    "confidence": 0.9,
                    "category": "preference"
                },
                {
                    "fact": "Budget constraint: $340k",
                    "confidence": 1.0,
                    "category": "constraint"
                }
            ]
        }

        Categories: "preference", "constraint", "pattern", "decision"
        Confidence: 0.0 to 1.0 (1.0 = explicitly stated, 0.7 = strongly implied, 0.5 = inferred)

        Only extract facts that would be useful for future AI interactions. Skip generic statements.
        """
    }

    // MARK: - Helper: Get or Create UserMemory

    static func getOrCreateUserMemory(modelContext: ModelContext) -> UserMemory {
        let descriptor = FetchDescriptor<UserMemory>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let newMemory = UserMemory()
        modelContext.insert(newMemory)
        return newMemory
    }
}

// MARK: - Response Models

private struct SummaryResponse: Codable {
    let summary: String
    let keyPoints: [String]
    let decisions: [String]
}

private struct FactExtractionResponse: Codable {
    let facts: [ExtractedFact]
}

private struct ExtractedFact: Codable {
    let fact: String
    let confidence: Double
    let category: String
}
