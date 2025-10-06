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
    let isGenerating: Bool  // Loading state from parent

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

                // Show children if this step is a parent
                if step.hasSubtasks {
                    childrenSection(for: step)
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
                    .stroke(step.hasSubtasks ? Color.blue.opacity(0.4) : Color.orange.opacity(0.3), lineWidth: 2)
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
                Label("Step \(step.orderIndexInParent + 1)", systemImage: step.hasSubtasks ? "folder.fill" : "play.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(step.hasSubtasks ? .blue : .orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background((step.hasSubtasks ? Color.blue : Color.orange).opacity(0.15))
                    .clipShape(Capsule())

                if step.hasSubtasks {
                    Label("Group", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }

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
    private func childrenSection(for step: Goal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Contains \(step.sortedSubgoals.count) sub-steps")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 10) {
                ForEach(step.sortedSubgoals) { child in
                    childStepRow(child)
                }
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(0.05))
        )
    }

    private func childStepRow(_ child: Goal) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(child.stepStatus == .completed ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: child.stepStatus == .completed ? "checkmark.circle.fill" : child.stepStatus.icon)
                    .font(.caption)
                    .foregroundStyle(child.stepStatus == .completed ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(child.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(child.stepStatus == .completed ? .secondary : .primary)
                    .strikethrough(child.stepStatus == .completed)

                if !child.outcome.isEmpty {
                    Text(child.outcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let targetDate = child.targetDate {
                    Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if child.stepStatus == .completed {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("Generating Next Step...")
                                .font(.headline)
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.headline)
                            Text("Mark Complete")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isGenerating ? Color.orange.opacity(0.6) : Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
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

        // NOTE: User inputs affect future step generation
        // The next time we run low on steps (pendingCount <= 1),
        // handleStopCompletion will automatically regenerate using this new context
        print("✏️ User added input: \(contextualInput) - will affect next step generation")
    }
}

#Preview {
    @Previewable @State var goal: Goal = {
        let g = Goal(title: "Build iOS App", priority: .now)
        g.activationState = .active
        let step = g.createSequentialStep(
            title: "Create MVP Prototype",
            outcome: "Working demo with core features X, Y, Z implemented",
            targetDate: Date().addingTimeInterval(7*86400)
        )
        step.stepStatus = .current
        step.content = "Focus on building the essential screens and connecting them together. Get the basic flow working before adding polish."
        return g
    }()

    CurrentStopCard(goal: goal, onComplete: {}, isGenerating: false)
        .padding()
        .background(Color(.systemGroupedBackground))
}
