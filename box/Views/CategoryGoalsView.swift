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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category Header
            Button(action: {
                withAnimation(.smoothSpring) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)

                    Text(category)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("(\(goals.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 12) {
                    ForEach(goals.sorted(by: { $0.createdAt > $1.createdAt })) { goal in
                        GoalCardView(goal: goal)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
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
                        Color(.secondarySystemBackground)
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
                            Color(.secondarySystemBackground)
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