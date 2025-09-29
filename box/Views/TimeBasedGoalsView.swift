//
//  TimeBasedGoalsView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct TimeBasedGoalsView: View {
    let goals: [Goal]
    
    var nowGoals: [Goal] { goals.filter { $0.priority == .now } }
    var nextGoals: [Goal] { goals.filter { $0.priority == .next } }
    var laterGoals: [Goal] { goals.filter { $0.priority == .later } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Now Section
            if !nowGoals.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.red)
                        
                        Text("Now")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text("·")
                            .foregroundStyle(.secondary)
                        
                        Text("\(nowGoals.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ForEach(nowGoals) { goal in
                        GoalCardView(goal: goal)
                            .padding(.horizontal)
                    }
                }
            }
            
            // Next Section
            if !nextGoals.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)
                        
                        Text("Next")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text("·")
                            .foregroundStyle(.secondary)
                        
                        Text("\(nextGoals.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ForEach(nextGoals) { goal in
                        GoalCardView(goal: goal)
                            .padding(.horizontal)
                    }
                }
            }
            
            // Later Section
            if !laterGoals.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                            .foregroundStyle(.gray)
                        
                        Text("Later")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text("·")
                            .foregroundStyle(.secondary)
                        
                        Text("\(laterGoals.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ForEach(laterGoals) { goal in
                        GoalCardView(goal: goal)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.vertical)
    }
}

struct CategoryGoalsView: View {
    let goals: [Goal]
    
    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(goals) { goal in
                GoalCardView(goal: goal)
            }
        }
    }
}

struct CategoryFilterView: View {
    let categories: [String]
    @Binding var selectedCategory: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FilterChip(
                    title: "All",
                    isSelected: selectedCategory == nil
                ) {
                    withAnimation(.smoothSpring) {
                        selectedCategory = nil
                    }
                }
                
                ForEach(categories, id: \.self) { category in
                    FilterChip(
                        title: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.smoothSpring) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ?
                    AnyView(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    ) :
                    AnyView(Color.gray.opacity(0.15))
                )
                .clipShape(Capsule())
                .overlay(
                    !isSelected ?
                    Capsule()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1) :
                    nil
                )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.quickBounce, value: isSelected)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("Ready to begin?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Text("Write or speak your first goal above")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        Text("Voice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.title3)
                            .foregroundStyle(.purple)
                        Text("Type")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
