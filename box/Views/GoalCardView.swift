//
//  GoalCardView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct GoalCardView: View {
    @Bindable var goal: Goal
    @State private var isExpanded = false
    @State private var showingChat = false
    @State private var isRegenerating = false
    @State private var showingActions = false
    @State private var dragOffset = CGSize.zero
    @State private var isPressed = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var allGoals: [Goal]

    @StateObject private var userContextService = UserContextService.shared

    private var aiService: AIService { AIService.shared }
    private let calendarService = CalendarService()
    
    var cardGradient: LinearGradient {
        switch goal.priority {
        case .now:
            return LinearGradient(
                colors: [Color.red.opacity(0.1), Color.red.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .next:
            return LinearGradient(
                colors: [Color.orange.opacity(0.1), Color.orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .later:
            return LinearGradient(
                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Card Content
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goal.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 8) {
                            // Category Badge
                            Label(goal.category, systemImage: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Capsule())
                            
                            // Priority Badge
                            PriorityBadge(priority: goal.priority)
                            
                            if goal.isActive {
                                Label("Active", systemImage: "bolt.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Active Toggle
                    Toggle("", isOn: $goal.isActive)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .scaleEffect(0.8)
                        .onChange(of: goal.isActive) { _, newValue in
                            if newValue {
                                Task {
                                    await scheduleGoal()
                                }
                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }
                        }
                }
                
                // Content (when expanded)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        if !goal.content.isEmpty {
                            Text(goal.content)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        
                        // Progress Bar
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Progress")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(goal.progress * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * goal.progress, height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                        
                        // Action Buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ActionButton(
                                    title: "Chat",
                                    icon: "bubble.left.fill",
                                    color: .blue
                                ) {
                                    showingChat = true
                                }
                                
                                ActionButton(
                                    title: "Break Down",
                                    icon: "square.grid.2x2.fill",
                                    color: .purple
                                ) {
                                    Task { await breakdownGoal() }
                                }
                                
                                ActionButton(
                                    title: "Regenerate",
                                    icon: "arrow.clockwise",
                                    color: .orange,
                                    isLoading: isRegenerating
                                ) {
                                    Task { await regenerateGoal() }
                                }
                                
                                ActionButton(
                                    title: "Summary",
                                    icon: "doc.text.fill",
                                    color: .green
                                ) {
                                    Task { await summarizeProgress() }
                                }
                            }
                        }
                        
                        // Subgoals
                        if let subgoals = goal.subgoals, !subgoals.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Subtasks")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                
                                ForEach(subgoals) { subgoal in
                                    SubgoalRow(subgoal: subgoal)
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                        // Metadata
                        HStack {
                            Label(goal.createdAt.timeAgo, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            if goal.updatedAt != goal.createdAt {
                                Text("Updated \(goal.updatedAt.timeAgo)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
        }
        .background(
            ZStack {
                if goal.isActive {
                    cardGradient
                }
                Color(.systemBackground).opacity(colorScheme == .dark ? 0.3 : 0.8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    goal.isActive ? 
                    Color.blue.opacity(0.3) : 
                    Color.gray.opacity(0.1),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1),
            radius: isExpanded ? 12 : 8,
            x: 0,
            y: isExpanded ? 6 : 4
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .offset(dragOffset)
        .onTapGesture {
            withAnimation(.cardSpring) {
                isExpanded.toggle()
            }
            
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    withAnimation(.interactiveSpring()) {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    withAnimation(.cardSpring) {
                        if abs(value.translation.width) > 100 {
                            // Swipe to delete or archive
                            if value.translation.width > 0 {
                                // Archive
                                goal.isActive = false
                            }
                        }
                        dragOffset = .zero
                    }
                }
        )
        .sheet(isPresented: $showingChat) {
            GoalChatView(goal: goal)
        }
    }
    
    // MARK: - Actions
    
    private func scheduleGoal() async {
        do {
            let events = try await calendarService.generateSmartSchedule(for: goal, goals: allGoals)
            for event in events {
                try await calendarService.createEvent(
                    title: event.title,
                    startDate: event.startDate,
                    duration: event.duration,
                    notes: "Goal: \(goal.title)\n\n\(goal.content)"
                )
            }
            print("🗓️ Successfully scheduled \(events.count) events for: \(goal.title)")
        } catch {
            print("❌ Failed to schedule: \(error)")
        }
    }
    
    private func breakdownGoal() async {
        do {
            let context = userContextService.buildContext(from: allGoals)
            let response = try await aiService.breakdownGoal(goal, context: context)

            await MainActor.run {
                // Create subgoals from AI response
                for subtask in response.subtasks {
                    let subgoal = Goal(
                        title: subtask.title,
                        content: subtask.description,
                        category: goal.category,
                        priority: .later
                    )
                    subgoal.parent = goal
                    subgoal.progress = 0.0

                    modelContext.insert(subgoal)
                }

                goal.updatedAt = Date()

                print("🔗 Created \(response.subtasks.count) subgoals for: \(goal.title)")
                print("⏱️ Total estimated hours: \(response.totalEstimatedHours)")

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        } catch {
            print("❌ Failed to breakdown: \(error)")
        }
    }
    
    private func regenerateGoal() async {
        withAnimation(.cardSpring) {
            isRegenerating = true
        }

        do {
            let context = userContextService.buildContext(from: allGoals)
            let response = try await aiService.chatWithGoal(
                message: "Regenerate this goal with fresh perspective and new ideas. Provide a refined title and description.",
                goal: goal,
                context: context
            )

            await MainActor.run {
                // Update goal with AI suggestions (simplified for now)
                goal.updatedAt = Date()

                print("🔄 Regenerated goal: \(goal.title)")

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        } catch {
            print("❌ Failed to regenerate: \(error)")
        }

        withAnimation(.cardSpring) {
            isRegenerating = false
        }
    }
    
    private func summarizeProgress() async {
        do {
            let context = userContextService.buildContext(from: allGoals)
            let response = try await aiService.summarizeProgress(for: goal, context: context)

            await MainActor.run {
                // Show summary in alert or sheet (for now just print)
                print("📊 Progress Summary for \(goal.title):")
                print(response)

                goal.updatedAt = Date()

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        } catch {
            print("❌ Failed to summarize: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct PriorityBadge: View {
    let priority: Goal.Priority
    
    var color: Color {
        switch priority {
        case .now: return .red
        case .next: return .orange
        case .later: return .gray
        }
    }
    
    var icon: String {
        switch priority {
        case .now: return "flame.fill"
        case .next: return "clock.fill"
        case .later: return "calendar"
        }
    }
    
    var body: some View {
        Label(priority.rawValue, systemImage: icon)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color)
            .clipShape(Capsule())
        }
        .disabled(isLoading)
    }
}

struct SubgoalRow: View {
    @Bindable var subgoal: Goal
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.cardSpring) {
                    subgoal.progress = subgoal.progress >= 1.0 ? 0.0 : 1.0
                }
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }) {
                Image(systemName: subgoal.progress >= 1.0 ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subgoal.progress >= 1.0 ? .green : .secondary)
                    .font(.system(size: 20))
            }
            
            Text(subgoal.title)
                .font(.subheadline)
                .strikethrough(subgoal.progress >= 1.0)
                .foregroundStyle(subgoal.progress >= 1.0 ? .secondary : .primary)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}