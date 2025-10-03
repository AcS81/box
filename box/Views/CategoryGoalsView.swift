//
//  CategoryGoalsView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct CategoryGoalsView: View {
    let goals: [Goal]

    var categorizedGoals: [String: [Goal]] {
        Dictionary(grouping: goals, by: { $0.category })
    }

    var body: some View {
        LazyVStack(spacing: 20) {
            ForEach(categorizedGoals.keys.sorted(), id: \.self) { category in
                if let categoryGoals = categorizedGoals[category] {
                    CategorySection(category: category, goals: categoryGoals)
                }
            }
        }
    }
}

struct CategorySection: View {
    let category: String
    let goals: [Goal]
    @State private var isExpanded = true

    private var activeGoalsCount: Int {
        goals.filter { $0.activationState == .active }.count
    }

    private var lockedGoalsCount: Int {
        goals.filter { $0.isLocked }.count
    }

    private var averageProgress: Double {
        guard !goals.isEmpty else { return 0 }
        let total = goals.reduce(0.0) { $0 + $1.progress }
        return total / Double(goals.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.smoothSpring) {
                    isExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Label(category, systemImage: "folder.fill")
                            .font(.title3.weight(.semibold))
                            .labelStyle(.titleAndIcon)

                        Spacer()

                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(
                                Text("\(goals.count) goals")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                            )
                            .frame(height: 28)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }

                    HStack(spacing: 12) {
                        categoryMetric(title: "Active", value: "\(activeGoalsCount)")
                        categoryMetric(title: "Locked", value: "\(lockedGoalsCount)")
                        categoryMetric(title: "Avg", value: "\(Int(averageProgress * 100))%")
                    }

                    ProgressView(value: averageProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .liquidGlassCard(cornerRadius: 26, tint: Color.accentColor.opacity(0.22))
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 12) {
                    ForEach(goals.sorted(by: { $0.createdAt > $1.createdAt })) { goal in
                        GoalCardView(goal: goal)
                    }
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
    }

    private func categoryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

struct CategoryFilterView: View {
    let categories: [String]
    @Binding var selectedCategory: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All categories button
                Button(action: {
                    withAnimation(.smoothSpring) {
                        selectedCategory = nil
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption)
                        Text("All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(selectedCategory == nil ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedCategory == nil ?
                        Color.blue :
                        Color.panelBackground
                    )
                    .clipShape(Capsule())
                }

                ForEach(categories, id: \.self) { category in
                    Button(action: {
                        withAnimation(.smoothSpring) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                            Text(category)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(selectedCategory == category ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedCategory == category ?
                            Color.blue :
                            Color.panelBackground
                        )
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    let sampleGoals = [
        Goal(title: "Learn SwiftUI", category: "Development"),
        Goal(title: "Build an app", category: "Development"),
        Goal(title: "Exercise daily", category: "Health"),
        Goal(title: "Read books", category: "Education")
    ]

    CategoryGoalsView(goals: sampleGoals)
}