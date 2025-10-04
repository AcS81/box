//
//  CategoryGoalsView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct CategoryGoalsView: View {
    let goals: [Goal]

    @State private var currentFolderIndex = 0
    @State private var selectedGoalID: UUID?

    private let palette: [Color] = [
        Color(red: 0.86, green: 0.64, blue: 0.32),
        Color(red: 0.71, green: 0.54, blue: 0.86),
        Color(red: 0.42, green: 0.67, blue: 0.84),
        Color(red: 0.48, green: 0.73, blue: 0.55),
        Color(red: 0.88, green: 0.54, blue: 0.51),
        Color(red: 0.73, green: 0.59, blue: 0.45),
        Color(red: 0.64, green: 0.54, blue: 0.87),
        Color(red: 0.53, green: 0.70, blue: 0.86)
    ]

    private var folders: [CategoryFolder] {
        Dictionary(grouping: goals) { goal in
            goal.category.trimmed.isEmpty ? "Untitled" : goal.category
        }
        .map { key, value in
            CategoryFolder(
                name: key,
                tint: tint(for: key),
                goals: value.sorted(by: goalSort)
            )
        }
        .sorted()
    }

    private var foldersSignature: String {
        folders
            .flatMap { folder in
                folder.goals.map { goal in
                    "\(folder.id)|\(goal.id)|\(goal.updatedAt.timeIntervalSince1970)"
                }
            }
            .joined(separator: ";")
    }

    private var currentFolder: CategoryFolder? {
        guard folders.indices.contains(currentFolderIndex) else { return folders.first }
        return folders[currentFolderIndex]
    }

    private var selectedGoal: Goal? {
        guard let folder = currentFolder else { return nil }

        if let id = selectedGoalID,
           let match = folder.goals.first(where: { $0.id == id }) {
            return match
        }

        return folder.goals.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if folders.isEmpty {
                    emptyState
                } else {
                    categoryStrip

                    if let goal = selectedGoal {
                        BlueprintGoalView(goal: goal, tint: currentFolder?.tint ?? .blue)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(LinedPaperBackground(spacing: 44, marginX: 64))
        .scrollIndicators(.never)
        .onAppear(perform: ensureSelectionValid)
        .onChange(of: currentFolderIndex) { _, _ in ensureSelectionValid() }
        .onChange(of: foldersSignature) { _, _ in ensureSelectionValid() }
    }

    private var categoryStrip: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let folder = currentFolder {
                folderBadge(for: folder)
            }

            TabView(selection: $currentFolderIndex) {
                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                    CategoryStripPage(
                        folder: folder,
                        selectedGoalID: Binding(
                            get: { selectedGoalID },
                            set: { newValue in
                                selectedGoalID = newValue
                                if currentFolderIndex != index {
                                    currentFolderIndex = index
                                }
                            }
                        )
                    ) { goal in
                        selectedGoalID = goal.id
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 200)

            pagerIndicators
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.paperBase.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.paperSpeck.opacity(0.4), lineWidth: 1.1)
                        .blendMode(.multiply)
                )
                .shadow(color: Color.paperSpeck.opacity(0.18), radius: 12, x: 0, y: 8)
        )
    }

    private var pagerIndicators: some View {
        HStack(spacing: 8) {
            ForEach(Array(folders.enumerated()), id: \.offset) { index, folder in
                Capsule()
                    .fill(folder.tint.opacity(index == currentFolderIndex ? 0.9 : 0.25))
                    .frame(width: index == currentFolderIndex ? 28 : 10, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentFolderIndex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 54))
                .foregroundStyle(Color.paperLine.opacity(0.7))

            Text("No goal decks yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.paperSpeck)

            Text("Create a goal and it will appear here as a card on your desk.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paperLine.opacity(0.75))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.paperSpeck.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
        )
    }

    private func folderBadge(for folder: CategoryFolder) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(folder.tint.opacity(0.18))
                .overlay(
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(folder.tint)
                        Text(folder.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(folder.tint)
                        Text("\(folder.goals.count) cards")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(folder.tint.opacity(0.22))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                )

            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private func tint(for name: String) -> Color {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return palette[0] }
        let index = abs(normalized.hashValue) % palette.count
        return palette[index]
    }

    private func goalSort(_ lhs: Goal, _ rhs: Goal) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
        if lhs.progress != rhs.progress {
            return lhs.progress > rhs.progress
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func ensureSelectionValid() {
        guard let folder = currentFolder else {
            selectedGoalID = nil
            return
        }

        if let id = selectedGoalID,
           folder.goals.contains(where: { $0.id == id }) {
            return
        }

        selectedGoalID = folder.goals.first?.id
    }
}

// MARK: - Blueprint Goal View

struct BlueprintGoalView: View {
    @Bindable var goal: Goal
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            goalHeader

            if goal.hasSequentialSteps {
                // Timeline Blueprint
                timelineBlueprint
            } else {
                // No timeline yet
                noTimelineState
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.paperBase.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(tint.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: tint.opacity(0.2), radius: 16, x: 0, y: 8)
        )
    }

    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(goal.priority.rawValue, systemImage: goal.priority.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(tint)
                    .clipShape(Capsule())

                Spacer()

                Text("\(Int(goal.progress * 100))%")
                    .font(.title.weight(.bold))
                    .foregroundStyle(tint)
            }

            Text(goal.title)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.paperSpeck.opacity(0.95))
                .lineLimit(3)

            if !goal.content.isEmpty {
                Text(goal.content)
                    .font(.body)
                    .foregroundStyle(Color.paperLine.opacity(0.85))
                    .lineLimit(4)
            }

            ProgressView(value: goal.progress)
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private var timelineBlueprint: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider()
                .background(Color.paperSpeck.opacity(0.3))

            // If tree grouping exists, show grouped structure
            if !goal.treeGroupingSections.isEmpty {
                groupedTimelineView
            } else {
                // Fallback to simple timeline
                simpleTimelineView
            }
        }
    }

    private var groupedTimelineView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(goal.treeGroupingSections) { section in
                let sectionSteps: [Goal] = section.stepIndices.compactMap { index in
                    guard goal.sequentialSteps.indices.contains(index) else { return nil }
                    return goal.sequentialSteps[index]
                }

                if !sectionSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: section.isComplete ? "checkmark.circle.fill" : "folder.fill")
                                .font(.headline)
                            Text(section.title)
                                .font(.headline.weight(.bold))
                            Spacer()
                            if section.isComplete {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .foregroundStyle(section.isComplete ? .green : .blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(section.isComplete ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        ForEach(sectionSteps) { step in
                            let color: Color = step.stepStatus == .completed ? .green : (step.stepStatus == .current ? .orange : .gray)
                            StepCard(step: step, color: color, isLocked: step.stepStatus != .current)
                                .padding(.leading, 16)
                        }
                    }
                }
            }

            // Show ungrouped steps (not in any section)
            let allGroupedIndices = Set(goal.treeGroupingSections.flatMap { $0.stepIndices })
            let ungroupedSteps = goal.sequentialSteps.enumerated().compactMap { (index, step) in
                allGroupedIndices.contains(index) ? nil : step
            }

            if !ungroupedSteps.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Other Steps")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    ForEach(ungroupedSteps) { step in
                        let color: Color = step.stepStatus == .completed ? .green : (step.stepStatus == .current ? .orange : .gray)
                        StepCard(step: step, color: color, isLocked: step.stepStatus != .current)
                    }
                }
            }
        }
    }

    private var simpleTimelineView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Until Now (Completed)
            if !goal.completedSequentialSteps.isEmpty {
                timelineSection(
                    title: "UNTIL NOW",
                    icon: "lock.fill",
                    color: .green,
                    steps: goal.completedSequentialSteps
                )
            }

            // Current Step
            if let current = goal.currentSequentialStep {
                timelineSection(
                    title: "CURRENT",
                    icon: "play.circle.fill",
                    color: .orange,
                    steps: [current]
                )
            }

            // Future (Pending)
            let pendingSteps = goal.sequentialSteps.filter { $0.stepStatus == .pending }
            if !pendingSteps.isEmpty {
                timelineSection(
                    title: "FUTURE",
                    icon: "lock.fill",
                    color: .gray,
                    steps: pendingSteps
                )
            }
        }
    }

    private func timelineSection(title: String, icon: String, color: Color, steps: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.15))
                .clipShape(Capsule())

            ForEach(steps) { step in
                StepCard(step: step, color: color, isLocked: step.stepStatus != .current)
            }
        }
    }

    private var noTimelineState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(Color.paperLine.opacity(0.5))

            Text("No timeline yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.paperSpeck.opacity(0.8))

            Text("This goal hasn't been broken into sequential steps")
                .font(.body)
                .foregroundStyle(Color.paperLine.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct StepCard: View {
    let step: Goal
    let color: Color
    let isLocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Step indicator
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: isLocked ? "lock.fill" : step.stepStatus.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.paperSpeck.opacity(0.95))

                if !step.outcome.isEmpty {
                    Text(step.outcome)
                        .font(.callout)
                        .foregroundStyle(Color.paperLine.opacity(0.85))
                        .lineLimit(2)
                }

                if let targetDate = step.targetDate {
                    Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(color.opacity(0.8))
                }

                if step.stepStatus == .current {
                    ProgressView(value: step.progress)
                        .progressViewStyle(.linear)
                        .tint(color)
                        .padding(.top, 4)
                }
            }

            Spacer()

            if step.stepStatus == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isLocked ? Color.paperSecondary.opacity(0.3) : color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(isLocked ? 0.2 : 0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Supporting Types

private struct CategoryFolder: Identifiable, Comparable {
    let name: String
    let tint: Color
    let goals: [Goal]

    var id: String { name }

    var sortKey: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func < (lhs: CategoryFolder, rhs: CategoryFolder) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}

private struct CategoryStripPage: View {
    let folder: CategoryFolder
    @Binding var selectedGoalID: UUID?
    let onSelectGoal: (Goal) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(folder.tint.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(folder.tint.opacity(0.35), lineWidth: 1)
                )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(folder.goals) { goal in
                        MiniGoalCard(
                            goal: goal,
                            tint: folder.tint,
                            isSelected: selectedGoalID == goal.id
                        )
                        .onTapGesture {
                            selectedGoalID = goal.id
                            onSelectGoal(goal)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .scrollBounceBehavior(.basedOnSize)

            Capsule(style: .continuous)
                .fill(folder.tint.opacity(0.85))
                .overlay(
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.95))
                        Text("Swipe to browse cards")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                )
                .padding(14)
        }
        .padding(.horizontal, 4)
    }
}

private struct MiniGoalCard: View {
    let goal: Goal
    let tint: Color
    let isSelected: Bool

    private var statusLabel: String {
        switch goal.activationState {
        case .active: return "Active"
        case .completed: return "Completed"
        case .draft: return "Draft"
        case .archived: return "Archived"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(goal.priority.rawValue, systemImage: goal.priority.iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())

                Spacer(minLength: 4)

                Text("\(Int(goal.progress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(goal.title)
                .font(.body.weight(.bold))
                .foregroundStyle(.white.opacity(0.98))
                .lineLimit(2)

            Spacer(minLength: 6)

            ProgressView(value: goal.progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.95))

            Text(statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 180, height: 150, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(isSelected ? 0.95 : 0.75),
                            tint.opacity(isSelected ? 0.65 : 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: tint.opacity(isSelected ? 0.35 : 0.18), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 8 : 4)
        .animation(.smoothSpring, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.title)
        .accessibilityValue("Progress \(Int(goal.progress * 100)) percent. \(statusLabel)")
    }
}

private extension Goal.Priority {
    var sortOrder: Int {
        switch self {
        case .now: return 0
        case .next: return 1
        case .later: return 2
        }
    }

    var iconName: String {
        switch self {
        case .now: return "flame.fill"
        case .next: return "clock.fill"
        case .later: return "calendar"
        }
    }
}

#Preview {
    let sampleGoals: [Goal] = {
        let g1 = Goal(title: "Ship onboarding", category: "Product", priority: .now)
        g1.progress = 0.65
        g1.activationState = .active

        let step1 = g1.createSequentialStep(title: "Research users", outcome: "User insights gathered", targetDate: Date())
        step1.stepStatus = .completed
        step1.progress = 1.0

        let step2 = g1.createSequentialStep(title: "Design flows", outcome: "Onboarding wireframes ready", targetDate: Date().addingTimeInterval(7*86400))
        step2.stepStatus = .current
        step2.progress = 0.6

        _ = g1.createSequentialStep(title: "Implement UI", outcome: "Screens coded", targetDate: Date().addingTimeInterval(14*86400))
        _ = g1.createSequentialStep(title: "Test & launch", outcome: "Live to users", targetDate: Date().addingTimeInterval(21*86400))

        let g2 = Goal(title: "Plan launch campaign", category: "Product", priority: .next)
        g2.progress = 0.3

        let g3 = Goal(title: "Strength training", category: "Health", priority: .now)
        g3.progress = 0.5

        return [g1, g2, g3]
    }()

    CategoryGoalsView(goals: sampleGoals)
        .modelContainer(for: Goal.self, inMemory: true)
}
