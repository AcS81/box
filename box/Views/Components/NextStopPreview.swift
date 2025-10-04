//
//  NextStopPreview.swift
//  box
//
//  Created on 03.10.2025.
//

import SwiftUI

struct NextStopPreview: View {
    let goal: Goal

    private var nextStep: Goal? {
        goal.nextSequentialStep
    }

    var body: some View {
        if let step = nextStep {
            VStack(alignment: .leading, spacing: 12) {
                header
                stepInfo(for: step)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        } else {
            emptyPreview
        }
    }

    private var header: some View {
        HStack {
            Label("Next Step", systemImage: "arrow.right.circle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.gray)

            Spacer()

            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.6))
        }
    }

    private func stepInfo(for step: Goal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                if let targetDate = step.targetDate {
                    Text(formatDate(targetDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(step.outcome)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var emptyPreview: some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.gray)

            Text("No more steps planned")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    let goal = Goal(title: "Build iOS App", priority: .now)
    goal.activationState = .active

    _ = goal.createSequentialStep(
        title: "Current Step",
        outcome: "Working on this now",
        targetDate: Date()
    )

    let nextStep = goal.createSequentialStep(
        title: "User Testing Phase",
        outcome: "Gather feedback from 20+ beta testers and identify improvements",
        targetDate: Date().addingTimeInterval(14*86400)
    )
    nextStep.stepStatus = .pending

    return NextStopPreview(goal: goal)
        .padding()
        .background(Color(.systemGroupedBackground))
}
