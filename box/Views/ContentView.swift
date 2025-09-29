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

    @State private var composerText = ""
    @State private var isGeneratingGoal = false
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedTab: MainTab = .board

    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainInterface
            } else {
                onboarding
            }
        }
        .environmentObject(lifecycleService)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .generalChat:
                GeneralChatView(goals: Array(goals))
            case .settings:
                SettingsView()
            }
        }
    }
}

private extension ContentView {
    var mainInterface: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                dashboardView
                    .navigationTitle("Goal Board")
                    .toolbar { primaryToolbar }
                    .searchable(text: $searchText, prompt: "Search goals")
            }
            .tabItem {
                Label("Board", systemImage: "rectangle.grid.2x2")
            }
            .tag(MainTab.board)

            NavigationStack {
                categoriesView
                    .navigationTitle("By Category")
                    .toolbar { primaryToolbar }
                    .searchable(text: $searchText, prompt: "Search goals")
            }
            .tabItem {
                Label("Categories", systemImage: "folder")
            }
            .tag(MainTab.categories)

            NavigationStack {
                timelineView
                    .navigationTitle("Time Buckets")
                    .toolbar { primaryToolbar }
                    .searchable(text: $searchText, prompt: "Search goals")
            }
            .tabItem {
                Label("Timeline", systemImage: "clock")
            }
            .tag(MainTab.timeline)

            NavigationStack {
                mirrorModeView
                    .navigationTitle("Mirror Mode")
                    .toolbar { primaryToolbar }
            }
            .tabItem {
                Label("Mirror", systemImage: "sparkles.rectangle.stack")
            }
            .tag(MainTab.mirror)
        }
    }

    var dashboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                composerPanel

                if !goals.isEmpty {
                    overviewRow
                }

                if filteredGoals.isEmpty {
                    EmptyStateView()
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(filteredGoals) { goal in
                            GoalCardView(goal: goal)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(sceneBackground)
    }

    var categoriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if filteredGoals.isEmpty {
                    EmptyStateView()
                        .padding(.top, 40)
                } else {
                    CategoryGoalsView(goals: filteredGoals)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(sceneBackground)
    }

    var timelineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if filteredGoals.isEmpty {
                    EmptyStateView()
                        .padding(.top, 40)
                } else {
                    TimeBasedGoalsView(goals: filteredGoals)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 36)
        }
        .background(sceneBackground)
    }

    var mirrorModeView: some View {
        MirrorModeView()
            .background(sceneBackground)
    }

    var composerPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start a new goal")
                        .font(.title2).fontWeight(.bold)
                    Text("Describe what you want and let AI craft the card")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isGeneratingGoal {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextEditor(text: $composerText)
                .focused($composerFocused)
                .frame(minHeight: 120)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack {
                Button(action: submitGoal) {
                    Label("Generate with AI", systemImage: "wand.and.stars")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isGeneratingGoal ? Color.blue.opacity(0.4) : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(isGeneratingGoal || composerText.trimmed.isEmpty)

                Button(action: submitQuickGoal) {
                    Label("Add Quickly", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Spacer()

                if let selectedCategory {
                    Text("Filtering: \(selectedCategory)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .glassBackground(cornerRadius: 28)
    }

    var overviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                OverviewTile(
                    title: "Active",
                    value: "\(activeGoals.count)",
                    caption: "Goals in motion",
                    systemImage: "bolt.fill",
                    tint: .green
                )

                OverviewTile(
                    title: "Drafts",
                    value: "\(draftGoals.count)",
                    caption: "Need activation",
                    systemImage: "tray.fill",
                    tint: .orange
                )

                OverviewTile(
                    title: "Completed",
                    value: "\(completedGoals.count)",
                    caption: "Celebrations",
                    systemImage: "checkmark.circle.fill",
                    tint: .blue
                )

                OverviewTile(
                    title: "Average Progress",
                    value: "\(Int(averageProgress * 100))%",
                    caption: "Across all goals",
                    systemImage: "chart.bar.fill",
                    tint: .purple
                )
            }
            .padding(.trailing, 12)
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
    var primaryToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button("All Categories") {
                    selectedCategory = nil
                }

                let categories = sortedCategories
                if !categories.isEmpty {
                    Divider()
                }

                ForEach(categories, id: \.self) { category in
                    Button(category) {
                        selectedCategory = category
                    }
                }
            } label: {
                Label(selectedCategory ?? "All Categories", systemImage: "line.3.horizontal.decrease.circle")
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                activeSheet = .generalChat
            } label: {
                Label("General Chat", systemImage: "message.and.waveform")
            }

            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    var filteredGoals: [Goal] {
        var result = goals

        if let selectedCategory {
            result = result.filter { $0.category.caseInsensitiveCompare(selectedCategory) == .orderedSame }
        }

        let query = searchText.trimmed.lowercased()
        if !query.isEmpty {
            result = result.filter { goal in
                goal.title.lowercased().contains(query) || goal.content.lowercased().contains(query)
            }
        }

        return result
    }

    var sortedCategories: [String] {
        let categories = Set(goals.map { $0.category })
        return categories.sorted()
    }

    var activeGoals: [Goal] {
        goals.filter { $0.activationState == .active }
    }

    var draftGoals: [Goal] {
        goals.filter { $0.activationState == .draft }
    }

    var completedGoals: [Goal] {
        goals.filter { $0.activationState == .completed }
    }

    var averageProgress: Double {
        guard !goals.isEmpty else { return 0 }
        let total = goals.reduce(0) { $0 + $1.progress }
        return total / Double(goals.count)
    }

    func submitGoal() {
        let prompt = composerText.trimmed
        guard !prompt.isEmpty else { return }

        isGeneratingGoal = true

        Task {
            let context = await MainActor.run { () -> AIContext in
                let snapshot = Array(goals)
                return UserContextService.shared.buildContext(from: snapshot)
            }

            do {
                let response = try await AIService.shared.createGoal(from: prompt, context: context)
                await MainActor.run {
                    addGoal(using: response, fallbackTitle: prompt)
                }
            } catch {
                await MainActor.run {
                    addFallbackGoal(title: prompt)
                }
            }

            await MainActor.run {
                isGeneratingGoal = false
            }
        }
    }

    func submitQuickGoal() {
        let prompt = composerText.trimmed
        guard !prompt.isEmpty else { return }

        Task { @MainActor in
            addFallbackGoal(title: prompt)
        }
    }

    @MainActor
    func addGoal(using response: GoalCreationResponse, fallbackTitle: String) {
        let title = response.title.trimmed.isEmpty ? fallbackTitle : response.title
        let priority = Goal.Priority(rawValue: response.priority.capitalized) ?? .next

        let newGoal = Goal(
            title: title,
            content: response.content,
            category: response.category.isEmpty ? "General" : response.category,
            priority: priority
        )

        modelContext.insert(newGoal)

        for suggestion in response.suggestedSubgoals where !suggestion.trimmed.isEmpty {
            let subgoal = Goal(title: suggestion.trimmed, content: "", category: newGoal.category, priority: .later)
            subgoal.parent = newGoal
            modelContext.insert(subgoal)
        }

        composerText = ""
        composerFocused = false
        selectedCategory = response.category.isEmpty ? selectedCategory : response.category
    }

    @MainActor
    func addFallbackGoal(title: String) {
        let newGoal = Goal(title: title)
        modelContext.insert(newGoal)
        composerText = ""
        composerFocused = false
    }
}

private extension ContentView {
    enum MainTab: Hashable {
        case board
        case categories
        case timeline
        case mirror
    }

    enum ActiveSheet: String, Identifiable {
        case generalChat
        case settings

        var id: String { rawValue }
    }

    struct OverviewTile: View {
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
                    .font(.title3)
                    .fontWeight(.bold)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .glassBackground(cornerRadius: 20)
        }
    }
}


