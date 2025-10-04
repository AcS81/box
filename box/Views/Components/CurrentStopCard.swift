//
//  CurrentStopCard.swift
//  box
//
//  Created on 03.10.2025.
//

import SwiftUI

struct CurrentStopCard: View {
    @Bindable var goal: Goal
    let onComplete: () -> Void

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedOutcome: String = ""
    @State private var editedDate: Date = Date()
    @State private var contextualInput: String = ""
    @State private var showInputField: Bool = false

    private var currentStep: Goal? {
        goal.currentSequentialStep
    }

    var body: some View {
        if let step = currentStep {
            VStack(alignment: .leading, spacing: 20) {
                header(for: step)

                if isEditing {
                    editModeContent(for: step)
                } else {
                    viewModeContent(for: step)
                }

                actionButtons(for: step)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 2)
            )
            .onAppear {
                editedTitle = step.title
                editedOutcome = step.outcome
                editedDate = step.targetDate ?? Date()
            }
        } else {
            emptyState
        }
    }

    private func header(for step: Goal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Step \(step.orderIndexInParent + 1)", systemImage: "play.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                if let targetDate = step.targetDate {
                    Text(formatDate(targetDate))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            Text(step.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func viewModeContent(for step: Goal) -> some View {
        // Contextual input field (optional, collapsible)
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInputField.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showInputField ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("✏️ Your Input (preferences, constraints, data...)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            if showInputField {
                VStack(alignment: .leading, spacing: 12) {
                    // Show existing user inputs
                    if let step = currentStep, !step.userInputs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(step.userInputs.enumerated()), id: \.offset) { index, input in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.blue)
                                    Text(input)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    // Input field + Append button
                    if let step = currentStep {
                        HStack(spacing: 8) {
                            TextField("e.g., 8pm-10pm: study time, Budget: $340k", text: $contextualInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)

                            Button {
                                appendUserInput(to: step)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(contextualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Text("These inputs will inform the AI when generating future steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))

        VStack(alignment: .leading, spacing: 8) {
            Label("Outcome", systemImage: "flag.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

            Text(step.outcome)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))

        if !step.content.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("💡 AI Thinks (How to do it)", systemImage: "lightbulb.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)

                Text(step.content)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func editModeContent(for step: Goal) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                TextField("Step title", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Outcome")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                TextEditor(text: $editedOutcome)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Target Date")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                DatePicker("Target Date", selection: $editedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for step: Goal) -> some View {
        if isEditing {
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        isEditing = false
                    }
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    saveEdits(to: step)
                } label: {
                    Text("Save Changes")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        isEditing = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                            .font(.headline)
                        Text("Edit")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    onComplete()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.headline)
                        Text("Mark Complete")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func saveEdits(to step: Goal) {
        step.title = editedTitle
        step.outcome = editedOutcome
        step.targetDate = editedDate
        goal.updatedAt = Date()

        withAnimation {
            isEditing = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All steps completed!")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("You've reached the end of this journey.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.green.opacity(0.1))
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func appendUserInput(to step: Goal) {
        // Append user input to the list
        step.appendUserInput(contextualInput)
        goal.updatedAt = Date()

        // Clear input field (keep field visible for more inputs)
        contextualInput = ""
    }
}

#Preview {
    let goal = Goal(title: "Build iOS App", priority: .now)
    goal.activationState = .active

    let step = goal.createSequentialStep(
        title: "Create MVP Prototype",
        outcome: "Working demo with core features X, Y, Z implemented",
        targetDate: Date().addingTimeInterval(7*86400)
    )
    step.stepStatus = .current
    step.content = "Focus on building the essential screens and connecting them together. Get the basic flow working before adding polish."

    return CurrentStopCard(goal: goal, onComplete: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
