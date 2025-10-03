import Foundation
import SwiftUI

@MainActor
final class GoalEmojiProvider {
    static let shared = GoalEmojiProvider(
        aiService: AIService.shared,
        userContextService: UserContextService.shared
    )

    private let aiService: AIService
    private let userContextService: UserContextService
    private var inFlight: [UUID: Task<String, Never>] = [:]

    private let fallbackEmojis: [String] = [
        "🎯", "🚀", "🌱", "🧠", "📈", "🛠", "✨", "🎨", "🏋️", "💡", "📚", "🧭"
    ]

    init(aiService: AIService, userContextService: UserContextService) {
        self.aiService = aiService
        self.userContextService = userContextService
    }

    func emoji(for goal: Goal, goalsSnapshot: [Goal]) async -> String {
        if let stored = sanitized(goal.aiGlyph) {
            return stored
        }

        if let task = inFlight[goal.id] {
            return await task.value
        }

        let fallback = fallbackEmoji(for: goal)
        let task = Task<String, Never> { [weak self] in
            guard let self else { return fallback }

            do {
                let context = await self.userContextService.buildContext(from: goalsSnapshot)
                let response = try await self.aiService.suggestEmoji(for: goal, context: context)
                let suggestion = self.sanitized(response.emoji) ?? fallback
                self.store(suggestion, for: goal)
                return suggestion
            } catch {
                self.store(fallback, for: goal)
                return fallback
            }
        }

        inFlight[goal.id] = task
        let result = await task.value
        inFlight[goal.id] = nil
        return result
    }

    private func store(_ emoji: String, for goal: Goal) {
        goal.aiGlyph = emoji
        goal.aiGlyphUpdatedAt = Date()
    }

    private func sanitized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let character = trimmed.first
        guard let character else { return nil }

        if isEmojiCharacter(character) {
            return String(character)
        }

        // Some emojis compose with variation selectors; try full grapheme cluster next
        if trimmed.unicodeScalars.allSatisfy({ $0.properties.isEmojiPresentation || $0.properties.isEmoji }) {
            return trimmed
        }

        return nil
    }

    private func isEmojiCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }

    private func fallbackEmoji(for goal: Goal) -> String {
        let scalarSum = goal.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let categorySum = goal.category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let index = (scalarSum + categorySum) % fallbackEmojis.count
        return fallbackEmojis[index]
    }
}
