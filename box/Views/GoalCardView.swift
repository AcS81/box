//
//  GoalCardView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct GoalCardView: View {
    @Bindable var goal: Goal
    @State private var isExpanded = false
    @State private var showingChat = false
    @State private var dragOffset = CGSize.zero
    @State private var isPressed = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showActivationPreview = false
    @State private var activationPlan: CalendarService.ActivationPlan?
    @State private var showDeleteConfirmation = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var lifecycleService: GoalLifecycleService

    @StateObject private var userContextService = UserContextService.shared

    private var aiService: AIService { AIService.shared }

    private var isProcessing: Bool {
        lifecycleService.isProcessing(goalID: goal.id)
    }
    
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
                            
                            if goal.isLocked {
                                Label("Locked", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.yellow.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            ActivationBadge(state: goal.activationState)
                        }
                    }
                    
                    Spacer()

                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        }
                        Button(action: toggleLock) {
                            Image(systemName: goal.isLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(goal.isLocked ? .yellow : .secondary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.gray.opacity(0.12)))
                        }
                        .disabled(isProcessing)
                        .accessibilityLabel(goal.isLocked ? "Unlock goal" : "Lock goal")
                        .accessibilityHint(goal.isLocked ? "Double tap to unlock this goal and allow changes" : "Double tap to lock this goal and prevent accidental changes")
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
                                    isLoading: isProcessing,
                                    isDisabled: goal.isLocked || isProcessing
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

                                ActionButton(
                                    title: goal.activationState == .active ? "Deactivate" : "Activate",
                                    icon: goal.activationState == .active ? "pause.fill" : "bolt.fill",
                                    color: goal.activationState == .active ? .gray : .green,
                                    isLoading: isProcessing,
                                    isDisabled: goal.isLocked
                                ) {
                                    Task { await handleActivationAction() }
                                }

                                ActionButton(
                                    title: "Delete",
                                    icon: "trash.fill",
                                    color: .red,
                                    isDisabled: isProcessing
                                ) {
                                    showDeleteConfirmation = true
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
        .accessibilityLabel("Goal: \(goal.title)")
        .accessibilityValue("Progress: \(Int(goal.progress * 100)) percent, Priority: \(goal.priority.rawValue)")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") goal details")
        .accessibilityAddTraits(.isButton)
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
        .alert("Something went wrong", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "Delete \"\(goal.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Goal", role: .destructive) {
                Task { await deleteGoal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All subgoals and related data will also be deleted.")
        }
        .sheet(isPresented: $showActivationPreview, onDismiss: {
            activationPlan = nil
        }) {
            if let plan = activationPlan {
                ActivationPreviewSheet(
                    goalTitle: goal.title,
                    plan: plan,
                    isProcessing: isProcessing,
                    onConfirm: {
                        Task { await confirmActivation(using: plan) }
                    },
                    onCancel: {
                        dismissActivationPreview()
                    }
                )
                .presentationDetents([.medium, .large])
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing activation plan...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingChat) {
            GoalChatView(goal: goal)
        }
    }
    
    // MARK: - Actions
    
    private func breakdownGoal() async {
        do {
            let goalsSnapshot = currentGoals()
            let context = userContextService.buildContext(from: goalsSnapshot)
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
    
    private func toggleLock() {
        if goal.isLocked {
            lifecycleService.unlock(goal: goal, reason: "User unlocked card")
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
        } else {
            Task {
                let goalsSnapshot = currentGoals()
                await lifecycleService.lock(goal: goal, within: goalsSnapshot, modelContext: modelContext)
                await MainActor.run {
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                }
            }
        }
    }

    private func handleActivationAction() async {
        if goal.activationState == .active {
            await lifecycleService.deactivate(goal: goal, reason: "User deactivated", modelContext: modelContext)
            await MainActor.run {
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.warning)
            }
            return
        }

        do {
            let goalsSnapshot = currentGoals()
            let plan = try await lifecycleService.generateActivationPlan(for: goal, within: goalsSnapshot)

            await MainActor.run {
                activationPlan = plan
                showActivationPreview = true
            }
        } catch {
            await MainActor.run {
                presentError(error)
            }
        }
    }

    private func confirmActivation(using plan: CalendarService.ActivationPlan) async {
        do {
            let goalsSnapshot = currentGoals()
            try await lifecycleService.confirmActivation(
                goal: goal,
                plan: plan,
                within: goalsSnapshot,
                modelContext: modelContext
            )

            await MainActor.run {
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
                dismissActivationPreview()
            }
        } catch {
            await MainActor.run {
                dismissActivationPreview()
                presentError(error)
            }
        }
    }

    private func dismissActivationPreview() {
        showActivationPreview = false
        activationPlan = nil
    }

    private func regenerateGoal() async {
        do {
            let goalsSnapshot = currentGoals()
            try await lifecycleService.regenerate(goal: goal, within: goalsSnapshot, modelContext: modelContext)
            await MainActor.run {
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        } catch {
            await MainActor.run {
                presentError(error)
            }
        }
    }
    
    private func summarizeProgress() async {
        do {
            let goalsSnapshot = currentGoals()
            let context = userContextService.buildContext(from: goalsSnapshot)
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

    private func deleteGoal() async {
        do {
            let goalsSnapshot = currentGoals()
            try await lifecycleService.delete(goal: goal, within: goalsSnapshot, modelContext: modelContext)

            await MainActor.run {
                // Haptic feedback for deletion
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
            }
        } catch {
            await MainActor.run {
                presentError(error)
            }
        }
    }

    @MainActor
    private func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
        showErrorAlert = true
    }

    private func currentGoals() -> [Goal] {
        let descriptor = FetchDescriptor<Goal>()
        return (try? modelContext.fetch(descriptor)) ?? []
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

struct ActivationBadge: View {
    let state: Goal.ActivationState

    var body: some View {
        Group {
            if let info = state.presentation {
                Label(info.title, systemImage: info.icon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(info.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(info.color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}

struct ActivationPreviewSheet: View {
    let goalTitle: String
    let plan: CalendarService.ActivationPlan
    let isProcessing: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activate \(goalTitle)")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Review the AI-suggested focus sessions before committing them to your calendar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.events) { event in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(event.title)
                                    .font(.headline)
                                Spacer()
                                Text(durationString(for: event.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Label(
                                    event.startDate.formatted(date: .abbreviated, time: .shortened),
                                    systemImage: "calendar.badge.clock"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if let slot = event.suggestedTimeSlot {
                                    Label(slot.capitalized, systemImage: "clock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let notes = event.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }

                            if let prep = event.preparation, !prep.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prep")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)

                                    ForEach(prep, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "checkmark.circle")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(item)
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }

            if !plan.tips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scheduling Tips")
                        .font(.footnote)
                        .fontWeight(.semibold)

                    ForEach(plan.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(tip)
                                .font(.caption2)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Text("Confirm Activation")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
        }
        .padding()
        .presentationDragIndicator(.visible)
    }

    private func durationString(for duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    var isDisabled: Bool = false
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
        .disabled(isLoading || isDisabled)
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

private extension Goal.ActivationState {
    struct Presentation {
        let title: String
        let icon: String
        let color: Color
    }

    var presentation: Presentation? {
        switch self {
        case .draft:
            return nil
        case .active:
            return Presentation(title: "Active", icon: "bolt.fill", color: .green)
        case .completed:
            return Presentation(title: "Completed", icon: "checkmark.seal.fill", color: .blue)
        case .archived:
            return Presentation(title: "Archived", icon: "archivebox.fill", color: .gray)
        }
    }
}