//
//  GoalDependency.swift
//  box
//
//  Created on 01.10.2025.
//

import Foundation
import SwiftData

@Model
final class GoalDependency {
    enum Kind: String, Codable, CaseIterable {
        case finishToStart
        case startToStart
        case finishToFinish
    }

    var id = UUID()
    var createdAt: Date = Date()
    var note: String?
    var kind: Kind

    @Relationship var prerequisite: Goal?
    @Relationship var dependent: Goal?

    init(
        prerequisite: Goal? = nil,
        dependent: Goal? = nil,
        kind: Kind = .finishToStart,
        note: String? = nil
    ) {
        self.kind = kind
        self.prerequisite = prerequisite
        self.dependent = dependent
        self.note = note
    }
}

