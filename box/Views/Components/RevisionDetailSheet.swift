//
//  RevisionDetailSheet.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import SwiftData

struct RevisionDetailSheet: View {
    let revision: GoalRevision

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with icon
                    HStack(spacing: 12) {
                        Image(systemName: iconForRevision)
                            .font(.title)
                            .foregroundStyle(.blue)
                            .frame(width: 50, height: 50)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(revision.summary)
                                .font(.headline)

                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Rationale
                    if let rationale = revision.rationale {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Reason", systemImage: "text.alignleft")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(rationale)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.panelBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Snapshot data if available
                    if let snapshot = revision.snapshot {
                        snapshotSection(snapshot)
                    }

                    // Metadata
                    metadataSection
                }
                .padding()
            }
            .navigationTitle("Event Details")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
#endif
        }
    }

    @ViewBuilder
    private func snapshotSection(_ snapshot: GoalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Snapshot", systemImage: "camera.viewfinder")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "Title", value: snapshot.title)
                infoRow(label: "Content", value: snapshot.content.isEmpty ? "No description" : snapshot.content)
                infoRow(label: "Category", value: snapshot.category)
                infoRow(label: "Priority", value: snapshot.priority)
                infoRow(label: "Progress", value: "\(Int(snapshot.progress * 100))%")
            }
            .padding()
            .background(Color.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Metadata", systemImage: "info.circle")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "Event ID", value: revision.id.uuidString.prefix(8).uppercased())
                let goalIdText = revision.goalId.map { String($0.uuidString.prefix(8)).uppercased() } ?? "Unknown"
                infoRow(label: "Goal ID", value: goalIdText)
                infoRow(label: "Timestamp", value: revision.createdAt.formatted(date: .long, time: .standard))
            }
            .padding()
            .background(Color.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var iconForRevision: String {
        let summary = revision.summary.lowercased()

        if summary.contains("created") {
            return "sparkles"
        } else if summary.contains("locked") {
            return "lock.fill"
        } else if summary.contains("unlocked") {
            return "lock.open"
        } else if summary.contains("activated") {
            return "bolt.fill"
        } else if summary.contains("deactivated") || summary.contains("moved to") {
            return "pause.fill"
        } else if summary.contains("complete") {
            return "checkmark.seal.fill"
        } else if summary.contains("regenerated") {
            return "arrow.clockwise"
        } else if summary.contains("autopilot") {
            return "sparkles"
        } else {
            return "circle.fill"
        }
    }
}