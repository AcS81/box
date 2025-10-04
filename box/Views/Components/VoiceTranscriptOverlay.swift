import SwiftUI
import Combine

@MainActor
final class VoiceTranscriptManager: ObservableObject {
    struct Entry: Identifiable, Equatable {
        enum Stage: Equatable {
            case active
            case held
            case fading
        }

        let id = UUID()
        let goalTitle: String
        let message: String
        let createdAt: Date
        var stage: Stage
        let displayDuration: TimeInterval
    }

    @Published private(set) var entries: [Entry] = []

    private var fadeTasks: [UUID: Task<Void, Never>] = [:]
    private var removalTasks: [UUID: Task<Void, Never>] = [:]

    private let maxVisibleEntries = 3
    private let fadeDuration: TimeInterval = 2.2
    private let holdBuffer: TimeInterval = 0.4

    func presentTranscript(goalTitle: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = Entry(
            goalTitle: goalTitle,
            message: trimmed,
            createdAt: Date(),
            stage: .active,
            displayDuration: displayDuration(for: trimmed)
        )

        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            entries.append(entry)
            enforceMaximum()
        }

        scheduleFade(for: entry.id, after: entry.displayDuration)
    }

    func beginHold(for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        guard entry.stage != .held else { return }
        entry.stage = .held
        cancelTimers(for: id)
        entries[index] = entry
    }

    func endHold(for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        entry.stage = .active
        entries[index] = entry
        scheduleFade(for: id, after: holdBuffer)
    }

    func refresh(for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        entry.stage = .active
        entries[index] = entry
        cancelTimers(for: id)
        scheduleFade(for: id, after: max(holdBuffer, entry.displayDuration * 0.6))
    }

    private func displayDuration(for text: String) -> TimeInterval {
        let baseDuration: TimeInterval = 4.0
        let scale: TimeInterval = 0.055
        return min(10.0, baseDuration + scale * Double(min(text.count, 200)))
    }

    private func enforceMaximum() {
        guard entries.count > maxVisibleEntries else { return }
        let surplus = entries.count - maxVisibleEntries
        let sorted = entries.sorted { $0.createdAt < $1.createdAt }
        for entry in sorted.prefix(surplus) {
            remove(entry.id)
        }
    }

    private func scheduleFade(for id: UUID, after delay: TimeInterval) {
        fadeTasks[id]?.cancel()
        fadeTasks[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self.transitionToFade(id)
            }
        }
    }

    private func transitionToFade(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].stage != .held else { return }

        withAnimation(.easeInOut(duration: fadeDuration)) {
            entries[index].stage = .fading
        }

        scheduleRemoval(for: id, after: fadeDuration)
    }

    private func scheduleRemoval(for id: UUID, after delay: TimeInterval) {
        removalTasks[id]?.cancel()
        removalTasks[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self.remove(id)
            }
        }
    }

    private func remove(_ id: UUID) {
        cancelTimers(for: id)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            _ = withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                entries.remove(at: index)
            }
        }
    }

    private func cancelTimers(for id: UUID) {
        fadeTasks[id]?.cancel()
        removalTasks[id]?.cancel()
        fadeTasks[id] = nil
        removalTasks[id] = nil
    }
}

struct VoiceTranscriptOverlay: View {
    @ObservedObject var manager: VoiceTranscriptManager

    var body: some View {
        VStack(spacing: 12) {
            ForEach(manager.entries) { entry in
                VoiceTranscriptBubble(entry: entry, manager: manager)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

private struct VoiceTranscriptBubble: View {
    let entry: VoiceTranscriptManager.Entry
    @ObservedObject var manager: VoiceTranscriptManager

    private var opacity: Double {
        switch entry.stage {
        case .active, .held:
            return 1.0
        case .fading:
            return 0.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text(entry.goalTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            Text(entry.message)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.3), value: opacity)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onChanged { _ in manager.beginHold(for: entry.id) }
                .onEnded { _ in manager.endHold(for: entry.id) }
        )
        .onTapGesture {
            manager.refresh(for: entry.id)
        }
    }
}

extension View {
    func voiceTranscriptOverlay(manager: VoiceTranscriptManager) -> some View {
        overlay(alignment: .bottom) {
            VoiceTranscriptOverlay(manager: manager)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .allowsHitTesting(true)
        }
    }
}

