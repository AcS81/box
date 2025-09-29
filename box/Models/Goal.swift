//
//  Goal.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

@Model
class Goal {
    var id = UUID()
    var title: String = ""
    var content: String = ""
    var category: String = "General"
    var priority: Priority = Priority.next
    var isActive: Bool = false
    var progress: Double = 0.0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var targetDate: Date?
    
    @Relationship(deleteRule: .cascade) var subgoals: [Goal]?
    @Relationship(inverse: \Goal.subgoals) var parent: Goal?
    @Relationship(deleteRule: .cascade) var chatHistory: [ChatMessage]?
    
    enum Priority: String, Codable, CaseIterable {
        case now = "Now"
        case next = "Next"
        case later = "Later"
    }
    
    init(title: String, content: String = "", category: String = "General", priority: Priority = Priority.next, targetDate: Date? = nil) {
        self.title = title
        self.content = content
        self.category = category
        self.priority = priority
        self.targetDate = targetDate
    }
}

@Model
class ChatMessage {
    var id = UUID()
    var content: String = ""
    var isUser: Bool = true
    var timestamp: Date = Date()
    var goalId: UUID?
    
    init(content: String, isUser: Bool = true, goalId: UUID? = nil) {
        self.content = content
        self.isUser = isUser
        self.goalId = goalId
    }
}

@Model
class AIMirrorCard {
    var id = UUID()
    var title: String = ""
    var aiInterpretation: String = ""
    var suggestedActions: [String] = []
    var confidence: Double = 0.0
    var relatedGoalId: UUID?
    var createdAt: Date = Date()
    
    init(title: String, interpretation: String = "", relatedGoalId: UUID? = nil) {
        self.title = title
        self.aiInterpretation = interpretation
        self.relatedGoalId = relatedGoalId
    }
}
