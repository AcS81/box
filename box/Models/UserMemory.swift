//
//  UserMemory.swift
//  box
//
//  Singleton container for all persistent user memory
//

import Foundation
import SwiftData

@Model
final class UserMemory {
    var id = UUID()

    // Persistent user facts learned from conversations
    @Relationship(deleteRule: .cascade) var facts: [UserFact] = []

    // Conversation summaries for long-term context
    @Relationship(deleteRule: .cascade) var summaries: [ConversationSummary] = []

    // Global preferences discovered
    var preferences: [String: String] = [:]

    // Communication patterns
    var communicationStyle: String = "balanced"  // "detailed", "brief", "balanced"
    var preferredTone: String = "encouraging"  // "encouraging", "direct", "analytical"

    // Last updated
    var updatedAt = Date()

    // Metadata
    var totalConversations: Int = 0
    var totalFactsExtracted: Int = 0

    init() {
        // Empty init - singleton will be created in context
    }

    // Get high-confidence facts for AI context
    var highConfidenceFacts: [UserFact] {
        facts.filter { $0.isHighConfidence }
            .sorted { $0.extractedAt > $1.extractedAt }
    }

    // Get recent summaries (last 5)
    var recentSummaries: [ConversationSummary] {
        summaries.sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { $0 }
    }

    // Get summaries for specific scope
    func summaries(for scope: ChatEntry.Scope) -> [ConversationSummary] {
        summaries.filter { $0.scope == scope }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // Get facts for specific scope
    func facts(for scope: ChatEntry.Scope) -> [UserFact] {
        facts.filter { $0.scope == scope }
            .sorted { $0.confidence > $1.confidence }
    }

    // Add a new fact
    func addFact(_ fact: UserFact) {
        facts.append(fact)
        totalFactsExtracted += 1
        updatedAt = Date()
    }

    // Add a new summary
    func addSummary(_ summary: ConversationSummary) {
        summaries.append(summary)
        totalConversations += 1
        updatedAt = Date()
    }

    // Update preference
    func setPreference(key: String, value: String) {
        preferences[key] = value
        updatedAt = Date()
    }
}
