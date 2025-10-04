//
//  GanttTimelineView.swift
//  box
//
//  Created on 03.10.2025.
//

import SwiftUI

struct GanttTimelineView: View {
    let goal: Goal
    let onStopTap: ((Goal) -> Void)?

    private var steps: [Goal] {
        goal.sequentialSteps
    }

    private var timelineRange: (start: Date, end: Date) {
        guard let firstStep = steps.first else {
            return (Date(), Date().addingTimeInterval(30 * 86400))
        }

        let start = Calendar.current.startOfDay(for: firstStep.createdAt)

        // End is either last step's target date + buffer, or estimated future
        var end: Date
        if let lastStep = steps.last, let targetDate = lastStep.targetDate {
            end = targetDate
            // Add buffer for unknown future steps (up to 10 total)
            let remainingSteps = max(0, 10 - steps.count)
            let daysToAdd = max(7, remainingSteps * 7)
            end = Calendar.current.date(byAdding: .day, value: daysToAdd, to: end) ?? end
        } else {
            end = Calendar.current.date(byAdding: .day, value: 60, to: start) ?? start
        }

        return (start, end)
    }

    private var totalDays: Int {
        let interval = timelineRange.end.timeIntervalSince(timelineRange.start)
        return max(1, Int(interval / 86400))
    }

    private var todayPosition: Double {
        let now = Date()
        let start = timelineRange.start
        let total = timelineRange.end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            timeAxisView
            ganttBarsView
            legendSection
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline")
                    .font(.headline)
                    .fontWeight(.bold)

                Text("\(steps.count) steps • \(totalDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let currentStep = goal.currentSequentialStep {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(currentStep.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
    }

    private var timeAxisView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Background line
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 2)

                // Today marker
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 2, height: 24)
                    .offset(x: width * todayPosition, y: -11)

                // Date labels
                HStack {
                    Text(formatDate(timelineRange.start))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if todayPosition > 0.1 && todayPosition < 0.9 {
                        Text("Today")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                            .offset(x: width * todayPosition - 20)
                    }

                    Spacer()

                    Text(formatDate(timelineRange.end))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .offset(y: 20)
            }
        }
        .frame(height: 50)
    }

    private var ganttBarsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                GanttBarRow(
                    step: step,
                    stepNumber: index + 1,
                    totalSteps: steps.count,
                    timelineStart: timelineRange.start,
                    timelineEnd: timelineRange.end,
                    onTap: { onStopTap?(step) }
                )
            }
        }
    }

    private var legendSection: some View {
        HStack(spacing: 16) {
            LegendItem(color: .green, label: "Completed")
            LegendItem(color: .orange, label: "Current")
            LegendItem(color: .gray.opacity(0.3), label: "Future")
        }
        .font(.caption2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct GanttBarRow: View {
    let step: Goal
    let stepNumber: Int
    let totalSteps: Int
    let timelineStart: Date
    let timelineEnd: Date
    let onTap: () -> Void

    private var cumulativePercentage: Int {
        Int((Double(stepNumber) / Double(totalSteps)) * 100)
    }

    private var barPosition: (start: Double, width: Double) {
        let totalInterval = timelineEnd.timeIntervalSince(timelineStart)

        // Start position
        let stepStart = step.createdAt
        let startOffset = stepStart.timeIntervalSince(timelineStart)
        let startPercent = max(0, min(1, startOffset / totalInterval))

        // End date: use actual completion date if completed, otherwise use target date
        let stepEnd: Date
        if step.stepStatus == .completed, let completedDate = step.completedAt {
            // For completed steps, use actual completion date
            stepEnd = completedDate
        } else if let targetDate = step.targetDate {
            // For pending/current steps, use projected target date
            stepEnd = targetDate
        } else {
            // Fallback: minimal width if no date available
            return (startPercent, 0.05)
        }

        let duration = stepEnd.timeIntervalSince(stepStart)
        let widthPercent = max(0.02, min(1 - startPercent, duration / totalInterval))

        return (startPercent, widthPercent)
    }

    private var barColor: Color {
        switch step.stepStatus {
        case .completed: return .green
        case .current: return .orange
        case .pending: return .gray.opacity(0.3)
        case .unknown: return .purple.opacity(0.3)
        }
    }

    private var statusIcon: String {
        switch step.stepStatus {
        case .completed: return "checkmark.circle.fill"
        case .current: return "play.circle.fill"
        case .pending: return "lock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.caption)
                    .foregroundStyle(barColor)

                Text(step.title)
                    .font(.subheadline)
                    .fontWeight(step.stepStatus == .current ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Show actual completion date for completed steps, target date for others
                if step.stepStatus == .completed, let completedDate = step.completedAt {
                    Text(formatDate(completedDate))
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let targetDate = step.targetDate {
                    Text(formatDate(targetDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(cumulativePercentage)%")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(barColor)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let barStart = width * barPosition.start
                let barWidth = width * barPosition.width

                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 12)

                    // Step bar
                    RoundedRectangle(cornerRadius: 6)
                        .fill(barColor)
                        .frame(width: max(8, barWidth), height: 12)
                        .offset(x: barStart)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(barColor.opacity(0.5), lineWidth: 1)
                                .frame(width: max(8, barWidth), height: 12)
                                .offset(x: barStart)
                        )
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 16, height: 8)

            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

private func createPreviewGoal() -> Goal {
    let goal = Goal(title: "Build iOS App", priority: .now)
    goal.activationState = .active

    let step1 = goal.createSequentialStep(
        title: "Research & Planning",
        outcome: "Clear requirements",
        targetDate: Date().addingTimeInterval(7*86400)
    )
    step1.stepStatus = .completed
    step1.progress = 1.0

    let step2 = goal.createSequentialStep(
        title: "Design Prototype",
        outcome: "MVP design ready",
        targetDate: Date().addingTimeInterval(14*86400)
    )
    step2.stepStatus = .current
    step2.progress = 0.6

    let step3 = goal.createSequentialStep(
        title: "Build Core Features",
        outcome: "Working app",
        targetDate: Date().addingTimeInterval(28*86400)
    )
    step3.stepStatus = .pending

    return goal
}

#Preview {
    GanttTimelineView(goal: createPreviewGoal(), onStopTap: { _ in })
        .padding()
        .background(Color(.systemGroupedBackground))
}
