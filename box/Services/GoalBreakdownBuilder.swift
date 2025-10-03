//
//  GoalBreakdownBuilder.swift
//  box
//
//  Created on 01.10.2025.
//

import Foundation
import SwiftData

struct GoalBreakdownBuilder {
    struct Result {
        let createdGoals: [Goal]
        let dependencyCount: Int
        let atomicTaskCount: Int
        let assignedIdentifiers: [UUID: String]
    }

    static func apply(
        response: GoalBreakdownResponse,
        to parent: Goal,
        in modelContext: ModelContext
    ) -> Result {
        var slugger = SlugGenerator()
        var createdGoals: [Goal] = []
        var records: [NodeRecord] = []
        var atomicCount = 0
        var assignedIdentifiers: [UUID: String] = [:]

        for node in response.subtasks {
            records += build(
                node: node,
                parent: parent,
                modelContext: modelContext,
                slugger: &slugger,
                createdGoals: &createdGoals,
                atomicCount: &atomicCount,
                assignedIdentifiers: &assignedIdentifiers
            )
        }

        let dependencyCount = createDependencies(from: records, slugger: slugger, modelContext: modelContext)

        return Result(
            createdGoals: createdGoals,
            dependencyCount: dependencyCount,
            atomicTaskCount: atomicCount,
            assignedIdentifiers: assignedIdentifiers
        )
    }

    private static func build(
        node: GoalBreakdownResponse.Node,
        parent: Goal,
        modelContext: ModelContext,
        slugger: inout SlugGenerator,
        createdGoals: inout [Goal],
        atomicCount: inout Int,
        assignedIdentifiers: inout [UUID: String]
    ) -> [NodeRecord] {
        let identifier = slugger.assignIdentifier(for: node)

        let detail = formatContent(for: node)
        let subgoal = Goal(
            title: node.title,
            content: detail,
            category: parent.category,
            priority: priority(for: node.difficulty)
        )
        subgoal.parent = parent
        subgoal.sortOrder = Double(createdGoals.count)
        subgoal.progress = 0.0
        subgoal.updatedAt = Date()
        subgoal.isAutopilotEnabled = parent.isAutopilotEnabled

        modelContext.insert(subgoal)
        createdGoals.append(subgoal)
        assignedIdentifiers[subgoal.id] = identifier

        var records: [NodeRecord] = [NodeRecord(node: node, identifier: identifier, goal: subgoal)]

        if let children = node.children, !children.isEmpty {
            for child in children {
                records += build(
                    node: child,
                    parent: subgoal,
                    modelContext: modelContext,
                    slugger: &slugger,
                    createdGoals: &createdGoals,
                    atomicCount: &atomicCount,
                    assignedIdentifiers: &assignedIdentifiers
                )
            }

            subgoal.hasBeenBrokenDown = true
        } else {
            atomicCount += 1
        }

        return records
    }

    private static func createDependencies(
        from records: [NodeRecord],
        slugger: SlugGenerator,
        modelContext: ModelContext
    ) -> Int {
        guard !records.isEmpty else { return 0 }

        var index: [String: Goal] = [:]
        for record in records {
            index[record.identifier] = record.goal
        }

        var created = 0

        for record in records {
            guard let dependencyIds = record.node.dependencies, !dependencyIds.isEmpty else {
                continue
            }

            for rawId in dependencyIds {
                let normalized = slugger.normalize(rawId)
                guard
                    let prerequisite = index[normalized],
                    prerequisite.id != record.goal.id,
                    !record.goal.incomingDependencies.contains(where: { $0.prerequisite?.id == prerequisite.id })
                else { continue }

                let link = GoalDependency(prerequisite: prerequisite, dependent: record.goal)
                modelContext.insert(link)
                created += 1
            }
        }

        return created
    }

    private static func formatContent(for node: GoalBreakdownResponse.Node) -> String {
        var metadata: [String] = []

        if let hours = node.estimatedHours {
            let formatted = String(format: "%.1f", hours)
            metadata.append("Estimate: \(formatted)h")
        }

        if let difficulty = node.difficulty, !difficulty.isEmpty {
            metadata.append("Difficulty: \(difficulty.capitalized)")
        }

        if metadata.isEmpty {
            return node.description
        }

        return node.description + "\n\n" + metadata.joined(separator: " • ")
    }

    private static func priority(for difficulty: String?) -> Goal.Priority {
        guard let difficulty else { return .later }
        switch difficulty.lowercased() {
        case "hard":
            return .now
        case "medium":
            return .next
        default:
            return .later
        }
    }

    private struct NodeRecord {
        let node: GoalBreakdownResponse.Node
        let identifier: String
        let goal: Goal
    }

    private struct SlugGenerator {
        private var assigned: Set<String> = []

        mutating func assignIdentifier(for node: GoalBreakdownResponse.Node) -> String {
            let proposed = node.id ?? node.title
            return ensureUnique(normalize(proposed))
        }

        func normalize(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return UUID().uuidString.lowercased() }

            let lowercased = trimmed.lowercased()
            let transformed = lowercased
                .map { char -> Character in
                    if char.isLetter || char.isNumber { return char }
                    if char == "-" || char == " " { return "-" }
                    return "-"
                }
            let collapsed = String(transformed)
                .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

            return collapsed.isEmpty ? UUID().uuidString.lowercased() : collapsed
        }

        private mutating func ensureUnique(_ candidate: String) -> String {
            var final = candidate
            var counter = 2
            while assigned.contains(final) {
                final = "\(candidate)-\(counter)"
                counter += 1
            }
            assigned.insert(final)
            return final
        }
    }
}

