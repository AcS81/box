//
//  UserFact.swift
//  box
//
//  Persistent user facts learned from conversations
//

import Foundation
import SwiftData

@Model
final class UserFact {
    var id = UUID()
    var fact: String
    var confidence: Double
    var sourceScope: Data  // Encoded ChatEntry.Scope
    var extractedAt = Date()
    var category: String  // "preference", "constraint", "pattern", "decision"

    // Relationship to memory
    @Relationship(inverse: \UserMemory.facts) var memory: UserMemory?

    init(fact: String, confidence: Double, scope: ChatEntry.Scope, category: String = "preference") {
        self.fact = fact
        self.confidence = confidence
        self.sourceScope = (try? JSONEncoder().encode(scope)) ?? Data()
        self.category = category
    }

    var scope: ChatEntry.Scope {
        get {
            (try? JSONDecoder().decode(ChatEntry.Scope.self, from: sourceScope)) ?? .general
        }
        set {
            sourceScope = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var isHighConfidence: Bool {
        confidence >= 0.7
    }
}
