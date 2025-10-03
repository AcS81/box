//
//  ProactiveInsightsView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct ProactiveInsightsView: View {
    @ObservedObject var proactiveService: ProactiveAIService
    let onActionTapped: (ProactiveInsightAction, UUID?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(proactiveService.insights) { insight in
                    InsightCard(
                        insight: insight,
                        onActionTapped: { action in
                            onActionTapped(action, insight.goalId)
                        },
                        onDismiss: {
                            proactiveService.dismissInsight(insight)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct InsightCard: View {
    let insight: ProactiveInsight
    let onActionTapped: (ProactiveInsightAction) -> Void
    let onDismiss: () -> Void

    var priorityColor: Color {
        switch insight.priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    var iconName: String {
        switch insight.type {
        case .stagnation: return "clock.arrow.circlepath"
        case .quickWin: return "flag.checkered"
        case .unactivated: return "bolt.slash"
        case .overdue: return "exclamationmark.triangle"
        case .suggestion: return "lightbulb"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundStyle(priorityColor)

                        Text(insight.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                    }

                    Text(insight.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            if !insight.suggestedActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(insight.suggestedActions) { action in
                        Button(action: { onActionTapped(action) }) {
                            Text(action.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(priorityColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(priorityColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ProactiveInsightsView(
        proactiveService: ProactiveAIService.shared,
        onActionTapped: { _, _ in }
    )
    .padding()
}