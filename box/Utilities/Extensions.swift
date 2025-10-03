//
//  Extensions.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

// MARK: - Color Extensions
extension Color {
    #if os(iOS)
    static let cardBackground = Color(.systemBackground).opacity(0.8)
    static let cardBackgroundDark = Color(.secondarySystemBackground)
    static let panelBackground = Color(.secondarySystemBackground)
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    #else
    static let cardBackground = Color(NSColor.windowBackgroundColor).opacity(0.8)
    static let cardBackgroundDark = Color(NSColor.underPageBackgroundColor)
    static let panelBackground = Color(NSColor.underPageBackgroundColor)
    static let primaryText = Color(NSColor.labelColor)
    static let secondaryText = Color(NSColor.secondaryLabelColor)
    #endif
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
    
    func liquidGlassCard(cornerRadius: CGFloat = 24, tint: Color = Color.blue.opacity(0.12)) -> some View {
        self
            .padding(1)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                            .blendMode(.plusLighter)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.9),
                                        tint.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blur(radius: 28)
                            .opacity(0.7)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 16)
    }

    func cardStyle() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    #if os(iOS)
    /// Dismisses keyboard when view is tapped
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.impactOccurred()
        }
    }
    #else
    func hapticFeedback(_ style: Int = 0) -> some View { self }
    #endif
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

extension TimeInterval {
    var asClockString: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
