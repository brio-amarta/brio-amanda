//
//  ChatMessage.swift
//  Mentalzz
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    /// Our own stable identifier. SwiftData supplies `id` / `persistentModelID`.
    var uuid: UUID = UUID()
    var text: String = ""
    /// True when the community sent it, false when it came from the client.
    var isFromOwner: Bool = true
    var timestamp: Date = Date()
    /// Marks messages produced by the on-device model rather than typed by hand.
    var isGenerated: Bool = false

    var client: Client?

    init(text: String, isFromOwner: Bool, isGenerated: Bool = false, timestamp: Date = .now) {
        self.uuid = UUID()
        self.text = text
        self.isFromOwner = isFromOwner
        self.isGenerated = isGenerated
        self.timestamp = timestamp
    }
}
