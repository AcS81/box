//
//  GoalChatView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct GoalChatView: View {
    @Bindable var goal: Goal
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var isPreparingContext = false
    @State private var pendingActions: [AIAction] = []
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""
    @State private var goalEmoji: String = "🎯"
    @State private var showingSuggestions = true
    @State private var lastMessageTime: Date?
    private let messageDebounceInterval: TimeInterval = 0.5  // 500ms debounce

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var userContextService = UserContextService.shared

    @EnvironmentObject private var lifecycleService: GoalLifecycleService

    private var aiService: AIService { AIService.shared }

    let suggestions = [
        "Break this down into steps",
        "What should I focus on first?",
        "Summarize my progress",
        "Give me motivation",
        "What are potential blockers?",
        "Create a timeline"
    ]

    // MARK: - Timeline (Chat + Revisions)

    private var timeline: [Goal.TimelineItem] {
        goal.unifiedTimeline(from: modelContext)
    }

    private var chatScope: ChatEntry.Scope {
        goal.parent != nil ? .subgoal(goal.id) : .goal(goal.id)
    }

    @ViewBuilder
    private var activeEmojiChip: some View {
        HStack(spacing: 8) {
            Text(goalEmoji)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("Active focus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(goal.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.28 : 0.16))
        )
        .overlay(
            Capsule()
                .stroke(Color.blue.opacity(colorScheme == .dark ? 0.45 : 0.3), lineWidth: 0.8)
        )
        .accessibilityLabel("Goal is active")
        .accessibilityValue(goal.category)
    }
 
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Goal Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            
                            HStack(spacing: 8) {
                                PriorityBadge(priority: goal.priority)
                                
                                if goal.isActive {
                                    activeEmojiChip
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Progress Ring
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                                .frame(width: 50, height: 50)
                            
                            Circle()
                                .trim(from: 0, to: goal.progress)
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .frame(width: 50, height: 50)
                                .rotationEffect(.degrees(-90))
                            
                            Text("\(Int(goal.progress * 100))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                // Subtask Cards Carousel
                let subgoals = goal.sortedSubgoals
                if !subgoals.isEmpty {
                    ChatSubtaskDrawer(
                        goal: goal,
                        subgoals: subgoals,
                        onToggleCompletion: { subgoal, isComplete in
                            Task { await toggleCompletion(for: subgoal, target: isComplete) }
                        },
                        onDelete: { subgoal in
                            Task { await deleteSubgoal(subgoal) }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // AI Introduction
                            ChatBubble(
                                message: "I'm your dedicated assistant for '\(goal.title)'. I'll help you achieve this goal step by step. How can I assist you today?",
                                isUser: false
                            )
                            
                            // Suggestions (if shown)
                            if showingSuggestions && timeline.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Quick actions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    LazyVGrid(columns: [
                                        GridItem(.adaptive(minimum: 140))
                                    ], spacing: 8) {
                                        ForEach(suggestions, id: \.self) { suggestion in
                                            Button(action: {
                                                messageText = suggestion
                                                sendMessage()
                                            }) {
                                                Text(suggestion)
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .frame(maxWidth: .infinity)
                                                    .background(Color.panelBackground)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            // Unified Timeline (Chat + Revisions)
                            ForEach(timeline) { item in
                                switch item {
                                case .chat(let message):
                                    ChatBubble(
                                        message: message.content,
                                        isUser: message.isUser
                                    )
                                    .id(item.id)

                                case .revision(let revision):
                                    SystemEventBubble(revision: revision)
                                        .id(item.id)
                                }
                            }
                            
                            // Loading indicator
                            if isProcessing || isPreparingContext {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(isPreparingContext ? "Preparing..." : "Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color.panelBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: timeline.count) { _, _ in
                        withAnimation {
                            showingSuggestions = false
                            if let lastItem = timeline.last {
                                proxy.scrollTo(lastItem.id, anchor: .bottom)
                            } else if isProcessing {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input Area
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .onSubmit {
                                sendMessage()
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(messageText.isEmpty || isProcessing || isPreparingContext ? .gray : .blue)
                    }
                    .disabled(messageText.isEmpty || isProcessing || isPreparingContext)
                    .scaleEffect(messageText.isEmpty ? 1.0 : 1.1)
                    .animation(.quickBounce, value: messageText.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .onAppear {
                showingSuggestions = timeline.isEmpty
            }
            .task(id: goal.updatedAt) {
                await refreshEmoji()
            }
            .confirmationDialog(
                confirmationMessage,
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Confirm", role: .destructive) {
                    Task {
                        await performExecution(pendingActions)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingActions = []
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmed.isEmpty else { return }

        // Debounce: prevent rapid-fire messages
        if let lastTime = lastMessageTime,
           Date().timeIntervalSince(lastTime) < messageDebounceInterval {
            print("⚠️ Message debounced - too soon after last message")
            return
        }

        lastMessageTime = Date()

        // Create user entry
        let userEntry = ChatEntry(content: messageText, isUser: true, scope: chatScope)
        modelContext.insert(userEntry)

        let currentMessage = messageText
        messageText = ""
        showingSuggestions = false

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        Task {
            isPreparingContext = true
            isProcessing = true

            do {
                // Build rich context with snapshots asynchronously
                let goalsSnapshot = currentGoals()
                let context = await userContextService.buildContext(from: goalsSnapshot)

                isPreparingContext = false

                // Fetch conversation history for this scope
                let history = fetchChatHistory(for: chatScope)

                // Get structured response with actions using unified scope-based chat
                let response = try await aiService.chatWithScope(
                    message: currentMessage,
                    scope: chatScope,
                    history: history,
                    context: context
                )

                // Append AI reply
                let aiEntry = ChatEntry(content: response.reply, isUser: false, scope: chatScope)
                modelContext.insert(aiEntry)

                // Execute actions if present
                if !response.actions.isEmpty {
                    await executeActions(response.actions, goals: goalsSnapshot, requiresConfirmation: response.requiresConfirmation)
                }

                // Update goal
                goal.updatedAt = Date()

                // Success haptic
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

            } catch {
                // Show specific error message instead of generic one
                let errorMessage: String
                if let aiError = error as? AIError {
                    errorMessage = "AI Error: \(aiError.errorDescription ?? "Unknown error")"
                } else {
                    errorMessage = "Error: \(error.localizedDescription)"
                }

                let errorEntry = ChatEntry(
                    content: errorMessage,
                    isUser: false,
                    scope: chatScope
                )
                modelContext.insert(errorEntry)

                // Error haptic
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.error)
            }

            isPreparingContext = false
            isProcessing = false
        }
    }

    @MainActor
    private func toggleCompletion(for subgoal: Goal, target: Bool) async {
        let goalsSnapshot = currentGoals()

        if target {
            await lifecycleService.complete(
                goal: subgoal,
                within: goalsSnapshot,
                modelContext: modelContext
            )
        } else {
            subgoal.deactivate(to: .draft, rationale: "Reopened from chat")
            subgoal.progress = 0
            subgoal.updatedAt = .now
        }

        goal.updatedAt = .now

        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(target ? .success : .warning)
    }

    private func fetchChatHistory(for scope: ChatEntry.Scope) -> [ChatEntry] {
        let descriptor = FetchDescriptor<ChatEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        guard let allEntries = try? modelContext.fetch(descriptor) else { return [] }

        // Filter by scope
        return allEntries.filter { $0.scope == scope }
    }

    @MainActor
    private func executeActions(_ actions: [AIAction], goals: [Goal], requiresConfirmation: Bool) async {
        if requiresConfirmation {
            // Store for confirmation dialog
            pendingActions = actions
            confirmationMessage = generateConfirmationMessage(actions)
            showConfirmation = true
        } else {
            await performExecution(actions)
        }
    }

    @MainActor
    private func performExecution(_ actions: [AIAction]) async {
        let executor = AIActionExecutor(
            lifecycleService: lifecycleService,
            aiService: aiService,
            userContextService: userContextService
        )

        let goalsSnapshot = currentGoals()

        do {
            let results = try await executor.executeAll(
                actions,
                modelContext: modelContext,
                goals: goalsSnapshot,
                fallbackGoal: goal
            )

            // Show results in chat
            for result in results where result.success {
                let feedbackEntry = ChatEntry(
                    content: "✓ \(result.message)",
                    isUser: false,
                    scope: chatScope
                )
                modelContext.insert(feedbackEntry)
            }

            // Show errors
            for result in results where !result.success {
                let errorEntry = ChatEntry(
                    content: "✗ \(result.message)",
                    isUser: false,
                    scope: chatScope
                )
                modelContext.insert(errorEntry)
            }

            // Success haptic
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

        } catch {
            let errorEntry = ChatEntry(
                content: "✗ Action failed: \(error.localizedDescription)",
                isUser: false,
                scope: chatScope
            )
            modelContext.insert(errorEntry)

            print("❌ Action execution failed: \(error)")
        }

        pendingActions = []
    }

    private func generateConfirmationMessage(_ actions: [AIAction]) -> String {
        let actionTypes = actions.map { $0.type.rawValue }.joined(separator: ", ")
        return "Confirm: \(actionTypes)?"
    }

    @MainActor
    private func refreshEmoji() async {
        if let stored = goal.aiGlyph, !stored.isEmpty {
            goalEmoji = stored
        }

        let snapshot = currentGoals()
        let emoji = await GoalEmojiProvider.shared.emoji(for: goal, goalsSnapshot: snapshot)
        goalEmoji = emoji
    }

    private func deleteSubgoal(_ subgoal: Goal) async {
        do {
            try await lifecycleService.delete(goal: subgoal, within: currentGoals(), modelContext: modelContext)
        } catch {
            print("❌ Failed to delete subgoal: \(error.localizedDescription)")
        }
    }
}

private extension GoalChatView {
    func currentGoals() -> [Goal] {
        let descriptor = FetchDescriptor<Goal>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

struct ChatBubble: View {
    let message: String
    let isUser: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if isUser {
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            Color.panelBackground
                        }
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: 20)
                            .applyingCustomCorners(
                                isUser: isUser
                            )
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

extension RoundedRectangle {
    func applyingCustomCorners(isUser: Bool) -> some Shape {
        if isUser {
            return AnyShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 20
                )
            )
        } else {
            return AnyShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 20
                )
            )
        }
    }
}

struct AnyShape: Shape {
    private let makePath: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        let baseShape = shape
        makePath = { rect in
            baseShape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        makePath(rect)
    }
}

// MARK: - Chat Subtask Drawer

private struct ChatSubtaskDrawer: View {
    @Bindable var goal: Goal
    let subgoals: [Goal]
    let onToggleCompletion: (Goal, Bool) -> Void
    let onDelete: (Goal) -> Void

    @State private var isExpanded = true

    private var completedCount: Int {
        subgoals.filter { $0.progress >= 0.999 }.count
    }

    private var averageProgress: Double {
        guard !subgoals.isEmpty else { return 0 }
        let total = subgoals.reduce(0.0) { $0 + $1.progress }
        return total / Double(subgoals.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if subgoals.count > 1 {
                ProgressView(value: averageProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            if isExpanded {
                SubtaskChecklistView(
                    subgoals: subgoals,
                    onToggleCompletion: onToggleCompletion,
                    onDelete: onDelete,
                    onVoiceRecord: nil,
                    onShowDetail: nil
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            footer
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 26, tint: Color.blue.opacity(0.24))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Subtasks", systemImage: "rectangle.stack.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(completedCount) of \(subgoals.count) complete")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.smoothSpring) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .padding(8)
                    .background(
                        Circle().fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse subtasks" : "Expand subtasks")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            summaryChip(icon: "list.bullet.rectangle", label: "Total", value: "\(subgoals.count)")
            summaryChip(icon: "checkmark.circle", label: "Done", value: "\(completedCount)")
            summaryChip(icon: "clock", label: "Updated", value: goal.updatedAt.timeAgo)

            Spacer()

            if subgoals.count > 1 {
                Text("Overall \(Int(averageProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryChip(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }
}

// MARK: - System Event Bubble

struct SystemEventBubble: View {
    let revision: GoalRevision
    @State private var showingDetail = false

    var icon: String {
        let summary = revision.summary.lowercased()

        if summary.contains("created") {
            return "sparkles"
        } else if summary.contains("locked") {
            return "lock.fill"
        } else if summary.contains("unlocked") {
            return "lock.open"
        } else if summary.contains("activated") {
            return "sparkles"
        } else if summary.contains("deactivated") || summary.contains("moved to") {
            return "pause.fill"
        } else if summary.contains("complete") {
            return "checkmark.seal.fill"
        } else if summary.contains("regenerated") {
            return "arrow.clockwise"
        } else if summary.contains("autopilot") {
            return "sparkles"
        } else {
            return "circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(revision.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Show changeDescription if there are before/after snapshots
                if revision.beforeSnapshot != nil && revision.snapshot != nil {
                    Text(revision.changeDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                } else if let rationale = revision.rationale {
                    Text(rationale)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text(revision.createdAt.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            RevisionDetailSheet(revision: revision)
        }
    }
}

