//
//  Extensions.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

// MARK: - Color Extensions
extension Color {
    static let cardBackground = Color(.systemBackground).opacity(0.8)
    static let cardBackgroundDark = Color(.secondarySystemBackground)
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let successGreen = Color(red: 0.196, green: 0.843, blue: 0.294)
    static let warningOrange = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let errorRed = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let mirrorBlue = Color.blue.opacity(0.1)
}

extension ShapeStyle where Self == Color {
    static var accentBlue: Color { Color(red: 0.0, green: 0.478, blue: 1.0) }
}

// MARK: - View Extensions
extension View {
    func glassBackground(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    func cardStyle() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.impactOccurred()
        }
    }
}

// MARK: - Animation Extensions
extension Animation {
    static let cardSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let smoothSpring = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let quickBounce = Animation.spring(response: 0.3, dampingFraction: 0.6)
}

// MARK: - Date Extensions
extension Date {
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    var shortTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    var mediumDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions
extension String {
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func truncated(to length: Int) -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length)) + "..."
    }
}

// MARK: - Additional View Modifiers
extension View {
    func conditionalBackground<Content: View>(
        condition: Bool,
        @ViewBuilder trueBackground: () -> Content,
        @ViewBuilder falseBackground: () -> Content
    ) -> some View {
        self.background {
            if condition {
                trueBackground()
            } else {
                falseBackground()
            }
        }
    }
}
