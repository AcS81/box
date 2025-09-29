//
//  SecretsService.swift
//  box
//
//  Created on 29.09.2025.
//

import Combine
import Foundation
import Security

@MainActor
final class SecretsService: ObservableObject {
    static let shared = SecretsService()

    @Published private(set) var openAIKey: String?

    private init() {
        openAIKey = try? Self.loadKey()
    }

    func updateOpenAIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmed, !trimmed.isEmpty {
            do {
                try Self.saveKey(trimmed)
                openAIKey = trimmed
            } catch {
                print("🔐 Failed to store OpenAI key: \(error)")
            }
        } else {
            do {
                try Self.deleteKey()
                openAIKey = nil
            } catch {
                print("🔐 Failed to delete OpenAI key: \(error)")
            }
        }
    }

    func clearAll() {
        do {
            try Self.deleteKey()
            openAIKey = nil
        } catch {
            print("🔐 Failed to clear secrets: \(error)")
        }
    }

    // MARK: - Keychain Helpers

    private static let service = "com.youandgoals.openai"
    private static let account = "api-key"

    private enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error: \(status)"
            }
        }
    }

    private static func loadKey() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            if let data = item as? Data, let key = String(data: data, encoding: .utf8) {
                return key
            }
            return nil
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func saveKey(_ key: String) throws {
        try deleteKey()

        let data = Data(key.utf8)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func deleteKey() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}


