//
//  GeneralChatView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

struct GeneralChatView: View {
    let goals: [Goal]
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var messages: [GeneralChatMessage] = []
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var voiceService = VoiceService()
    @StateObject private var userContextService = UserContextService.shared

    private var aiService: AIService { AIService.shared }
    
    struct GeneralChatMessage: Identifiable {
        let id = UUID()
        let content: String
        let isUser: Bool
        let timestamp = Date()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // Welcome message
                            ChatBubble(
                                message: "I can help you manage all your goals at once. Try:\n• 'Reorder by urgency'\n• 'Show me what needs attention'\n• 'Archive completed goals'\n• 'Give me a weekly summary'",
                                isUser: false
                            )
                            
                            ForEach(messages) { message in
                                ChatBubble(
                                    message: message.content,
                                    isUser: message.isUser
                                )
                                .id(message.id)
                            }
                            
                            if isProcessing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            if let lastId = messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            } else {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input Area
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Ask about your goals...", text: $messageText)
                            .textFieldStyle(.plain)
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
                                .foregroundStyle(voiceService.isRecording ? .red : .blue)
                                .font(.system(size: 18))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                    }
                    .disabled(messageText.isEmpty || isProcessing)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("General Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                        Text("\(goals.count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmed.isEmpty else { return }

        let userMessage = GeneralChatMessage(content: messageText, isUser: true)
        withAnimation(.cardSpring) {
            messages.append(userMessage)
        }

        let currentMessage = messageText
        messageText = ""

        Task {
            isProcessing = true

            do {
                let context = userContextService.buildContext(from: goals)

                // Determine the type of request and route to appropriate AI function
                let response: String
                if isReorderRequest(currentMessage) {
                    let reorderResponse = try await aiService.reorderCards(goals, instruction: currentMessage, context: context)
                    response = reorderResponse.reasoning
                    // Apply reordering
                    await applyReorderChanges(reorderResponse)
                } else {
                    // General management request
                    response = try await aiService.chatWithGoal(
                        message: currentMessage,
                        goal: goals.first ?? Goal(title: "General"),
                        context: context
                    )
                }

                withAnimation(.cardSpring) {
                    let aiMessage = GeneralChatMessage(content: response, isUser: false)
                    messages.append(aiMessage)
                }

                print("🤖 General chat response: \(response)")

            } catch {
                withAnimation(.cardSpring) {
                    let errorMessage = GeneralChatMessage(
                        content: "I couldn't process that request. Please try again.",
                        isUser: false
                    )
                    messages.append(errorMessage)
                }
                print("❌ General chat error: \(error)")
            }

            isProcessing = false
        }
    }

    private func isReorderRequest(_ message: String) -> Bool {
        let reorderKeywords = ["reorder", "sort", "organize", "arrange", "prioritize"]
        let lowercaseMessage = message.lowercased()
        return reorderKeywords.contains { lowercaseMessage.contains($0) }
    }

    private func applyReorderChanges(_ response: GoalReorderResponse) async {
        await MainActor.run {
            // Update goal priorities or order based on AI response
            // This is a simplified implementation
            for (index, goalId) in response.reorderedGoals.enumerated() {
                if let goal = goals.first(where: { $0.id.uuidString == goalId }) {
                    // Adjust priority based on position
                    switch index {
                    case 0...2:
                        goal.priority = .now
                    case 3...6:
                        goal.priority = .next
                    default:
                        goal.priority = .later
                    }
                    goal.updatedAt = Date()
                }
            }

            print("🔄 Applied reordering to \(response.reorderedGoals.count) goals")
        }
    }
    
    private func processAIResponse(_ response: String) {
        // This function is no longer needed as we handle responses in sendMessage
        // Legacy function kept for compatibility
    }
}

#Preview {
    GeneralChatView(goals: [])
}
