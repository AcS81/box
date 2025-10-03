//
//  AsyncActionStatus.swift
//  box
//
//  Created on 29.09.2025.
//

import SwiftUI

enum AsyncActionStatus: Equatable {
    case idle
    case running
    case success(message: String? = nil)
    case failure(message: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "Working…"
        case .success(let message):
            return message ?? "Done"
        case .failure(let message):
            return message
        }
    }

    var systemImage: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
}

