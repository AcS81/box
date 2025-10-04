//
//  ConversationSummary.swift
//  box
//
//  Summarizes blocks of conversation for long-term memory
//

import Foundation
import SwiftData

@Model
final class ConversationSummary {
    var id = UUID()
    var scopeData: Data  // Encoded ChatEntry.Scope
    var summary: String
    var keyPoints: [String] = []
    var decisionsAr: [String] = []  // Key decisions made
    var messageCount: Int = 0  // How many messages this summarizes
    var createdAt = Date()

    // Time range of messages
    var startTimestamp: Date
    var endTimestamp: Date

    // Relationship to memory
    @Relationship(inverse: \UserMemory.summaries) var memory: UserMemory?

    init(scope: ChatEntry.Scope, summary: String, keyPoints: [String] = [], decisions: [String] = [], messageCount: Int = 0, startTimestamp: Date, endTimestamp: Date) {
        self.scopeData = (try? JSONEncoder().encode(scope)) ?? Data()
        self.summary = summary
        self.keyPoints = keyPoints
        self.decisionsAr = decisions
        self.messageCount = messageCount
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
    }

    var scope: ChatEntry.Scope {
        get {
            (try? JSONDecoder().decode(ChatEntry.Scope.self, from: scopeData)) ?? .general
        }
        set {
            scopeData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: startTimestamp)) - \(formatter.string(from: endTimestamp))"
    }
}
