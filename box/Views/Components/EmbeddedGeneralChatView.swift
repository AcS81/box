import SwiftUI
import SwiftData

struct EmbeddedGeneralChatView: View {
    let goals: [Goal]
    @ObservedObject var lifecycleService: GoalLifecycleService
    @Binding var focusTrigger: Bool
    @Query(
        sort: [SortDescriptor(\ChatEntry.timestamp, order: .reverse)]
    ) private var chatEntries: [ChatEntry]
    @Environment(\.modelContext) private var modelContext

    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var isRecording = false
    @FocusState private var isComposerFocused: Bool

    @ObservedObject private var userContextService = UserContextService.shared
    @StateObject private var voiceService = VoiceService()
    @EnvironmentObject private var transcriptManager: VoiceTranscriptManager

    private var aiService: AIService { AIService.shared }

    private var visibleMessages: [ChatEntry] {
        Array(generalChatEntries.prefix(3).reversed())
    }

    private var generalChatEntries: [ChatEntry] {
        chatEntries.filter { $0.scope == .general }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assistant")
                        .font(.handDrawn(size: 26, weight: .bold))
                        .foregroundStyle(Color.paperSpeck)
                    Text("Ask about all goals, bulk-manage, or get insights")
                        .font(.subheadline)
                        .foregroundStyle(Color.paperLine.opacity(0.85))
                }
                Spacer()
                if isProcessing { ProgressView().controlSize(.small) }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ChatBubble(
                            message: "Hi! I can help manage your whole board. Try: 'Archive all completed', 'What's overdue?', or 'Reorder by priority'.",
                            isUser: false
                        )

                        ForEach(visibleMessages) { message in
                            ChatBubble(message: message.content, isUser: message.isUser)
                                .id(message.id)
                        }

                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .id("loading")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: generalChatEntries.count) { _, _ in
                    if let last = visibleMessages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    } else if isProcessing {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 12) {
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
                .disabled(isProcessing)

                TextField("Ask or command across all goals…", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit { submit() }
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(messageText.trimmed.isEmpty || isProcessing ? .gray : .blue)
                }
                .disabled(messageText.trimmed.isEmpty || isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.paperDeep.opacity(0.25))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.paperSpeck.opacity(0.55), lineWidth: 1.2)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .padding(24)
        .paperCard(cornerRadius: 28)
        .onChange(of: focusTrigger) { _, newValue in
            guard newValue else { return }
            DispatchQueue.main.async {
                isComposerFocused = true
                focusTrigger = false
            }
        }
    }

    @MainActor
    private func submit() {
        let trimmed = messageText.trimmed
        guard !trimmed.isEmpty else { return }

        let userEntry = ChatEntry(content: trimmed, isUser: true, scope: .general)
        modelContext.insert(userEntry)

        let current = trimmed
        withAnimation { messageText = "" }
        isComposerFocused = false

        Task { @MainActor in
            isProcessing = true
            do {
                let context = await userContextService.buildContext(from: goals)

                let history = Array(generalChatEntries.reversed())
                let response = try await aiService.chatWithScope(
                    message: current,
                    scope: .general,
                    history: history,
                    context: context
                )

                let aiEntry = ChatEntry(content: response.reply, isUser: false, scope: .general)
                modelContext.insert(aiEntry)

                if !response.actions.isEmpty {
                    let executor = AIActionExecutor(
                        lifecycleService: lifecycleService,
                        aiService: aiService,
                        userContextService: userContextService
                    )
                    do {
                        let results = try await executor.executeAll(response.actions, modelContext: modelContext, goals: goals)
                        for result in results where result.success {
                            modelContext.insert(ChatEntry(content: "✓ \(result.message)", isUser: false, scope: .general))
                        }
                        for result in results where !result.success {
                            modelContext.insert(ChatEntry(content: "✗ \(result.message)", isUser: false, scope: .general))
                        }
                    } catch {
                        modelContext.insert(ChatEntry(content: "✗ Action failed: \(error.localizedDescription)", isUser: false, scope: .general))
                    }
                }
            } catch {
                modelContext.insert(ChatEntry(content: "I couldn't process that request. Please try again.", isUser: false, scope: .general))
            }

            isProcessing = false
        }
    }

    @MainActor
    private func startRecording() async {
        guard !isProcessing else { return }
        await voiceService.startRecording()
        isRecording = true
    }

    @MainActor
    private func stopRecording() async {
        guard isRecording else { return }
        isRecording = false

        await voiceService.stopRecordingGeneral()

        if case .error(let message) = voiceService.state {
            print("❌ Voice error: \(message)")
            voiceService.resetTranscript()
            return
        }

        let transcript = voiceService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        transcriptManager.presentTranscript(goalTitle: "Assistant", text: transcript)
        messageText = transcript
        submit()
        voiceService.resetTranscript()
    }
}



