//
//  GeneralChatView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct GeneralChatView: View {
    let goals: [Goal]
    @ObservedObject var lifecycleService: GoalLifecycleService
    @StateObject private var voiceService = VoiceService()
    @StateObject private var userContextService = UserContextService.shared
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var isPreparingContext = false
    @State private var isRecording = false
    @FocusState private var isInputFocused: Bool
    @State private var hasFocusedInput = false
    @Query(sort: \ChatEntry.timestamp, order: .forward) private var allChatEntries: [ChatEntry]
    @State private var pendingActions: [AIAction] = []
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""
    @State private var messageDisplayLimit = 150
    private let messageDisplayBatchSize = 100
    @State private var lastMessageTime: Date?
    private let messageDebounceInterval: TimeInterval = 0.5  // 500ms debounce
    @State private var showContextReadyBanner = false
    @State private var contextReadyTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var transcriptManager: VoiceTranscriptManager

    private var aiService: AIService { AIService.shared }

    private var generalChatMessages: [ChatEntry] {
        allChatEntries.filter { $0.scope == .general }
    }

    private var displayedMessages: [ChatEntry] {
        guard generalChatMessages.count > messageDisplayLimit else { return generalChatMessages }
        return Array(generalChatMessages.suffix(messageDisplayLimit))
    }

    private var hiddenMessageCount: Int {
        max(0, generalChatMessages.count - messageDisplayLimit)
    }

    private var trimmedMessageText: String { messageText.trimmed }

    private enum InputReadiness {
        case notReady
        case ready
        case processing

        var label: String {
            switch self {
            case .notReady:
                return "Not ready"
            case .ready:
                return "Ready"
            case .processing:
                return "Sending"
            }
        }

        var color: Color {
            switch self {
            case .notReady:
                return .secondary
            case .ready:
                return .green
            case .processing:
                return .orange
            }
        }
    }

    private var inputReadiness: InputReadiness {
        if isProcessing || isPreparingContext {
            return .processing
        }

        switch userContextService.contextStatus {
        case .ready:
            return .ready
        case .idle, .preparing:
            return .notReady
        }
    }

    private var inputStatusLabel: String { inputReadiness.label }

    private var inputStatusColor: Color { inputReadiness.color }

    private var canSendMessage: Bool {
        !trimmedMessageText.isEmpty && !isProcessing && !isPreparingContext
    }

    private func loadMoreHistory() {
        guard hiddenMessageCount > 0 else { return }
        let expandedLimit = messageDisplayLimit + messageDisplayBatchSize
        messageDisplayLimit = min(expandedLimit, generalChatMessages.count)
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
                                message: "I can help you manage all your goals at once. Try:\n• 'Delete all archived goals'\n• 'Complete all goals over 90%'\n• 'Archive all completed goals'\n• 'Show me what needs attention'\n• 'Give me a weekly summary'",
                                isUser: false
                            )
                            
                            if hiddenMessageCount > 0 {
                                Button(action: loadMoreHistory) {
                                    HStack {
                                        Image(systemName: "arrow.uturn.backward")
                                        Text("Show earlier messages (\(hiddenMessageCount))")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                            }

                            ForEach(displayedMessages) { message in
                                ChatBubble(
                                    message: message.content,
                                    isUser: message.isUser
                                )
                                .id(message.id)
                            }
                            
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: generalChatMessages.count) { _, _ in
                        if let lastId = displayedMessages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        } else if isProcessing {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
                .dismissKeyboardOnTap()

                Divider()

                contextStatusBanner
                    .padding(.vertical, 6)
                
                // Input Area
                HStack(alignment: .top, spacing: 12) {
                    // Voice button
                    Button {
                        Task {
                            if isRecording {
                                await stopRecording()
                            } else {
                                await startRecording()
                            }
                        }
                    } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(isRecording ? .red : .blue)
                    }
                    .disabled(isProcessing || isPreparingContext)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Ask about your goals...", text: $messageText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.panelBackground)
                            .clipShape(Capsule())
                            .focused($isInputFocused)
                            .onSubmit {
                                sendMessage()
                            }

                        Text(inputStatusLabel)
                            .font(.caption2)
                            .foregroundStyle(inputStatusColor)
                            .padding(.leading, 18)
                    }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSendMessage ? .blue : .gray)
                    }
                    .disabled(!canSendMessage)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                guard !hasFocusedInput else { return }
                hasFocusedInput = true
                DispatchQueue.main.async {
                    isInputFocused = true
                }
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
                    Text("\(goals.count) goals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if os(iOS)
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
                #endif
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
        .onChange(of: userContextService.contextStatus) { newStatus in
            contextReadyTask?.cancel()

            switch newStatus {
            case .idle:
                withAnimation(.easeInOut(duration: 0.2)) {
                    showContextReadyBanner = false
                }
                contextReadyTask = nil
            case .preparing:
                withAnimation(.easeInOut(duration: 0.2)) {
                    showContextReadyBanner = false
                }
                contextReadyTask = nil
            case .ready:
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showContextReadyBanner = true
                }

                contextReadyTask = Task { [weak userContextService] in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if userContextService?.contextStatus.isReady ?? false {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showContextReadyBanner = false
                            }
                        }
                        contextReadyTask = nil
                    }
                }
            }
        }
        .onDisappear {
            contextReadyTask?.cancel()
            contextReadyTask = nil
        }
    }
    
    @MainActor
    private func sendMessage() {
        let trimmed = messageText.trimmed
        guard !trimmed.isEmpty else { return }
        guard !isProcessing && !isPreparingContext else { return }

        // Debounce: prevent rapid-fire messages
        if let lastTime = lastMessageTime,
           Date().timeIntervalSince(lastTime) < messageDebounceInterval {
            print("⚠️ Message debounced - too soon after last message")
            return
        }

        lastMessageTime = Date()

        // Create user entry
        let userEntry = ChatEntry(content: trimmed, isUser: true, scope: .general)
        modelContext.insert(userEntry)

        let currentMessage = trimmed
        messageText = ""

        Task { @MainActor in
            isPreparingContext = true
            isProcessing = true

            do {
                let context = await userContextService.buildContext(from: goals)

                isPreparingContext = false

                // Get structured response with actions using unified scope-based chat
                let response = try await aiService.chatWithScope(
                    message: currentMessage,
                    scope: .general,
                    history: generalChatMessages,
                    context: context
                )

                // Append AI reply
                let aiEntry = ChatEntry(content: response.reply, isUser: false, scope: .general)
                modelContext.insert(aiEntry)

                // Execute actions if present
                if !response.actions.isEmpty {
                    await executeActions(response.actions, requiresConfirmation: response.requiresConfirmation)
                }

            } catch {
                // Show specific error message instead of generic one
                let errorMessage: String
                if let aiError = error as? AIError {
                    errorMessage = "AI Error: \(aiError.errorDescription ?? "Unknown error")"
                    print("❌ AI Error: \(aiError)")
                } else if let decodingError = error as? DecodingError {
                    print("❌ JSON Decoding Error: \(decodingError)")
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        errorMessage = "Response missing '\(key.stringValue)'. Context: \(context.debugDescription)"
                    case .typeMismatch(let type, let context):
                        errorMessage = "Response type mismatch for \(type). Context: \(context.debugDescription)"
                    case .valueNotFound(let type, let context):
                        errorMessage = "Response missing value for \(type). Context: \(context.debugDescription)"
                    case .dataCorrupted(let context):
                        errorMessage = "Response data corrupted. Context: \(context.debugDescription)"
                    @unknown default:
                        errorMessage = "Unknown decoding error"
                    }
                } else {
                    errorMessage = "Error: \(error.localizedDescription)"
                    print("❌ General error: \(error)")
                }

                let errorEntry = ChatEntry(content: errorMessage, isUser: false, scope: .general)
                modelContext.insert(errorEntry)
            }

            isPreparingContext = false
            isProcessing = false
        }
    }

    @MainActor
    private func executeActions(_ actions: [AIAction], requiresConfirmation: Bool) async {
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

        do {
            let results = try await executor.executeAll(actions, modelContext: modelContext, goals: goals)

            // Show results in chat
            for result in results where result.success {
                let feedbackEntry = ChatEntry(content: "✓ \(result.message)", isUser: false, scope: .general)
                modelContext.insert(feedbackEntry)
            }

            // Show errors
            for result in results where !result.success {
                let errorEntry = ChatEntry(content: "✗ \(result.message)", isUser: false, scope: .general)
                modelContext.insert(errorEntry)
            }

        } catch {
            let errorEntry = ChatEntry(content: "✗ Action failed: \(error.localizedDescription)", isUser: false, scope: .general)
            modelContext.insert(errorEntry)

            print("❌ Action execution failed: \(error)")
        }

        pendingActions = []
    }

    private func generateConfirmationMessage(_ actions: [AIAction]) -> String {
        let actionTypes = actions.map { $0.type.rawValue }.joined(separator: ", ")
        let actionCount = actions.count
        return "Confirm \(actionCount) action\(actionCount == 1 ? "" : "s"): \(actionTypes)?"
    }

    @ViewBuilder
    private var contextStatusBanner: some View {
        switch userContextService.contextStatus {
        case .idle:
            EmptyView()
        case .preparing:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Preparing goal context…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.panelBackground)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        case .ready where showContextReadyBanner:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.green)
                Text("Context ready")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.panelBackground.opacity(0.7))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        case .ready:
            EmptyView()
        }
    }

    // MARK: - Voice Input

    @MainActor
    private func startRecording() async {
        await voiceService.startRecording()
        isRecording = true
    }

    @MainActor
    private func stopRecording() async {
        isRecording = false

        // Stop recording without goal context (general chat)
        guard case .recording = voiceService.state else { return }

        // Manually stop the recording engine
        await voiceService.stopRecordingGeneral()

        if case .error(let message) = voiceService.state {
            print("❌ Voice error: \(message)")
            voiceService.resetTranscript()
            return
        }

        let transcript = voiceService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            // Show transcript overlay
            transcriptManager.presentTranscript(goalTitle: "General Chat", text: transcript)

            // Set message text and auto-send
            messageText = transcript
            sendMessage()

            // Reset transcript for next recording
            voiceService.resetTranscript()
        }
    }
}

#Preview {
    GeneralChatView(
        goals: [],
        lifecycleService: GoalLifecycleService(
            aiService: AIService.shared,
            calendarService: CalendarService(),
            userContextService: UserContextService.shared
        )
    )
}
