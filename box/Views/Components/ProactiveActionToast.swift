//
//  ProactiveActionToast.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI
import Combine

struct ProactiveActionToast: View {
    let message: String
    let type: ToastType
    let onDismiss: () -> Void

    @State private var isShowing = false

    enum ToastType {
        case info
        case success
        case working

        var icon: String {
            switch self {
            case .info: return "lightbulb.fill"
            case .success: return "checkmark.circle.fill"
            case .working: return "sparkles"
            }
        }

        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .working: return .purple
            }
        }
    }

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(type.color)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            .padding(.horizontal)
            .padding(.bottom, 20)
            .offset(y: isShowing ? 0 : 100)
            .opacity(isShowing ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isShowing = true
            }

            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isShowing = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Toast Manager

@MainActor
class ProactiveToastManager: ObservableObject {
    @Published var currentToast: ToastData?

    struct ToastData: Identifiable {
        let id = UUID()
        let message: String
        let type: ProactiveActionToast.ToastType
    }

    func show(message: String, type: ProactiveActionToast.ToastType = .info) {
        currentToast = ToastData(message: message, type: type)
    }

    func dismiss() {
        currentToast = nil
    }
}

// MARK: - View Extension

extension View {
    func proactiveToast(manager: ProactiveToastManager) -> some View {
        ZStack {
            self

            if let toast = manager.currentToast {
                ProactiveActionToast(
                    message: toast.message,
                    type: toast.type,
                    onDismiss: { manager.dismiss() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }
}