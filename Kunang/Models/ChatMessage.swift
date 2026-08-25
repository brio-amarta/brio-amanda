//
//  ChatMessage.swift
//  Kunang
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

    /// False for demo messages, true for anything that really left the iPad
    /// — or that the owner transcribed from a real conversation.
    var isLive: Bool = false
    /// Which channel carried it. Empty for demo messages.
    var channelRaw: String = ""
    /// Where this message got to. See MessageDelivery.
    var deliveryRaw: String = MessageDelivery.simulated.rawValue

    var client: Client?

    init(
        text: String,
        isFromOwner: Bool,
        isGenerated: Bool = false,
        isLive: Bool = false,
        channel: MessagingChannel? = nil,
        delivery: MessageDelivery = .simulated,
        timestamp: Date = .now
    ) {
        self.uuid = UUID()
        self.text = text
        self.isFromOwner = isFromOwner
        self.isGenerated = isGenerated
        self.isLive = isLive
        self.channelRaw = channel?.rawValue ?? ""
        self.deliveryRaw = delivery.rawValue
        self.timestamp = timestamp
    }

    // MARK: - Convenience wrappers

    var channel: MessagingChannel? {
        get { MessagingChannel(rawValue: channelRaw) }
        set { channelRaw = newValue?.rawValue ?? "" }
    }

    var delivery: MessageDelivery {
        get { MessageDelivery(rawValue: deliveryRaw) ?? .simulated }
        set { deliveryRaw = newValue.rawValue }
    }

    /// Handed to another app but never confirmed — the chat offers a
    /// "mark as sent" tick for these.
    var needsConfirmation: Bool {
        isLive && isFromOwner && delivery == .handedOff
    }
}
