//
//  ContentView.swift
//  box
//
//  Created by AcS on 29.09.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var goals: [Goal]
    
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var showMirrorMode = false
    @State private var viewMode: ViewMode = .timeBased
    @State private var selectedCategory: String? = nil
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedGoal: Goal? = nil
    @State private var chatMode: ChatMode = .createGoal

    enum ChatMode {
        case createGoal
        case chatWithGoal(Goal)
        case generalManagement

        var placeholder: String {
            switch self {
            case .createGoal:
                return "Write a goal or tap the mic..."
            case .chatWithGoal(let goal):
                return "Chat with \(goal.title)..."
            case .generalManagement:
                return "Ask about your goals..."
            }
        }

        var icon: String {
            switch self {
            case .createGoal:
                return "sparkles"
            case .chatWithGoal:
                return "bubble.left"
            case .generalManagement:
                return "wand.and.stars"
            }
        }

        func isEqual(to other: ChatMode) -> Bool {
            switch (self, other) {
            case (.createGoal, .createGoal), (.generalManagement, .generalManagement):
                return true
            case (.chatWithGoal(let goal1), .chatWithGoal(let goal2)):
                return goal1.id == goal2.id
            default:
                return false
            }
        }
    }
    
    @StateObject private var voiceService = VoiceService()
    @StateObject private var userContextService = UserContextService.shared
    @StateObject private var calendarService: CalendarService
    @StateObject private var lifecycleService: GoalLifecycleService

    private var aiService: AIService {
        AIService.shared
    }
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("userPreferredName") private var userPreferredName = ""

    init() {
        let calendarService = CalendarService()
        _calendarService = StateObject(wrappedValue: calendarService)
        _lifecycleService = StateObject(
            wrappedValue: GoalLifecycleService(
                aiService: AIService.shared,
                calendarService: calendarService,
                userContextService: UserContextService.shared
            )
        )
    }
    
    enum ViewMode: String, CaseIterable {
        case timeBased = "Time"
        case categoryBased = "Folders"
        
        var icon: String {
            switch self {
            case .timeBased: return "clock.fill"
            case .categoryBased: return "folder.fill"
            }
        }
    }
    
    var filteredGoals: [Goal] {
        let baseGoals = goals.filter { $0.parent == nil }
        
        switch viewMode {
        case .timeBased:
            return baseGoals.sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return priorityOrder(lhs.priority) < priorityOrder(rhs.priority)
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .categoryBased:
            if let category = selectedCategory {
                return baseGoals.filter { $0.category == category }
            }
            return baseGoals
        }
    }
    
    var categories: [String] {
        Array(Set(goals.map { $0.category })).sorted()
    }

    var shouldShowCategoryFilter: Bool {
        // Only show category filter if we have multiple categories and enough goals
        let categoryCount = categories.count
        let totalGoals = goals.count

        // Show folders only if:
        // - More than 1 category exists
        // - At least 4 goals total (minimum to make folders useful)
        // - Not more categories than goals/2 (avoid too many empty folders)
        return categoryCount > 1 && totalGoals >= 4 && categoryCount <= max(2, totalGoals / 2)
    }
    
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = userPreferredName.isEmpty ? "" : ", \(userPreferredName)"
        
        switch hour {
        case 0..<12:
            return "Good morning\(name)"
        case 12..<17:
            return "Good afternoon\(name)"
        default:
            return "Good evening\(name)"
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: colorScheme == .dark ? 
                    [Color.black, Color(white: 0.1)] : 
                    [Color(white: 0.98), Color(white: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with chat input
                VStack(spacing: 16) {
                    // App title and settings
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(greeting)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Text("Speak or type your goal to create an intelligent card")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Contextual input field with voice
                    VStack(spacing: 8) {
                        // Chat mode selector
                        if !goals.isEmpty {
                            HStack(spacing: 8) {
                                Button(action: { chatMode = .createGoal }) {
                                    Text("Create")
                                        .font(.caption)
                                        .fontWeight(chatMode == .createGoal ? .semibold : .medium)
                                        .foregroundStyle(chatMode == .createGoal ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(chatMode == .createGoal ? Color.blue : Color.clear)
                                        .clipShape(Capsule())
                                }

                                Button(action: { chatMode = .generalManagement }) {
                                    Text("Manage")
                                        .font(.caption)
                                        .fontWeight(chatMode == .generalManagement ? .semibold : .medium)
                                        .foregroundStyle(chatMode == .generalManagement ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(chatMode == .generalManagement ? Color.green : Color.clear)
                                        .clipShape(Capsule())
                                }

                                if let selectedGoal = selectedGoal {
                                    Button(action: { chatMode = .chatWithGoal(selectedGoal) }) {
                                        Text("Chat with \(selectedGoal.title.prefix(10))...")
                                            .font(.caption)
                                            .fontWeight(chatMode.isEqual(to: .chatWithGoal(selectedGoal)) ? .semibold : .medium)
                                            .foregroundStyle(chatMode.isEqual(to: .chatWithGoal(selectedGoal)) ? .white : .primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .background(chatMode.isEqual(to: .chatWithGoal(selectedGoal)) ? Color.purple : Color.clear)
                                            .clipShape(Capsule())
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: chatMode.icon)
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 18))

                                TextField(voiceService.isRecording ? "Listening..." : chatMode.placeholder, text: $inputText)
                                    .font(.body)
                                    .disabled(voiceService.isRecording)
                                    .onSubmit {
                                        handleInput()
                                    }

                                if isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                        
                            // Voice button
                            Button(action: {
                                Task {
                                    if voiceService.isRecording {
                                        voiceService.stopRecording()
                                        inputText = voiceService.transcribedText
                                        handleInput()
                                    } else {
                                        try await voiceService.startRecording()
                                    }
                                }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(voiceService.isRecording ? Color.red : Color.blue)
                                    .frame(width: 48, height: 48)
                                
                                Image(systemName: voiceService.isRecording ? "mic.fill" : "mic")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 20))
                            }
                        }
                        .scaleEffect(voiceService.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: voiceService.isRecording)
                        .accessibilityLabel(voiceService.isRecording ? "Stop recording" : "Start voice recording")
                        .accessibilityHint("Double tap to \(voiceService.isRecording ? "stop recording and create goal" : "start recording your goal with voice")")
                        .accessibilityAddTraits(.isButton)
                    }
                    .padding(.horizontal)
                    
                    // View mode selector
                    HStack(spacing: 16) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Button(action: { 
                                withAnimation(.smoothSpring) {
                                    viewMode = mode
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 14))
                                    Text(mode.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(viewMode == mode ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    viewMode == mode ? 
                                    Color.blue : 
                                    Color.clear
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    viewMode != mode ?
                                    Capsule()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1) :
                                    nil
                                )
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(.ultraThinMaterial)
                
                // Main content area
                ZStack {
                    if showMirrorMode {
                        MirrorModeView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        ScrollView {
                            VStack(spacing: 20) {
                                if viewMode == .categoryBased && shouldShowCategoryFilter {
                                    CategoryFilterView(
                                        categories: categories,
                                        selectedCategory: $selectedCategory
                                    )
                                    .padding(.horizontal)
                                }
                                
                                if goals.isEmpty {
                                    EmptyStateView()
                                        .padding(.top, 60)
                                } else if viewMode == .timeBased {
                                    TimeBasedGoalsView(goals: filteredGoals)
                                } else {
                                    CategoryGoalsView(goals: filteredGoals)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.bottom, 100)
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            // Bottom bar with Mirror Mode toggle
            VStack {
                Spacer()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showMirrorMode ? "AI Understanding" : "Your Goals")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(showMirrorMode ? "How AI sees your goals" : "\(goals.count) active goals")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Mirror Mode Toggle
                    Button(action: {
                        withAnimation(.smoothSpring) {
                            showMirrorMode.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: showMirrorMode ? "brain" : "person.fill")
                                .font(.system(size: 14))
                            Text(showMirrorMode ? "AI Mode" : "User Mode")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(showMirrorMode ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if showMirrorMode {
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .environmentObject(lifecycleService)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
        .task {
            await requestPermissions()
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }
    
    private func handleInput() {
        guard !inputText.trimmed.isEmpty else { return }

        switch chatMode {
        case .createGoal:
            createGoal()
        case .chatWithGoal(let goal):
            chatWithGoal(goal)
        case .generalManagement:
            handleGeneralManagement()
        }
    }

    private func chatWithGoal(_ goal: Goal) {
        let message = inputText.trimmed
        inputText = ""

        withAnimation(.cardSpring) {
            isProcessing = true
        }

        Task {
            do {
                let context = userContextService.buildContext(from: goals)
                let response = try await aiService.processUnifiedMessage(message, goal: goal, context: context)

                await MainActor.run {
                    // Handle any lifecycle intents
                    if let intent = response.intent {
                        handleLifecycleIntent(intent, response: response)
                    }

                    // Show AI response (this could be integrated into chat history)
                    print("🤖 AI Response: \(response.message)")

                    if response.requiresConfirmation {
                        print("⚠️ Action requires confirmation")
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Chat error: \(error)")
                }
            }

            await MainActor.run {
                withAnimation(.cardSpring) {
                    isProcessing = false
                }
            }
        }
    }

    private func handleGeneralManagement() {
        let message = inputText.trimmed
        inputText = ""

        withAnimation(.cardSpring) {
            isProcessing = true
        }

        Task {
            do {
                let context = userContextService.buildContext(from: goals)
                let response = try await aiService.processUnifiedMessage(message, context: context)

                await MainActor.run {
                    // Handle any lifecycle intents
                    if let intent = response.intent {
                        handleLifecycleIntent(intent, response: response)
                    }

                    // Show AI response
                    print("🛠️ Management Response: \(response.message)")
                }
            } catch {
                await MainActor.run {
                    print("❌ Management error: \(error)")
                }
            }

            await MainActor.run {
                withAnimation(.cardSpring) {
                    isProcessing = false
                }
            }
        }
    }

    private func handleLifecycleIntent(_ intent: LifecycleIntent, response: UnifiedChatResponse) {
        Task {
            do {
                switch intent {
                case .delete(let goal):
                    if response.requiresConfirmation {
                        // For now, just execute - in a full implementation, you'd show a confirmation dialog
                        print("🗑️ Deleting goal: \(goal.title)")
                    }
                    try await lifecycleService.delete(goal: goal, within: goals, modelContext: modelContext)

                case .complete(let goal):
                    print("✅ Completing goal: \(goal.title)")
                    await lifecycleService.complete(goal: goal, within: goals, modelContext: modelContext)

                case .edit(let goal, let changes):
                    print("✏️ Editing goal: \(goal.title)")
                    lifecycleService.updateGoal(
                        goal,
                        title: changes.title,
                        content: changes.content,
                        category: changes.category,
                        priority: changes.priority
                    )
                }

                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            } catch {
                print("❌ Failed to execute lifecycle action: \(error)")
            }
        }
    }

    private func createGoal() {
        guard !inputText.trimmed.isEmpty else { return }

        let goalText = inputText.trimmed
        inputText = ""

        withAnimation(.cardSpring) {
            isProcessing = true
        }

        Task {
            do {
                // Build context from existing goals
                let context = userContextService.buildContext(from: goals)

                print("🤖 Creating goal with context: \(context.contextSummary)")

                // Use the new AI service with structured response
                let response = try await aiService.createGoal(from: goalText, context: context)

                // Create goal with AI-enhanced data
                let priority = Goal.Priority(rawValue: response.priority) ?? .next
                let newGoal = Goal(
                    title: response.title,
                    content: response.content,
                    category: response.category,
                    priority: priority
                )

                await MainActor.run {
                    withAnimation(.cardSpring) {
                        modelContext.insert(newGoal)
                    }
                }

                // Generate mirror card with AI analysis
                let mirrorResponse = try await aiService.generateMirrorCard(for: newGoal, context: context)
                let mirrorCard = AIMirrorCard(
                    title: newGoal.title,
                    interpretation: mirrorResponse.aiInterpretation,
                    relatedGoalId: newGoal.id
                )
                mirrorCard.suggestedActions = mirrorResponse.suggestedActions
                mirrorCard.confidence = mirrorResponse.confidence

                await MainActor.run {
                    modelContext.insert(mirrorCard)
                }

                // Create suggested subgoals if provided
                if !response.suggestedSubgoals.isEmpty {
                    for subgoalTitle in response.suggestedSubgoals.prefix(3) {
                        let subgoal = Goal(
                            title: subgoalTitle,
                            content: "Sub-goal of: \(newGoal.title)",
                            category: newGoal.category,
                            priority: .later
                        )
                        subgoal.parent = newGoal

                        await MainActor.run {
                            modelContext.insert(subgoal)
                        }
                    }
                }

                print("🎯 Goal created: \(response.title)")
                print("📊 Difficulty: \(response.difficulty ?? "Unknown")")
                print("⏱️ Estimated duration: \(response.estimatedDuration ?? "Unknown")")

                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()

            } catch {
                print("❌ Failed to create goal with AI: \(error)")

                // Fallback: create a basic goal even if AI fails
                let newGoal = Goal(title: goalText)

                await MainActor.run {
                    withAnimation(.cardSpring) {
                        modelContext.insert(newGoal)
                    }
                }

                // Create a basic mirror card
                let mirrorCard = AIMirrorCard(
                    title: goalText,
                    interpretation: "Goal created without AI analysis",
                    relatedGoalId: newGoal.id
                )

                await MainActor.run {
                    modelContext.insert(mirrorCard)
                }
            }

            await MainActor.run {
                withAnimation(.cardSpring) {
                    isProcessing = false
                }
            }
        }
    }
    
    private func priorityOrder(_ priority: Goal.Priority) -> Int {
        switch priority {
        case .now: return 0
        case .next: return 1
        case .later: return 2
        }
    }
    
    private func requestPermissions() async {
        voiceService.requestAuthorization()
        _ = await calendarService.requestAccess()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Goal.self, ChatMessage.self, AIMirrorCard.self, GoalSnapshot.self, GoalRevision.self, ScheduledEventLink.self])
}