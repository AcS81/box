import Foundation
import SwiftData

@Model
final class GeneralChatMessage {
    var id: UUID = UUID()
    var content: String
    var isUser: Bool
    var timestamp: Date

    init(content: String, isUser: Bool, timestamp: Date = .now) {
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

