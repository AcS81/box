//
//  StopProgressBar.swift
//  box
//
//  Created on 03.10.2025.
//

import SwiftUI

struct StopProgressBar: View {
    let goal: Goal

    private var steps: [Goal] {
        goal.sequentialSteps
    }

    private var hasSteps: Bool {
        !steps.isEmpty
    }

    private var targetStepCount: Int {
        // Use 10 as baseline target, but show actual if exceeds
        max(10, steps.count)
    }

    private var unknownStepsCount: Int {
        // Only show unknown steps if under target
        steps.count < 10 ? max(0, 10 - steps.count) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasSteps {
                stepsTimeline
                dateLabels
                progressLabel
            } else {
                placeholderBar
            }
        }
    }

    private var stepsTimeline: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let displaySegments = unknownStepsCount > 0 ? steps.count + 1 : steps.count
            let stepWidth = totalWidth / CGFloat(displaySegments)

            HStack(spacing: 0) {
                // Known steps (completed or current)
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    StepSegment(
                        step: step,
                        stepNumber: index + 1,
                        totalSteps: steps.count,
                        targetTotal: targetStepCount,
                        width: stepWidth,
                        isFirst: index == 0,
                        isLast: index == steps.count - 1 && unknownStepsCount == 0
                    )
                }

                // Unknown future steps (question marks) - only if under target
                if unknownStepsCount > 0 {
                    QuestionMarkSegment(width: stepWidth, label: "?", isFinal: true)
                }
            }
        }
        .frame(height: 50)
    }

    private var dateLabels: some View {
        HStack {
            if let firstStep = steps.first, let targetDate = firstStep.targetDate {
                Text(formatDate(targetDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if steps.count < 10 {
                Text("TBD")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressLabel: some View {
        HStack {
            if steps.count > 10 {
                // Show warning for excessive steps
                Text("\(steps.count) steps (consider splitting goal)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            } else {
                Text("\(steps.count)/\(targetStepCount) steps")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let currentStep = goal.currentSequentialStep {
                Text("\(Int(currentStep.progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var placeholderBar: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 50)

            Text("No roadmap yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct StepSegment: View {
    let step: Goal
    let stepNumber: Int
    let totalSteps: Int
    let targetTotal: Int
    let width: CGFloat
    let isFirst: Bool
    let isLast: Bool

    private var cumulativePercentage: Int {
        // Cumulative progress: completed steps + current step's progress
        // Formula: (steps_before_this + this_step_progress) / total_steps * 100
        let stepsCompleted = Double(stepNumber - 1)  // Steps before this one
        let currentProgress = step.progress           // This step's progress (0.0 to 1.0)
        let total = Double(totalSteps)
        let cumulative = ((stepsCompleted + currentProgress) / total) * 100
        return min(100, Int(cumulative))
    }

    private var fillColor: Color {
        switch step.stepStatus {
        case .completed: return .green
        case .current: return .orange
        case .pending: return .gray.opacity(0.3)
        case .unknown: return .purple.opacity(0.3)
        }
    }

    private var borderColor: Color {
        switch step.stepStatus {
        case .completed: return .green.opacity(0.8)
        case .current: return .orange.opacity(0.8)
        case .pending: return .gray.opacity(0.5)
        case .unknown: return .purple.opacity(0.5)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Segment bar
            RoundedRectangle(cornerRadius: isFirst || isLast ? 8 : 0)
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .stroke(borderColor, lineWidth: 1)
                )
                .frame(width: width, height: 40)
                .overlay(
                    VStack(spacing: 2) {
                        // Status icon
                        Image(systemName: step.stepStatus.icon)
                            .font(.caption2)
                            .foregroundStyle(step.stepStatus == .pending ? .gray : .white)

                        // Cumulative percentage
                        Text("\(cumulativePercentage)%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(step.stepStatus == .pending ? .gray : .white)
                    }
                )

            // Step number
            Text("Step \(stepNumber)")
                .font(.caption2)
                .fontWeight(step.stepStatus == .current ? .semibold : .regular)
                .foregroundStyle(step.stepStatus == .current ? .orange : .secondary)
        }
        .frame(width: width)
    }
}

private struct QuestionMarkSegment: View {
    let width: CGFloat
    let label: String
    var isFinal: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.gray.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
                .frame(width: width, height: 40)
                .overlay(
                    Text(label)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                )

            Text(isFinal ? "Future" : "TBD")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: width)
    }
}

#Preview {
    let goal = Goal(title: "Sample Goal", priority: .now)
    goal.activationState = .active

    let step1 = goal.createSequentialStep(
        title: "Research",
        outcome: "Gather requirements",
        targetDate: Date()
    )
    step1.stepStatus = .completed
    step1.progress = 1.0

    let step2 = goal.createSequentialStep(
        title: "Design",
        outcome: "Create mockups",
        targetDate: Date().addingTimeInterval(7*86400)
    )
    step2.stepStatus = .completed
    step2.progress = 1.0

    let step3 = goal.createSequentialStep(
        title: "Build",
        outcome: "Implement features",
        targetDate: Date().addingTimeInterval(14*86400)
    )
    step3.stepStatus = .current
    step3.progress = 0.6

    let step4 = goal.createSequentialStep(
        title: "Test",
        outcome: "QA and fixes",
        targetDate: Date().addingTimeInterval(21*86400)
    )
    step4.stepStatus = .pending

    return StopProgressBar(goal: goal)
        .padding()
        .background(Color(.systemBackground))
}
