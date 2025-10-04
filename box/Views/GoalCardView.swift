//
//  GoalCardView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct GoalCardView: View {
    @Bindable var goal: Goal
    @State private var isExpanded = false
    @State private var showingChat = false
    @State private var isRecording = false
    @State private var recordedTranscript: String?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showActivationPreview = false
    @State private var activationPlan: CalendarService.ActivationPlan?
    @State private var showDeleteConfirmation = false
    @State private var goalEmoji: String = "🎯"
    @State private var showAllSubtasksSheet = false
    @State private var selectedSubgoalForDetail: Goal?
    @State private var isLocking = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var lifecycleService: GoalLifecycleService

    @StateObject private var userContextService = UserContextService.shared
    @StateObject private var voiceService = VoiceService()
    @EnvironmentObject private var transcriptManager: VoiceTranscriptManager

    private var aiService: AIService { AIService.shared }

    private var isProcessing: Bool {
        lifecycleService.isProcessing(goalID: goal.id)
    }

    private var parentGoal: Goal? {
        goal.parent
    }

    private var isSubgoal: Bool {
        parentGoal != nil
    }

    private var completedSubgoalsCount: Int {
        goal.allDescendants()
            .filter { $0.progress >= 0.999 }
            .count
    }

    private var dependencyCount: Int {
        goal.allDescendants(includeSelf: true)
            .reduce(0) { $0 + $1.incomingDependencies.count }
    }

    private var goalKindPresentation: (title: String, icon: String, tint: Color) {
        switch goal.kind {
        case .event:
            return ("Event", "calendar.badge.clock", .blue)
        case .campaign:
            return ("Campaign", "chart.line.uptrend.xyaxis", .purple)
        case .hybrid:
            return ("Hybrid", "arrow.triangle.2.circlepath", .teal)
        }
    }

    private var upcomingProjection: GoalProjection? {
        let now = Date()
        return goal.projections
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.startDate < rhs.startDate
            }
            .first { projection in
                switch projection.status {
                case .complete, .skipped:
                    return false
                case .stale:
                    return projection.endDate >= now
                case .upcoming, .inProgress:
                    return projection.endDate >= now || projection.status == .inProgress
                }
            }
    }

    private var upcomingEvent: ScheduledEventLink? {
        goal.scheduledEvents
            .sorted { lhs, rhs in
                let lhsStart = lhs.startDate ?? lhs.endDate ?? .distantFuture
                let rhsStart = rhs.startDate ?? rhs.endDate ?? .distantFuture
                return lhsStart < rhsStart
            }
            .first { link in
                guard let start = link.startDate ?? link.endDate else { return false }
                return start >= Date()
            }
    }

    private var cardTint: Color {
        switch goal.priority {
        case .now:
            return Color(red: 0.96, green: 0.32, blue: 0.36)
        case .next:
            return Color(red: 0.98, green: 0.63, blue: 0.24)
        case .later:
            return Color(red: 0.28, green: 0.54, blue: 0.96)
        }
    }

    private var priorityAccentColor: Color {
        switch goal.priority {
        case .now:
            return Color.red
        case .next:
            return Color.orange
        case .later:
            return Color.blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardContent
        }
        .padding(20)
        .animation(.smoothSpring, value: isExpanded)
        .paperCard(
            cornerRadius: 28,
            accent: goal.isActive ? priorityAccentColor : Color.paperMargin
        )
        .accessibilityLabel("Goal: \(goal.title)")
        .accessibilityValue("Progress: \(Int(goal.progress * 100)) percent, Priority: \(goal.priority.rawValue)")
        .accessibilityHint("Double tap header to \(isExpanded ? "collapse" : "expand") goal details")
        .alert("Something went wrong", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "Delete \"\(goal.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Goal", role: .destructive) {
                Task { await deleteGoal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All subgoals and related data will also be deleted.")
        }
        .sheet(isPresented: $showActivationPreview, onDismiss: {
            activationPlan = nil
        }) {
            if let plan = activationPlan {
                ActivationPreviewSheet(
                    goalTitle: goal.title,
                    plan: plan,
                    isProcessing: isProcessing,
                    onConfirm: {
                        Task { await confirmActivation(using: plan) }
                    },
                    onCancel: {
                        dismissActivationPreview()
                    }
                )
                .presentationDetents([.medium, .large])
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing activation plan...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingChat) {
            GoalChatView(goal: goal)
        }
        .sheet(item: $selectedSubgoalForDetail) { subgoal in
            SubgoalDetailSheet(
                subgoal: subgoal,
                parentGoal: goal,
                onToggleCompletion: { goal, isComplete in
                    Task { await toggleSubgoalCompletion(goal, target: isComplete ? 1.0 : 0.0) }
                },
                onDelete: { goal in
                    Task { await deleteSubgoal(goal) }
                },
                onVoiceRecord: { goal in
                    Task { await recordVoiceForSubtask(goal) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAllSubtasksSheet) {
            SubtaskListSheet(
                parentGoal: goal,
                subgoals: goal.sortedSubgoals,
                recordingSubtaskId: recordingSubtaskId,
                onToggleCompletion: { goal, isComplete in
                    Task { await toggleSubgoalCompletion(goal, target: isComplete ? 1.0 : 0.0) }
                },
                onDelete: { goal in
                    Task { await deleteSubgoal(goal) }
                },
                onVoiceRecord: { goal in
                    Task { await recordVoiceForSubtask(goal) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .task(id: goal.updatedAt) {
            await refreshEmoji()
        }
        .onDisappear {
            if isRecording {
                voiceService.cancel()
                stopTimer()
            }
        }
        .onChange(of: voiceService.state) { _, newState in
            switch newState {
            case .recording:
                if !isRecording {
                    isRecording = true
                    recordingStartedAt = Date()
                    recordingElapsed = 0
                    startTimer()
                }
            case .idle, .transcribing, .error:
                if isRecording {
                    isRecording = false
                    stopTimer()
                }
            }
        }
    }
    
    // MARK: - Card Sections

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection
            metaRow
            milestoneRow
            glanceRow
            quickActionsSection
            if isExpanded {
                expandedSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            priorityGlyph

            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(goal.category)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.cardSpring) {
                    isExpanded.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(priorityAccentColor)
                }

                lockButton

                Button {
                    withAnimation(.smoothSpring) {
                        isExpanded.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var priorityGlyph: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [priorityAccentColor.opacity(0.55), priorityAccentColor.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)
                .shadow(color: priorityAccentColor.opacity(0.25), radius: 12, x: 0, y: 6)
 
            Text(goalEmoji)
                .font(.system(size: 24))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    private var metaRow: some View {
        let kind = goalKindPresentation

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                metaChip(icon: kind.icon, label: kind.title, tint: kind.tint)

                metaChip(icon: "folder.fill", label: goal.category, tint: priorityAccentColor)

                // Show sequential steps progress (roadmap system)
                if goal.hasSequentialSteps {
                    let completedCount = goal.completedSequentialSteps.count
                    let totalCount = goal.sequentialSteps.count
                    let percentage = totalCount > 0 ? Int((Double(completedCount) / Double(totalCount)) * 100) : 0
                    metaChip(icon: "map.fill", label: "\(completedCount)/\(totalCount) steps (\(percentage)%)", tint: .orange)
                }

                if let parent = parentGoal {
                    metaChip(icon: "arrowshape.turn.up.backward.fill", label: parent.title, tint: Color.blue)
                }

                if goal.isLocked {
                    metaChip(icon: "lock.fill", label: "Locked", tint: .yellow)
                        .accessibilityHidden(true)
                }

                if goal.activationState == .active {
                    emojiMetaChip(emoji: goalEmoji, label: "Active", tint: .green)
                } else if let info = goal.activationState.presentation {
                    metaChip(icon: info.icon, label: info.title, tint: info.color)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var glanceRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.hasSequentialSteps ? "Roadmap Progress" : "Progress")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(displayProgress * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            ProgressView(value: displayProgress)
                .progressViewStyle(.linear)
                .tint(priorityAccentColor)

            HStack(spacing: 12) {
                if goal.hasSequentialSteps {
                    glanceMetric(
                        icon: "map.fill",
                        title: "Roadmap Steps",
                        value: "\(goal.sequentialSteps.count)"
                    )

                    glanceMetric(
                        icon: "checkmark.circle.fill",
                        title: "Done",
                        value: "\(goal.completedSequentialSteps.count)"
                    )

                    if goal.hasParallelBranches {
                        glanceMetric(
                            icon: "arrow.triangle.branch",
                            title: "Subtasks",
                            value: "\(goal.parallelBranches.count)"
                        )
                    }
                } else {
                    glanceMetric(
                        icon: "list.bullet.rectangle",
                        title: "Subtasks",
                        value: "\(goal.sortedSubgoals.count)"
                    )

                    glanceMetric(
                        icon: "checkmark.circle",
                        title: "Complete",
                        value: "\(completedSubgoalsCount)"
                    )

                    glanceMetric(
                        icon: "link",
                        title: "Dependencies",
                        value: "\(dependencyCount)"
                    )
                }
            }
        }
    }

    private var displayProgress: Double {
        if goal.hasSequentialSteps {
            return goal.sequentialProgress
        }
        return goal.progress
    }

    @ViewBuilder
    private var milestoneRow: some View {
        // Show current sequential step if available
        if let currentStep = goal.currentSequentialStep {
            currentStepCard(step: currentStep)
        } else if let projection = upcomingProjection {
            milestoneCard(
                icon: projection.status == .inProgress ? "timer" : "scope",
                title: projection.title,
                detail: projection.detail,
                interval: DateInterval(start: projection.startDate, end: projection.endDate),
                accent: goal.kind == .campaign ? Color.purple : Color.blue,
                metric: projection.expectedMetricDelta,
                unit: projection.metricUnit,
                confidence: projection.confidence
            )
        } else if let nextEvent = upcomingEvent {
            let start = nextEvent.startDate ?? Date()
            let end = nextEvent.endDate ?? start.addingTimeInterval(3600)
            let detail = nextEventDetail(nextEvent)
            milestoneCard(
                icon: "calendar.badge.clock",
                title: nextEventStatusLine(nextEvent),
                detail: detail,
                interval: DateInterval(start: start, end: end),
                accent: Color.blue,
                metric: nil,
                unit: nil,
                confidence: nil
            )
        } else if goal.kind == .campaign, let target = goal.targetMetric {
            let start = Date()
            let end = start.addingTimeInterval(Double(target.measurementWindowDays ?? 14) * 86400)
            milestoneCard(
                icon: "target",
                title: target.label,
                detail: target.notes,
                interval: DateInterval(start: start, end: end),
                accent: Color.indigo,
                metric: target.targetValue,
                unit: target.unit,
                confidence: nil
            )
        }
    }

    private var quickActionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                quickActionButton(
                    icon: isRecording ? "stop.circle.fill" : "mic.fill",
                    title: isRecording ? recordingDuration : "Voice note",
                    tint: isRecording ? Color.red : priorityAccentColor,
                    isActive: isRecording,
                    isDisabled: goal.isLocked || isProcessing
                ) {
                    Task { await toggleRecording() }
                }
                .onAppear(perform: startTimerIfNeeded)
                .onDisappear(perform: stopTimer)

                quickActionButton(
                    icon: "bubble.right.fill",
                    title: "Chat",
                    tint: Color.blue,
                    isDisabled: isProcessing
                ) {
                    showingChat = true
                }
 
                let activationIcon = goal.activationState == .active ? "pause.fill" : goalEmoji
                let activationTitle = goal.activationState == .active ? "Deactivate" : "Activate"
                quickActionButton(
                    icon: activationIcon,
                    title: activationTitle,
                    tint: goal.activationState == .active ? Color.gray : Color.green,
                    isBusy: isProcessing,
                    isDisabled: goal.isLocked
                ) {
                    Task { await handleActivationAction() }
                }

                quickActionButton(
                    icon: "trash.fill",
                    title: "Delete",
                    tint: Color.red,
                    isDisabled: isProcessing
                ) {
                    showDeleteConfirmation = true
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func metaChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
        .clipShape(Capsule())
    }

    private func emojiMetaChip(emoji: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.caption.weight(.semibold))

            Text(label)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
        .clipShape(Capsule())
    }

    private func glanceMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05))
        )
    }

    private func milestoneCard(
        icon: String,
        title: String,
        detail: String?,
        interval: DateInterval,
        accent: Color,
        metric: Double?,
        unit: String?,
        confidence: Double?
    ) -> some View {
        let intervalText: String = {
            let formatted = Self.milestoneIntervalFormatter.string(from: interval.start, to: interval.end)
            if !formatted.isEmpty {
                return formatted
            }
            let formatter = Self.milestoneDateFormatter
            let start = formatter.string(from: interval.start)
            let end = formatter.string(from: interval.end)
            return "\(start) → \(end)"
        }()
        let metricText: String? = {
            guard let metric else { return nil }
            let unitSuffix = unit.map { " \($0)" } ?? ""
            let valueString = String(format: "%.1f", metric)
            return valueString + unitSuffix
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let metricText {
                    Text(metricText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }

            if let detail, !detail.trimmed.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(intervalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let confidence {
                    Label {
                        Text("Confidence \(Int(confidence * 100))%")
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
        )
    }

    private static let milestoneIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let milestoneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func currentStepCard(step: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Step")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                if let nextStep = goal.nextSequentialStep {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Next")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(nextStep.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if !step.outcome.isEmpty {
                Text(step.outcome)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let targetDate = step.targetDate {
                    Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    // Navigate to timeline view
                    // This would need to be wired up via environment or coordinator
                } label: {
                    Label("View Roadmap", systemImage: "map")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // "Until Now" indicator
            if !goal.completedSequentialSteps.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Until now: \(goal.completedSequentialSteps.count) completed steps locked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(colorScheme == .dark ? 0.35 : 0.25), lineWidth: 1.5)
        )
    }

    private func nextEventStatusLine(_ link: ScheduledEventLink) -> String {
        guard let start = link.startDate else {
            return "Scheduled session"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Next session • \(formatter.string(from: start))"
    }

    private func nextEventDetail(_ link: ScheduledEventLink) -> String? {
        switch link.status {
        case .confirmed:
            return "Confirmed focus block"
        case .proposed:
            return "Awaiting confirmation"
        case .cancelled:
            return "Session cancelled"
        }
    }

    private func quickActionButton(
        icon: String,
        title: String,
        tint: Color,
        isBusy: Bool = false,
        isActive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                } else {
                    if isEmoji(icon) {
                        Text(icon)
                            .font(.system(size: 18))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }

                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(isActive ? 0.9 : 0.75), tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tint.opacity(isActive ? 0.35 : 0.18), radius: isActive ? 12 : 8, x: 0, y: 6)
            )
            .foregroundStyle(Color.white)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy || isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private func isEmoji(_ icon: String) -> Bool {
        guard let scalar = icon.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
    }

    private var lockButton: some View {
        Button(action: toggleLock) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    .frame(width: 30, height: 30)
                
                if isLocking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: goal.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(goal.isLocked ? .yellow : .primary.opacity(0.7))
                }
            }
        }
        .disabled(isProcessing || isLocking)
        .buttonStyle(.plain)
        .accessibilityLabel(goal.isLocked ? "Unlock goal" : "Lock goal")
    }

    private var recordingDuration: String {
        if recordingElapsed <= 0 { return "00:00" }
        return recordingElapsed.asClockString
    }
 
    @State private var recordingStartedAt: Date?
    @State private var recordingTimer: Timer?
    @State private var recordingElapsed: TimeInterval = 0

    private func toggleRecording() async {
        if isRecording {
            // Stop recording
            await voiceService.stopRecording(for: goal)

            // Always reset UI state
            await MainActor.run {
                isRecording = false
                stopTimer()
            }

            if case .error(let message) = voiceService.state {
                await MainActor.run {
                    presentErrorMessage(message)
                    voiceService.resetTranscript()
                }
                return
            }

            let trimmed = voiceService.transcript.trimmed
            if !trimmed.isEmpty {
                await MainActor.run {
                    recordedTranscript = trimmed
                }
                await persistTranscript()
            }
        } else {
            guard !goal.isLocked else {
                await MainActor.run {
                    presentErrorMessage("Unlock the card to record")
                }
                return
            }

            // Reset everything before starting
            await MainActor.run {
                voiceService.cancel() // Force clean state
                recordedTranscript = nil
                recordingStartedAt = nil
                stopTimer()
            }

            await voiceService.startRecording()
            await MainActor.run {
                recordingStartedAt = Date()
                recordingElapsed = 0
                isRecording = true
                startTimer()
            }
        }
    }

    @MainActor
    private func appendTranscript() {
        guard let transcript = recordedTranscript, !transcript.isEmpty else { return }
        recordingStartedAt = nil
        stopTimer()

        // Create ChatEntry with appropriate scope
        let scope: ChatEntry.Scope = goal.parent != nil ? .subgoal(goal.id) : .goal(goal.id)
        let entry = ChatEntry(content: transcript, isUser: true, scope: scope)
        modelContext.insert(entry)

        goal.updatedAt = Date()
        recordedTranscript = nil
        transcriptManager.presentTranscript(goalTitle: goal.title, text: transcript)
    }
 
    private func persistTranscript() async {
        await MainActor.run { appendTranscript() }
    }

    @MainActor
    private func deleteSubgoalLocally(_ subgoal: Goal) {
        guard let index = goal.subgoals?.firstIndex(where: { $0.id == subgoal.id }) else { return }
        goal.subgoals?.remove(at: index)
        goal.updatedAt = Date()
    }

    private func deleteSubgoal(_ subgoal: Goal) async {
        do {
            try await lifecycleService.delete(goal: subgoal, within: currentGoals(), modelContext: modelContext)
            await MainActor.run { deleteSubgoalLocally(subgoal) }
        } catch {
            await MainActor.run {
                presentErrorMessage(error.localizedDescription)
            }
        }
    }

    @State private var recordingForSubgoal: Goal?
    @State private var recordingSubtaskId: UUID?

    private func recordVoiceForSubtask(_ subgoal: Goal) async {
        if recordingSubtaskId == subgoal.id {
            // Stop recording for this subtask
            await voiceService.stopRecording(for: subgoal)

            await MainActor.run {
                recordingSubtaskId = nil
                recordingForSubgoal = nil
                stopTimer()
            }

            if case .error(let message) = voiceService.state {
                await MainActor.run {
                    presentErrorMessage(message)
                    voiceService.resetTranscript()
                }
                return
            }

            let trimmed = voiceService.transcript.trimmed
            if !trimmed.isEmpty {
                await MainActor.run {
                    // Create transcript with subtask context
                    let contextualTranscript = "📎 \(subgoal.title): \(trimmed)"
                    let scope: ChatEntry.Scope = .subgoal(subgoal.id)
                    let entry = ChatEntry(content: contextualTranscript, isUser: true, scope: scope)
                    modelContext.insert(entry)
                    subgoal.updatedAt = Date()
                    goal.updatedAt = Date()
                    // Show transcript with subtask context - this creates its own UI
                    transcriptManager.presentTranscript(goalTitle: "\(goal.title) → \(subgoal.title)", text: trimmed)
                }
            }
        } else {
            // Start recording for this subtask
            guard !goal.isLocked else {
                await MainActor.run {
                    presentErrorMessage("Unlock the card to record")
                }
                return
            }

            // Cancel any existing recording
            await MainActor.run {
                voiceService.cancel()
                recordedTranscript = nil
                recordingStartedAt = nil
                stopTimer()
            }

            await voiceService.startRecording()
            await MainActor.run {
                recordingForSubgoal = subgoal
                recordingSubtaskId = subgoal.id
                recordingStartedAt = Date()
                recordingElapsed = 0
                startTimer()
            }
        }
    }

    private func toggleSubgoalCompletion(_ subgoal: Goal, target: Double) async {
        await MainActor.run {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                subgoal.progress = target
                subgoal.updatedAt = Date()
            }
        }

        if target >= 0.999 {
            await lifecycleService.complete(goal: subgoal, within: currentGoals(), modelContext: modelContext)
        }
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

    private func startTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if let start = self.recordingStartedAt {
                    self.recordingElapsed = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingElapsed = 0
    }

    private func startTimerIfNeeded() {
        if isRecording && recordingTimer == nil {
            startTimer()
        }
    }

    @ViewBuilder
    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            descriptionSection
            relationshipSection
            subgoalsSection
            metadataSection
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if !goal.content.isEmpty {
            Text(goal.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var relationshipSection: some View {
        if let parent = parentGoal {
            VStack(alignment: .leading, spacing: 12) {
                Text("Relations")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                relationshipRow(title: "Parent", goals: [parent])
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12), lineWidth: 0.8)
                    )
            )
        }
    }

    @ViewBuilder
    private func relationshipRow(title: String, goals: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(goals, id: \.id) { related in
                        relationshipChip(for: related)
                    }
                }
            }
        }
    }

    private func relationshipChip(for relatedGoal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(relatedGoal.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            ProgressView(value: relatedGoal.progress)
                .progressViewStyle(.linear)

            HStack(spacing: 6) {
                Image(systemName: "gauge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(relatedGoal.progress * 100))% • \(relatedGoal.priority.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12), lineWidth: 0.6)
                )
        )
    }

    @ViewBuilder
    private var subgoalsSection: some View {
        let subgoals = goal.sortedSubgoals
        let inlineLimit = 3
        let inlineSubgoals = Array(subgoals.prefix(inlineLimit))
        if !subgoals.isEmpty {
            let total = goal.allDescendants().count
            let atomic = goal.leafDescendants().count
            let depth = goal.subgoalTreeDepth()
            let dependencyCount = goal.allDescendants(includeSelf: true)
                .reduce(0) { $0 + $1.incomingDependencies.count }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subtasks")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Track every step right inside this card.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        MetricChip(icon: "list.bullet.rectangle", title: "Total", value: "\(total)")
                        MetricChip(icon: "circle.grid.2x2", title: "Atomic", value: "\(atomic)")
                        MetricChip(icon: "square.stack.3d.up", title: "Depth", value: "\(depth)")
                        if dependencyCount > 0 {
                            MetricChip(icon: "link", title: "Dependencies", value: "\(dependencyCount)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)

                SubtaskChecklistView(
                    subgoals: inlineSubgoals,
                    recordingSubtaskId: recordingSubtaskId,
                    onToggleCompletion: { subgoal, isComplete in
                        Task { await toggleSubgoalCompletion(subgoal, target: isComplete ? 1.0 : 0.0) }
                    },
                    onDelete: { subgoal in
                        Task { await deleteSubgoal(subgoal) }
                    },
                    onVoiceRecord: { subgoal in
                        Task { await recordVoiceForSubtask(subgoal) }
                    },
                    onShowDetail: { subgoal in
                        selectedSubgoalForDetail = subgoal
                    }
                )

                if subgoals.count > inlineLimit {
                    Button {
                        showAllSubtasksSheet = true
                    } label: {
                        Label("View all \(subgoals.count) subtasks", systemImage: "list.bullet.indent")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            .padding(.top, 8)
        }
    }

    private var metadataSection: some View {
        HStack {
            Label(goal.createdAt.timeAgo, systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            if goal.updatedAt != goal.createdAt {
                Text("Updated \(goal.updatedAt.timeAgo)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Actions
    private func toggleLock() {
        guard !isLocking else { return }
        
        Task {
            await MainActor.run { isLocking = true }
            
            if goal.isLocked {
                lifecycleService.unlock(goal: goal, reason: "User unlocked card")
            } else {
                let goalsSnapshot = currentGoals()
                await lifecycleService.lock(goal: goal, within: goalsSnapshot, modelContext: modelContext)
            }
            
            await MainActor.run {
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.impactOccurred()
                isLocking = false
            }
        }
    }

    private func handleActivationAction() async {
        if goal.activationState == .active {
            await lifecycleService.deactivate(goal: goal, reason: "User deactivated", modelContext: modelContext)
            await MainActor.run {
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.warning)
            }
            return
        }

        do {
            let goalsSnapshot = currentGoals()
            let plan = try await lifecycleService.generateActivationPlan(for: goal, within: goalsSnapshot)

            await MainActor.run {
                activationPlan = plan
                showActivationPreview = true
            }
        } catch {
            await MainActor.run {
                presentError(error)
            }
        }
    }

    private func confirmActivation(using plan: CalendarService.ActivationPlan) async {
        do {
            let goalsSnapshot = currentGoals()
            try await lifecycleService.confirmActivation(
                goal: goal,
                plan: plan,
                within: goalsSnapshot,
                modelContext: modelContext
            )

            await MainActor.run {
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
                dismissActivationPreview()
            }
        } catch {
            await MainActor.run {
                dismissActivationPreview()
                presentError(error)
            }
        }
    }

    private func dismissActivationPreview() {
        showActivationPreview = false
        activationPlan = nil
    }

    private func regenerateGoal() async {
        do {
            let goalsSnapshot = currentGoals()
            try await lifecycleService.regenerate(goal: goal, within: goalsSnapshot, modelContext: modelContext)
            await MainActor.run {
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        } catch {
            await MainActor.run {
                presentError(error)
            }
        }
    }
    
    private func summarizeProgress() async {
        do {
            let goalsSnapshot = currentGoals()
            let context = await userContextService.buildContext(from: goalsSnapshot)
            let response = try await aiService.summarizeProgress(for: goal, context: context)

            await MainActor.run {
                // Show summary in alert or sheet (for now just print)
                print("📊 Progress Summary for \(goal.title):")
                print(response)

                goal.updatedAt = Date()

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        } catch {
            print("❌ Failed to summarize: \(error)")
        }
    }

    private func deleteGoal() async {
        do {
            let goalsSnapshot = currentGoals()
            try await lifecycleService.delete(goal: goal, within: goalsSnapshot, modelContext: modelContext)

            await MainActor.run {
                // Haptic feedback for deletion
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
            }
        } catch {
            await MainActor.run {
                presentError(error)
            }
        }
    }

    @MainActor
    private func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
        showErrorAlert = true
    }

    @MainActor
    private func presentErrorMessage(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
    private func currentGoals() -> [Goal] {
        let descriptor = FetchDescriptor<Goal>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Supporting Views

struct PriorityBadge: View {
    let priority: Goal.Priority
    
    var color: Color {
        switch priority {
        case .now: return .red
        case .next: return .orange
        case .later: return .gray
        }
    }
    
    var icon: String {
        switch priority {
        case .now: return "flame.fill"
        case .next: return "clock.fill"
        case .later: return "calendar"
        }
    }
    
    var body: some View {
        Label(priority.rawValue, systemImage: icon)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct ActivationPreviewSheet: View {
    let goalTitle: String
    let plan: CalendarService.ActivationPlan
    let isProcessing: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activate \(goalTitle)")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Review the AI-suggested focus sessions before committing them to your calendar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.events) { event in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(event.title)
                                    .font(.headline)
                                Spacer()
                                Text(durationString(for: event.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Label(
                                    event.startDate.formatted(date: .abbreviated, time: .shortened),
                                    systemImage: "calendar.badge.clock"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if let slot = event.suggestedTimeSlot {
                                    Label(slot.capitalized, systemImage: "clock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let notes = event.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }

                            if let prep = event.preparation, !prep.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prep")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)

                                    ForEach(prep, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "checkmark.circle")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(item)
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }

            if !plan.tips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scheduling Tips")
                        .font(.footnote)
                        .fontWeight(.semibold)

                    ForEach(plan.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(tip)
                                .font(.caption2)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Text("Confirm Activation")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
        }
        .padding()
        .presentationDragIndicator(.visible)
    }

    private func durationString(for duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}

private struct MetricChip: View {
    let icon: String
    let title: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.2), lineWidth: 0.8)
                )
        )
    }
}

struct SubtaskChecklistView: View {
    let subgoals: [Goal]
    let level: Int
    let recordingSubtaskId: UUID?
    let onToggleCompletion: (Goal, Bool) -> Void
    let onDelete: (Goal) -> Void
    let onVoiceRecord: ((Goal) -> Void)?
    let onShowDetail: ((Goal) -> Void)?

    init(
        subgoals: [Goal],
        level: Int = 0,
        recordingSubtaskId: UUID? = nil,
        onToggleCompletion: @escaping (Goal, Bool) -> Void,
        onDelete: @escaping (Goal) -> Void,
        onVoiceRecord: ((Goal) -> Void)? = nil,
        onShowDetail: ((Goal) -> Void)? = nil
    ) {
        self.subgoals = subgoals
        self.level = level
        self.recordingSubtaskId = recordingSubtaskId
        self.onToggleCompletion = onToggleCompletion
        self.onDelete = onDelete
        self.onVoiceRecord = onVoiceRecord
        self.onShowDetail = onShowDetail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(subgoals) { subgoal in
                SubtaskChecklistRow(
                    subgoal: subgoal,
                    level: level,
                    recordingSubtaskId: recordingSubtaskId,
                    onToggleCompletion: onToggleCompletion,
                    onDelete: onDelete,
                    onVoiceRecord: onVoiceRecord,
                    onShowDetail: onShowDetail
                )
            }
        }
    }
}

private struct SubtaskChecklistRow: View {
    @Bindable var subgoal: Goal
    let level: Int
    let recordingSubtaskId: UUID?
    let onToggleCompletion: (Goal, Bool) -> Void
    let onDelete: (Goal) -> Void
    let onVoiceRecord: ((Goal) -> Void)?
    let onShowDetail: ((Goal) -> Void)?

    @State private var isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        subgoal: Goal,
        level: Int,
        recordingSubtaskId: UUID? = nil,
        onToggleCompletion: @escaping (Goal, Bool) -> Void,
        onDelete: @escaping (Goal) -> Void,
        onVoiceRecord: ((Goal) -> Void)? = nil,
        onShowDetail: ((Goal) -> Void)? = nil
    ) {
        self._subgoal = Bindable(subgoal)
        self.level = level
        self.recordingSubtaskId = recordingSubtaskId
        self.onToggleCompletion = onToggleCompletion
        self.onDelete = onDelete
        self.onVoiceRecord = onVoiceRecord
        self.onShowDetail = onShowDetail
        _isExpanded = State(initialValue: level < 1)
    }

    private var isComplete: Bool { subgoal.progress >= 0.999 }
    private var childSubgoals: [Goal] { subgoal.sortedSubgoals }
    private var detailPreview: String? {
        let trimmed = subgoal.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        return firstLines.prefix(2).joined(separator: " ")
    }
    private var blockerTitles: [String] {
        subgoal.incomingDependencies.compactMap { $0.prerequisite?.title }
    }
    private var unlockTitles: [String] {
        subgoal.outgoingDependencies.compactMap { $0.dependent?.title }
    }
    private var hasDependencyInfo: Bool {
        !(blockerTitles.isEmpty && unlockTitles.isEmpty)
    }
    private var accentTint: Color {
        subgoal.hasSubtasks ? .purple : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                completionToggle

                VStack(alignment: .leading, spacing: 10) {
                    titleBlock

                    if let detailPreview {
                        Text(detailPreview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    ProgressView(value: subgoal.progress)
                        .progressViewStyle(.linear)
                        .tint(isComplete ? .green : accentTint)

                    metaRow
                    dependencySummary
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    if let onVoiceRecord {
                        voiceButton(isRecording: recordingSubtaskId == subgoal.id, action: { onVoiceRecord(subgoal) })
                    }

                    lockButton

                    if !childSubgoals.isEmpty {
                        expandButton
                    }

                    deleteButton
                }
            }

            if isExpanded && !childSubgoals.isEmpty {
                SubtaskChecklistView(
                    subgoals: childSubgoals,
                    level: level + 1,
                    recordingSubtaskId: recordingSubtaskId,
                    onToggleCompletion: onToggleCompletion,
                    onDelete: onDelete,
                    onVoiceRecord: onVoiceRecord,
                    onShowDetail: onShowDetail
                )
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(colorScheme == .dark ? 0.85 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentTint.opacity(colorScheme == .dark ? 0.6 : 0.35), lineWidth: 1)
        )
        .shadow(color: accentTint.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.leading, level == 0 ? 0 : CGFloat(level) * 18)
        .contentShape(Rectangle())
        .onTapGesture {
            onShowDetail?(subgoal)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(subgoal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(subgoal.title)
                    .font(level == 0 ? .headline : .subheadline)
                    .fontWeight(level == 0 ? .semibold : .medium)
                    .foregroundStyle(isComplete ? .secondary : .primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .strikethrough(isComplete, color: .secondary.opacity(0.4))

                if subgoal.hasSubtasks {
                    Label("Nested", systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentTint.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundStyle(accentTint)
                }

                if subgoal.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            if subgoal.priority != .next {
                Text(subgoal.priority.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accentTint.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(accentTint)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            Label(subgoal.updatedAt.timeAgo, systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if subgoal.progress > 0 && subgoal.progress < 1 {
                Text("\(Int(subgoal.progress * 100))% done")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !subgoal.category.isEmpty {
                Text(subgoal.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var dependencySummary: some View {
        if hasDependencyInfo {
            VStack(alignment: .leading, spacing: 6) {
                if !blockerTitles.isEmpty {
                    dependencyChip(
                        icon: "exclamationmark.triangle.fill",
                        label: "Blocked by \(truncatedList(blockerTitles))",
                        tint: .orange
                    )
                }
                if !unlockTitles.isEmpty {
                    dependencyChip(
                        icon: "arrow.forward.circle.fill",
                        label: "Unlocks \(truncatedList(unlockTitles))",
                        tint: .blue
                    )
                }
            }
        }
    }

    private func dependencyChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    private func truncatedList(_ titles: [String]) -> String {
        guard !titles.isEmpty else { return "" }
        let unique = Array(Set(titles))
        if unique.count <= 2 {
            return unique.joined(separator: ", ")
        }
        return unique.prefix(2).joined(separator: ", ") + " (+\(unique.count - 2))"
    }

    private func toggleSubgoalLock() async {
        // This will be implemented to call the parent's locking mechanism
        // For now, we'll just toggle the state directly
        await MainActor.run {
            subgoal.isLocked.toggle()
            subgoal.updatedAt = Date()
        }
    }

    private var completionToggle: some View {
        Button {
            onToggleCompletion(subgoal, !isComplete)
        } label: {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green.opacity(0.22) : accentTint.opacity(0.16))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: isComplete ? "checkmark" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isComplete ? .green : accentTint)
            }
        }
        .buttonStyle(.plain)
    }

    private func voiceButton(isRecording: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isRecording ? .red : accentTint)
                .padding(7)
                .background(
                    Circle().fill(isRecording ? Color.red.opacity(0.12) : accentTint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record voice note")
    }

    private var expandButton: some View {
        Button {
            withAnimation(.smoothSpring) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .padding(7)
                .background(
                    Circle().fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse subtasks" : "Expand subtasks")
    }

    private var lockButton: some View {
        Button {
            Task { await toggleSubgoalLock() }
        } label: {
            Image(systemName: subgoal.isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(subgoal.isLocked ? .yellow : .primary.opacity(0.7))
                .padding(7)
                .background(
                    Circle().fill(subgoal.isLocked ? Color.yellow.opacity(0.12) : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subgoal.isLocked ? "Unlock subtask" : "Lock subtask")
    }

    private var deleteButton: some View {
        Button {
            onDelete(subgoal)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
                .padding(7)
                .background(
                    Circle().fill(Color.red.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SubtaskListSheet: View {
    let parentGoal: Goal
    let subgoals: [Goal]
    let recordingSubtaskId: UUID?
    let onToggleCompletion: (Goal, Bool) -> Void
    let onDelete: (Goal) -> Void
    let onVoiceRecord: ((Goal) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubgoal: Goal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if subgoals.isEmpty {
                        Text("No subtasks yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SubtaskChecklistView(
                            subgoals: subgoals,
                            recordingSubtaskId: recordingSubtaskId,
                            onToggleCompletion: onToggleCompletion,
                            onDelete: onDelete,
                            onVoiceRecord: onVoiceRecord,
                            onShowDetail: { subgoal in selectedSubgoal = subgoal }
                        )
                    }
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 24)
            }
            .navigationTitle("\(subgoals.count) Subtasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSubgoal) { subgoal in
                SubgoalDetailSheet(
                    subgoal: subgoal,
                    parentGoal: parentGoal,
                    onToggleCompletion: onToggleCompletion,
                    onDelete: { goal in
                        onDelete(goal)
                        dismiss()
                    },
                    onVoiceRecord: onVoiceRecord
                )
            }
        }
    }
}

private struct SubgoalDetailSheet: View {
    @Bindable var subgoal: Goal
    let parentGoal: Goal
    let onToggleCompletion: (Goal, Bool) -> Void
    let onDelete: (Goal) -> Void
    let onVoiceRecord: ((Goal) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    private var isComplete: Bool { subgoal.progress >= 0.999 }
    private var blockers: [GoalDependency] { subgoal.incomingDependencies }
    private var unlocks: [GoalDependency] { subgoal.outgoingDependencies }
    private var hasDependencies: Bool { !(blockers.isEmpty && unlocks.isEmpty) }
    private var trimmedContent: String { subgoal.content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if !trimmedContent.isEmpty {
                        detailSection(title: "Notes") {
                            Text(trimmedContent)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if hasDependencies {
                        dependencySection
                    }

                    detailSection(title: "Activity") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Created \(subgoal.createdAt.mediumDate)", systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if subgoal.updatedAt != subgoal.createdAt {
                                Label("Updated \(subgoal.updatedAt.timeAgo)", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let onVoiceRecord {
                        Button {
                            onVoiceRecord(subgoal)
                            dismiss()
                        } label: {
                            Label("Capture voice note", systemImage: "mic.fill")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete subtask", systemImage: "trash")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .navigationTitle(subgoal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(isComplete ? "Mark Incomplete" : "Mark Complete") {
                        onToggleCompletion(subgoal, !isComplete)
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove this subtask?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete(subgoal)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the subtask from \(parentGoal.title).")
        }
    }

    private var header: some View {
        detailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(parentGoal.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(subgoal.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                ProgressView(value: subgoal.progress)
                    .progressViewStyle(.linear)
                    .tint(isComplete ? .green : .blue)

                HStack(spacing: 12) {
                    Label("\(Int(subgoal.progress * 100))%", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(subgoal.priority.rawValue, systemImage: "flag")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if subgoal.isLocked {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
    }

    private var dependencySection: some View {
        detailSection(title: "Dependencies") {
            VStack(alignment: .leading, spacing: 16) {
                if !blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Blocked by")
                            .font(.subheadline.weight(.semibold))
                        ForEach(blockers) { dependency in
                            dependencyRow(for: dependency, direction: .blocker)
                        }
                    }
                }

                if !unlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Unlocks next")
                            .font(.subheadline.weight(.semibold))
                        ForEach(unlocks) { dependency in
                            dependencyRow(for: dependency, direction: .unlock)
                        }
                    }
                }

                dependencyExplainer
            }
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func dependencyRow(for dependency: GoalDependency, direction: DependencyDirection) -> some View {
        let targetTitle: String = {
            switch direction {
            case .blocker:
                return dependency.prerequisite?.title ?? "Unknown card"
            case .unlock:
                return dependency.dependent?.title ?? "Unknown card"
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: direction == .blocker ? "exclamationmark.triangle.fill" : "arrow.forward.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(direction == .blocker ? Color.orange : Color.blue)

                Text(targetTitle)
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(dependency.kind.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(dependency.kind.summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = dependency.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(direction == .blocker ? Color.orange.opacity(0.08) : Color.blue.opacity(0.08))
        )
    }

    private var dependencyExplainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How dependencies work", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Dependencies help Moss coordinate the order of your cards. A blocker must finish before this subtask can start, while unlocks kick off once this card moves. Use them to keep long projects flowing without micromanaging every date.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private enum DependencyDirection {
        case blocker
        case unlock
    }
}

private extension GoalDependency.Kind {
    var displayTitle: String {
        switch self {
        case .finishToStart: return "Finish to Start"
        case .startToStart: return "Start to Start"
        case .finishToFinish: return "Finish to Finish"
        }
    }

    var summary: String {
        switch self {
        case .finishToStart:
            return "Wait until the prerequisite is done before beginning."
        case .startToStart:
            return "Both cards kick off together once the prerequisite starts."
        case .finishToFinish:
            return "Both cards need to wrap up around the same time."
        }
    }
}

private extension Goal.ActivationState {
    struct Presentation {
        let title: String
        let icon: String
        let color: Color
    }

    var presentation: Presentation? {
        switch self {
        case .draft:
            return nil
        case .active:
            return Presentation(title: "Active", icon: "sparkles", color: .green)
        case .completed:
            return Presentation(title: "Completed", icon: "checkmark.seal.fill", color: .blue)
        case .archived:
            return Presentation(title: "Archived", icon: "archivebox.fill", color: .gray)
        }
    }
}