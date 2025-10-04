import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.updatedAt, order: .reverse) private var goals: [Goal]

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @StateObject private var lifecycleService = GoalLifecycleService(
        aiService: AIService.shared,
        calendarService: CalendarService(),
        userContextService: UserContextService.shared
    )

    @StateObject private var toastManager = ProactiveToastManager()
    @StateObject private var proactiveService = ProactiveAIService.shared
    @StateObject private var autopilotService = AutopilotService.shared
    @StateObject private var transcriptManager = VoiceTranscriptManager()

    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedTab: MainTab = .chat
    @State private var goalsLayout: GoalsLayout = .gantt
    @State private var statusFocus: StatusFocus = .active
    @State private var isRefreshing = false
    @State private var chatFocusTrigger = false
    @State private var splashPhase: SplashPhase = .idle
    @State private var isAppReady = false
    @State private var hasPreloaded = false

    var body: some View {
        ZStack {
            Group {
                if hasCompletedOnboarding && isAppReady {
                    mainInterface
                        .voiceTranscriptOverlay(manager: transcriptManager)
                } else if hasCompletedOnboarding {
                    mainInterface.hidden()
                } else {
                    onboarding
                }
            }

            if hasCompletedOnboarding, !isAppReady {
                SplashScreen(
                    phase: $splashPhase,
                    onReadyToUnlock: {
                        await enterApp()
                    }
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
        .environmentObject(lifecycleService)
        .environmentObject(transcriptManager)
        .proactiveToast(manager: toastManager)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            }
        }
        .task(id: hasCompletedOnboarding) {
            guard hasCompletedOnboarding, !hasPreloaded else { return }
            await preloadApp()
        }
    }
}

private extension ContentView {
    var mainInterface: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                chatTabView
                    .navigationTitle("Chat")
                    .toolbar { commandToolbar }
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.fill")
            }
            .tag(MainTab.chat)

            NavigationStack {
                timelineTabView
                    .navigationTitle("Timeline")
                    .toolbar { commandToolbar }
            }
            .tabItem {
                Label("Timeline", systemImage: "calendar.badge.clock")
            }
            .tag(MainTab.timeline)

            NavigationStack {
                categoriesTabView
                    .navigationTitle("Categories")
                    .toolbar { goalToolbar }
                    .searchable(text: $searchText, prompt: "Search goals")
            }
            .tabItem {
                Label("Categories", systemImage: "folder.fill")
            }
            .tag(MainTab.categories)
        }
    }

    // MARK: - Splash & Preload
    
    func preloadApp() async {
        guard splashPhase == .idle else { return }
        
        // Start loading animation
        await MainActor.run {
            splashPhase = .loading
        }
        
        // Minimum animation time for smoothness
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        // Do all the heavy preloading here
        let goalsSnapshot = Array(goals)
        
        // Generate daily insights
        await proactiveService.generateDailyInsights(from: goalsSnapshot)
        
        // Process autopilot goals
        await autopilotService.processAutopilotGoals(goalsSnapshot, modelContext: modelContext)
        
        // Mark as preloaded
        await MainActor.run {
            hasPreloaded = true
        }
        
        // Wait for current bounce to complete
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // Move to ready phase (ball settles, START button shows)
        await MainActor.run {
            splashPhase = .readyToStart
        }
    }
    
    func enterApp() async {
        // User tapped START button
        guard !isAppReady else { return }
        
        // Gate animation plays, then enter
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.4)) {
                isAppReady = true
            }
            splashPhase = .completed
            chatFocusTrigger = true
        }
        
        // Start ongoing services now that user is in
        autopilotService.startMonitoring()
        lifecycleService.startScheduleMaintenance(
            goalsProvider: {
                let descriptor = FetchDescriptor<Goal>()
                return (try? modelContext.fetch(descriptor)) ?? []
            },
            modelContext: modelContext
        )
    }

    var chatTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                EmbeddedGeneralChatView(
                    goals: goals,
                    lifecycleService: lifecycleService,
                    focusTrigger: $chatFocusTrigger
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .linedPaperBackground(spacing: 44, marginX: 64)
        .onDisappear {
            autopilotService.stopMonitoring()
            lifecycleService.stopScheduleMaintenance()
        }
    }

    var timelineTabView: some View {
        StopsTimelineView(goals: Array(goals))
    }

    var categoriesTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                GoalCategoryGridView(
                    goals: filteredGoals,
                    selectedCategory: $selectedCategory
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .linedPaperBackground(spacing: 44, marginX: 64)
    }

    var goalsWorkspaceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                workspacePicker

                Group {
                    switch goalsLayout {
                    case .gantt:
                        if filteredGoals.isEmpty {
                            EmptyStateView()
                                .padding(.top, 20)
                        } else {
                            GoalsTimelineView(goals: filteredGoals)
                        }
                    case .categories:
                        GoalCategoryGridView(
                            goals: filteredGoals,
                            selectedCategory: $selectedCategory
                        )
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(sceneBackground)
    }

    var mirrorModeView: some View {
        MirrorModeView()
            .background(sceneBackground)
    }

    var statusOverviewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Board Health")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("Updated \(Date().shortTime)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatusMetricCard(
                    title: "Active",
                    value: "\(activeGoals.count)",
                    caption: "In motion",
                    systemImage: "bolt.fill",
                    tint: .green
                )

                StatusMetricCard(
                    title: "Drafts",
                    value: "\(draftGoals.count)",
                    caption: "Awaiting activation",
                    systemImage: "tray.full.fill",
                    tint: .orange
                )

                StatusMetricCard(
                    title: "Completed",
                    value: "\(completedGoals.count)",
                    caption: "Momentum wins",
                    systemImage: "checkmark.seal.fill",
                    tint: .blue
                )

                StatusMetricCard(
                    title: "Average Progress",
                    value: "\(Int(averageProgress * 100))%",
                    caption: "Across all goals",
                    systemImage: "chart.bar.fill",
                    tint: .purple
                )
            }
        }
    }

    var statusFocusSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Spotlight")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StatusFocus.allCases) { focus in
                        Button {
                            withAnimation(.smoothSpring) {
                                statusFocus = focus
                            }
                        } label: {
                            LiquidPickerSegment(
                                title: focus.title,
                                subtitle: focus.subtitle(for: goals(for: focus).count),
                                systemImage: focus.systemImage,
                                isSelected: focus == statusFocus,
                                tint: focus.tint
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            let spotlightGoals = goals(for: statusFocus).prefix(3)
            if spotlightGoals.isEmpty {
                Text("No goals in this state yet. Try creating or activating one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(spotlightGoals.enumerated()), id: \.offset) { index, goal in
                        GoalQuickRow(goal: goal, accent: statusFocus.tint, index: index + 1)
                    }
                }
            }
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 32, tint: statusFocus.tint.opacity(0.28))
    }

    var timelineHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Goal Horizons")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Horizon.allCases, id: \.self) { horizon in
                        HorizonCard(
                            horizon: horizon,
                            goals: goals(for: horizon)
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    var proactiveInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Smart Insights")
                .font(.title3)
                .fontWeight(.semibold)

            ProactiveInsightsView(
                proactiveService: proactiveService,
                onActionTapped: { action, goalId in
                    handleProactiveAction(action, goalId: goalId)
                }
            )
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 30, tint: Color.purple.opacity(0.28))
    }

    var workspacePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workspace")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GoalsLayout.allCases) { layout in
                        Button {
                            withAnimation(.smoothSpring) {
                                goalsLayout = layout
                            }
                        } label: {
                            LiquidPickerSegment(
                                title: layout.title,
                                subtitle: layout.subtitle,
                                systemImage: layout.systemImage,
                                isSelected: goalsLayout == layout,
                                tint: layout.tint
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    var sceneBackground: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.08),
                Color.purple.opacity(0.05),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var onboarding: some View {
        OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            .frame(minWidth: 640, minHeight: 520)
            .background(sceneBackground)
    }

    @ToolbarContentBuilder
    var commandToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            refreshButton
            settingsButton
        }
    }

    @ToolbarContentBuilder
    var goalToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            refreshButton
            settingsButton
        }
    }

    var refreshButton: some View {
        Button {
            Task { await refreshAllActiveGoals() }
        } label: {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(isRefreshing)
    }

    var settingsButton: some View {
        Button {
            activeSheet = .settings
        } label: {
            Image(systemName: "gearshape")
        }
    }

    var filteredGoals: [Goal] {
        var result = topLevelGoals

        let query = searchText.trimmed.lowercased()
        if !query.isEmpty {
            result = result.filter { goal in
                matchesSearch(goal, query: query)
            }
        }

        return result.sorted { lhs, rhs in
            let lhsOrder = lhs.effectiveSortOrder
            let rhsOrder = rhs.effectiveSortOrder
            if lhsOrder == rhsOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhsOrder < rhsOrder
        }
    }

    func goals(for focus: StatusFocus) -> [Goal] {
        switch focus {
        case .active: return activeGoals
        case .draft: return draftGoals
        case .completed: return completedGoals
        }
    }

    func goals(for horizon: Horizon) -> [Goal] {
        switch horizon {
        case .short:
            return topLevelGoals.filter { $0.priority == .now }
        case .medium:
            return topLevelGoals.filter { $0.priority == .next }
        case .long:
            return topLevelGoals.filter { $0.priority == .later }
        }
    }

    func goals(forCategory category: String) -> [Goal] {
        let lowered = category.lowercased()
        var result = topLevelGoals.filter { $0.category.lowercased() == lowered }

        let query = searchText.trimmed.lowercased()
        if !query.isEmpty {
            result = result.filter { matchesSearch($0, query: query) }
        }

        return result.sorted { lhs, rhs in
            if lhs.effectiveSortOrder == rhs.effectiveSortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.effectiveSortOrder < rhs.effectiveSortOrder
        }
    }

    var activeGoals: [Goal] {
        topLevelGoals.filter { $0.activationState == .active }
    }

    var draftGoals: [Goal] {
        topLevelGoals.filter { $0.activationState == .draft }
    }

    var completedGoals: [Goal] {
        topLevelGoals.filter { $0.activationState == .completed }
    }

    var averageProgress: Double {
        guard !topLevelGoals.isEmpty else { return 0 }
        let total = topLevelGoals.reduce(0) { $0 + $1.progress }
        return total / Double(topLevelGoals.count)
    }

    var topLevelGoals: [Goal] {
        goals
            .filter { $0.parent == nil }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.effectiveSortOrder
                let rhsOrder = rhs.effectiveSortOrder
                if lhsOrder == rhsOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhsOrder < rhsOrder
            }
    }

    @MainActor
    private func executeProactiveBreakdown(for goal: Goal, reason: String) async {
        // Check if already broken down OR already has subgoals
        guard !goal.hasBeenBrokenDown else {
            print("ℹ️ Goal '\(goal.title)' already broken down, skipping")
            return
        }

        // NEW: Also skip if goal already has subgoals (from initial creation)
        if let existingSubgoals = goal.subgoals, !existingSubgoals.isEmpty {
            goal.hasBeenBrokenDown = true // Mark to prevent future attempts
            goal.updatedAt = Date()
            print("ℹ️ Goal '\(goal.title)' already has \(existingSubgoals.count) subgoal(s), skipping proactive breakdown")
            return
        }

        do {
            let goalsSnapshot = Array(goals)
            let context = await UserContextService.shared.buildContext(from: goalsSnapshot)
            let response = try await AIService.shared.breakdownGoal(goal, context: context)

            let breakdown = GoalBreakdownBuilder.apply(response: response, to: goal, in: modelContext)
            let atomicCount = max(breakdown.atomicTaskCount, breakdown.createdGoals.count)

            // Mark as broken down to prevent duplicates
            goal.hasBeenBrokenDown = true
            goal.updatedAt = Date()

            // Show feedback
            showProactiveToast(
                message: "✨ Created \(atomicCount) atomic step\(atomicCount == 1 ? "" : "s") for '\(goal.title)'\(breakdown.dependencyCount > 0 ? " and mapped \(breakdown.dependencyCount) dependency link\(breakdown.dependencyCount == 1 ? "" : "s")" : "")",
                type: .success
            )

            // Haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            print("🤖 Proactive breakdown: Created \(response.subtasks.count) subtasks for '\(goal.title)'")

        } catch {
            print("❌ Proactive breakdown failed: \(error)")
        }
    }

    @MainActor
    private func suggestActivation(for goal: Goal, reason: String) async {
        // Auto-activate high-priority goals
        showProactiveToast(
            message: "⏳ Activating '\(goal.title)'...",
            type: .working
        )

        do {
            let goalsSnapshot = Array(goals)
            let plan = try await lifecycleService.generateActivationPlan(for: goal, within: goalsSnapshot)

            // Auto-confirm activation with generated plan
            try await lifecycleService.confirmActivation(
                goal: goal,
                plan: plan,
                within: goalsSnapshot,
                modelContext: modelContext
            )

            showProactiveToast(
                message: "✓ Activated '\(goal.title)' with \(plan.events.count) session\(plan.events.count == 1 ? "" : "s")",
                type: .success
            )

            // Success haptic
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            print("🤖 Proactive activation: Scheduled \(plan.events.count) sessions for '\(goal.title)'")

        } catch {
            showProactiveToast(
                message: "Couldn't auto-activate. Try manually.",
                type: .info
            )
            print("❌ Proactive activation failed: \(error)")
        }
    }

    @MainActor
    private func showProactiveToast(message: String, type: ProactiveActionToast.ToastType = .success) {
        toastManager.show(message: message, type: type)
        print("🔔 Proactive: \(message)")
    }

    @MainActor
    private func generateDailyInsights() async {
        let goalsSnapshot = Array(goals)
        await proactiveService.generateDailyInsights(from: goalsSnapshot)

        // Note: Progress updates are now handled by AutopilotService automatically
    }

    @MainActor
    private func handleProactiveAction(_ action: ProactiveInsightAction, goalId: UUID?) {
        Task {
            switch action.type {
            case "breakdown":
                if let goalId, let goal = goals.first(where: { $0.id == goalId }) {
                    await executeProactiveBreakdown(for: goal, reason: "From insight")
                }

            case "reschedule":
                if let goalId, let goal = goals.first(where: { $0.id == goalId }) {
                    // Try to reactivate with new schedule
                    await suggestActivation(for: goal, reason: "Rescheduling stagnant goal")
                }

            case "archive":
                if let goalId, let goal = goals.first(where: { $0.id == goalId }) {
                    goal.deactivate(to: .archived, rationale: "Archived from insight")
                    showProactiveToast(message: "✓ Archived '\(goal.title)'", type: .success)
                }

            case "bulk_complete":
                let nearComplete = goals.filter { $0.progress >= 0.8 && $0.progress < 1.0 }
                for goal in nearComplete {
                    let goalsSnapshot = Array(goals)
                    await lifecycleService.complete(goal: goal, within: goalsSnapshot, modelContext: modelContext)
                }
                showProactiveToast(message: "🎉 Completed \(nearComplete.count) goals!", type: .success)

            case "activate_all":
                let nowGoals = goals.filter { $0.priority == .now && $0.activationState != .active }
                for goal in nowGoals {
                    await suggestActivation(for: goal, reason: "Batch activation")
                }

            default:
                print("⚠️ Unknown action type: \(action.type)")
            }
        }
    }

    func matchesSearch(_ goal: Goal, query: String) -> Bool {
        if goal.title.lowercased().contains(query) || goal.content.lowercased().contains(query) {
            return true
        }

        return goal.subgoals?.contains(where: { matchesSubgoal($0, query: query) }) ?? false
    }

    func matchesSubgoal(_ subgoal: Goal, query: String) -> Bool {
        if subgoal.title.lowercased().contains(query) || subgoal.content.lowercased().contains(query) {
            return true
        }

        return subgoal.subgoals?.contains(where: { matchesSubgoal($0, query: query) }) ?? false
    }

    @MainActor
    func refreshAllActiveGoals() async {
        guard !isRefreshing else { return }

        isRefreshing = true

        // Show initial feedback
        showProactiveToast(message: "Refreshing all active goals...", type: .working)

        // Run autopilot pass on all goals
        await autopilotService.processAutopilotGoals(Array(goals), modelContext: modelContext)

        // Sync active schedules
        await lifecycleService.syncActiveSchedules(goals: Array(goals), modelContext: modelContext)

        // Count results
        let activeGoalsCount = goals.filter { $0.activationState == .active }.count
        let totalSessionsCount = goals.flatMap { $0.scheduledEvents }.count

        // Show success feedback
        showProactiveToast(
            message: "✓ Refreshed \(activeGoalsCount) goals, \(totalSessionsCount) sessions scheduled",
            type: .success
        )

        // Success haptic
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)

        isRefreshing = false

        print("🔄 Manual refresh complete: \(activeGoalsCount) active goals, \(totalSessionsCount) sessions")
    }
}

private extension ContentView {
    enum MainTab: Hashable {
        case chat
        case timeline
        case categories
    }

    enum ActiveSheet: String, Identifiable {
        case settings

        var id: String { rawValue }
    }

    enum StatusFocus: String, CaseIterable, Identifiable {
        case active
        case draft
        case completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .active: return "Active"
            case .draft: return "Drafts"
            case .completed: return "Completed"
            }
        }

        var systemImage: String {
            switch self {
            case .active: return "bolt.fill"
            case .draft: return "tray.full"
            case .completed: return "checkmark.seal.fill"
            }
        }

        var tint: Color {
            switch self {
            case .active: return .green
            case .draft: return .orange
            case .completed: return .blue
            }
        }

        func subtitle(for count: Int) -> String {
            switch count {
            case 0: return "No cards"
            case 1: return "1 goal"
            default: return "\(count) goals"
            }
        }
    }

    enum GoalsLayout: String, CaseIterable, Identifiable {
        case gantt
        case categories

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gantt: return "Timeline"
            case .categories: return "Categories"
            }
        }

        var subtitle: String {
            switch self {
            case .gantt: return "Plan by time"
            case .categories: return "Organize by theme"
            }
        }

        var systemImage: String {
            switch self {
            case .gantt: return "chart.bar.xaxis"
            case .categories: return "square.grid.2x2"
            }
        }

        var tint: Color {
            switch self {
            case .gantt: return .cyan
            case .categories: return .blue
            }
        }
    }

    enum Horizon: CaseIterable {
        case short
        case medium
        case long

        var title: String {
            switch self {
            case .short: return "Short-term"
            case .medium: return "Mid-term"
            case .long: return "Long-term"
            }
        }

        var synopsis: String {
            switch self {
            case .short: return "Focus this week"
            case .medium: return "Shape the month"
            case .long: return "Vision ahead"
            }
        }

        var icon: String {
            switch self {
            case .short: return "flame.fill"
            case .medium: return "clock.fill"
            case .long: return "calendar"
            }
        }

        var tint: Color {
            switch self {
            case .short: return .red
            case .medium: return .orange
            case .long: return .purple
            }
        }
    }

    struct StatusMetricCard: View {
        let title: String
        let value: String
        let caption: String
        let systemImage: String
        let tint: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)

                Text(value)
                    .font(.title)
                    .fontWeight(.bold)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .liquidGlassCard(cornerRadius: 28, tint: tint.opacity(0.24))
        }
    }

    struct GoalQuickRow: View {
        @Bindable var goal: Goal
        let accent: Color
        let index: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%02d", index))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.7))
                        .clipShape(Capsule())

                    Text(goal.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(goal.progress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: goal.progress)
                    .progressViewStyle(.linear)
                    .tint(accent)

                if !goal.category.isEmpty {
                    HStack(spacing: 6) {
                        Label(goal.category, systemImage: "folder")
                            .font(.caption2)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(accent)
                        Text(goal.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(goal.priority.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .liquidGlassCard(cornerRadius: 28, tint: accent.opacity(0.18))
        }
    }

    struct HorizonCard: View {
        let horizon: Horizon
        let goals: [Goal]

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(horizon.title, systemImage: horizon.icon)
                        .font(.headline)
                        .foregroundStyle(horizon.tint)
                    Spacer()
                    Text("\(goals.count) goal\(goals.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(horizon.synopsis)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if goals.isEmpty {
                    Text("Nothing here yet. Add a goal to plan ahead.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(goals.prefix(3)) { goal in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(goal.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(goal.progress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                ProgressView(value: goal.progress)
                                    .progressViewStyle(.linear)
                                    .tint(horizon.tint)
                            }
                        }
                    }
                }
            }
            .frame(width: 260, alignment: .leading)
            .padding(22)
            .liquidGlassCard(cornerRadius: 30, tint: horizon.tint.opacity(0.24))
        }
    }

    struct LiquidPickerSegment: View {
        let title: String
        let subtitle: String
        let systemImage: String
        let isSelected: Bool
        let tint: Color

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : .secondary)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(tint)
                    }
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(
                                isSelected ? tint.opacity(colorScheme == .dark ? 0.8 : 0.6) : Color.white.opacity(0.12),
                                lineWidth: isSelected ? 1.6 : 1
                            )
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.25 : 0.08))
                    .blur(radius: isSelected ? 18 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: tint.opacity(isSelected ? 0.25 : 0.0), radius: isSelected ? 12 : 0, x: 0, y: 6)
        }
    }
}


