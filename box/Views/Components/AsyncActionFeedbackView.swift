//
//  AsyncActionFeedbackView.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import Combine

struct AsyncActionFeedbackView: View {
    let status: AsyncActionStatus
    var idleMessage: String? = nil

    var body: some View {
        Group {
            switch status {
            case .idle:
                if let idleMessage {
                    Label(idleMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            case .running:
                Label(status.message ?? "Working…", systemImage: status.systemImage ?? "hourglass")
                    .foregroundStyle(status.tint)
            case .success, .failure:
                if let message = status.message, let icon = status.systemImage {
                    Label(message, systemImage: icon)
                        .foregroundStyle(status.tint)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .opacity(status == .idle && idleMessage == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: status)
    }
}

#Preview {
    VStack(spacing: 12) {
        AsyncActionFeedbackView(status: .idle, idleMessage: "Ready")
        AsyncActionFeedbackView(status: .running)
        AsyncActionFeedbackView(status: .success(message: "Goal added"))
        AsyncActionFeedbackView(status: .failure(message: "Try again"))
    }
    .padding()
}


