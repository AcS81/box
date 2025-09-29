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
    @State private var showGeneralChat = false
    
    @StateObject private var voiceService = VoiceService()
    @StateObject private var userContextService = UserContextService.shared

    private var aiService: AIService {
        AIService.shared
    }
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("userPreferredName") private var userPreferredName = ""
    
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
                    
                    // Input field with voice
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                                .font(.system(size: 18))
                            
                            TextField(voiceService.isRecording ? "Listening..." : "Write a goal or tap the mic...", text: $inputText)
                                .font(.body)
                                .disabled(voiceService.isRecording)
                                .onSubmit {
                                    createGoal()
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
                                    createGoal()
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
                        
                        // General Chat Button
                        Button(action: { showGeneralChat = true }) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
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
                                if viewMode == .categoryBased && categories.count > 1 {
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showGeneralChat) {
            GeneralChatView(goals: goals)
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
        _ = await CalendarService().requestAccess()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Goal.self, ChatMessage.self, AIMirrorCard.self])
}