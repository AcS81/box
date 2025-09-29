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
    @State private var showingSuggestions = true
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var voiceService = VoiceService()
    @StateObject private var userContextService = UserContextService.shared

    private var aiService: AIService { AIService.shared }
    
    let suggestions = [
        "Break this down into steps",
        "What should I focus on first?",
        "Summarize my progress",
        "Give me motivation",
        "What are potential blockers?",
        "Create a timeline"
    ]
    
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
                                    Label("Active", systemImage: "bolt.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green)
                                        .clipShape(Capsule())
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
                            if showingSuggestions && (goal.chatHistory?.isEmpty ?? true) {
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
                                                    .background(Color(.secondarySystemBackground))
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            // Chat history
                            if let messages = goal.chatHistory {
                                ForEach(messages) { message in
                                    ChatBubble(
                                        message: message.content,
                                        isUser: message.isUser
                                    )
                                    .id(message.id)
                                }
                            }
                            
                            // Loading indicator
                            if isProcessing {
                                HStack(spacing: 8) {
                                    ForEach(0..<3) { index in
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 8, height: 8)
                                            .scaleEffect(isProcessing ? 1.0 : 0.5)
                                            .animation(
                                                .easeInOut(duration: 0.6)
                                                .repeatForever()
                                                .delay(Double(index) * 0.2),
                                                value: isProcessing
                                            )
                                    }
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: goal.chatHistory?.count ?? 0) { _, _ in
                        withAnimation {
                            showingSuggestions = false
                            proxy.scrollTo("loading", anchor: .bottom)
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
                        
                        Button(action: {
                            Task {
                                if voiceService.isRecording {
                                    voiceService.stopRecording()
                                    messageText = voiceService.transcribedText
                                    sendMessage()
                                } else {
                                    try await voiceService.startRecording()
                                }
                            }
                        }) {
                            Image(systemName: voiceService.isRecording ? "mic.fill" : "mic")
                                .foregroundStyle(voiceService.isRecording ? .red : .secondary)
                                .font(.system(size: 18))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(messageText.isEmpty ? .gray : .blue)
                    }
                    .disabled(messageText.isEmpty || isProcessing)
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
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmed.isEmpty else { return }
        
        let userMessage = ChatMessage(content: messageText, isUser: true, goalId: goal.id)
        
        if goal.chatHistory == nil {
            goal.chatHistory = []
        }
        
        withAnimation(.cardSpring) {
            goal.chatHistory?.append(userMessage)
        }
        
        let currentMessage = messageText
        messageText = ""
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        Task {
            isProcessing = true
            
            do {
                let context = userContextService.buildContext(from: currentGoals())
                let response = try await aiService.chatWithGoal(
                    message: currentMessage,
                    goal: goal,
                    context: context
                )
                
                let aiMessage = ChatMessage(content: response, isUser: false, goalId: goal.id)
                
                withAnimation(.cardSpring) {
                    goal.chatHistory?.append(aiMessage)
                }
                
                // Update goal
                goal.updatedAt = Date()
                
                // Success haptic
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
                
            } catch {
                let errorMessage = ChatMessage(
                    content: "I couldn't process that request. Please try again.",
                    isUser: false,
                    goalId: goal.id
                )
                
                withAnimation(.cardSpring) {
                    goal.chatHistory?.append(errorMessage)
                }
                
                // Error haptic
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.error)
            }
            
            isProcessing = false
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
                    .background(
                        isUser ?
                        AnyView(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        ) :
                        AnyView(Color(.secondarySystemBackground))
                    )
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