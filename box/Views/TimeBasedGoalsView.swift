//
//  TimeBasedGoalsView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct TimeBasedGoalsView: View {
    let goals: [Goal]

    private var nowGoals: [Goal] { goals.filter { $0.priority == .now } }
    private var nextGoals: [Goal] { goals.filter { $0.priority == .next } }
    private var laterGoals: [Goal] { goals.filter { $0.priority == .later } }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            GoalSectionView(
                title: "Now",
                systemImage: "flame.fill",
                tint: .red,
                goals: nowGoals
            )

            GoalSectionView(
                title: "Next",
                systemImage: "clock.fill",
                tint: .orange,
                goals: nextGoals
            )

            GoalSectionView(
                title: "Later",
                systemImage: "calendar",
                tint: .gray,
                goals: laterGoals
            )
        }
        .padding(.vertical)
    }
}

// MARK: - Section View

private struct GoalSectionView: View {
    let title: String
    let systemImage: String
    let tint: Color
    let goals: [Goal]

    var body: some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(tint)

                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text("\(goals.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal)

                ForEach(goals) { goal in
                    GoalCardView(goal: goal)
                        .padding(.horizontal)
                }
            }
        }
    }
}
