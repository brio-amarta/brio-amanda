//
//  Client.swift
//  Kunang
//

import Foundation
import SwiftData

@Model
final class Client {
    /// Our own stable identifier. SwiftData supplies `id` / `persistentModelID`.
    var uuid: UUID = UUID()
    var name: String = ""
    var age: Int = 0
    var location: String = ""
    var phone: String = ""
    /// 0–10. Higher means better mental health in this community's scale.
    var mentalHealthScore: Double = 0
    var notes: String = ""

    /// Stored raw so SwiftData stays happy with lightweight migrations.
    var priorityRaw: String = Priority.others.rawValue
    var statusRaw: String = ClientStatus.newIntake.rawValue

    /// One-line explanation from the triage model.
    var triageReason: String = ""
    /// 1–10 urgency from the triage model, used as a scheduling tiebreak.
    var urgency: Int = 5
    var isInBali: Bool = false
    var triagedAt: Date?

    var scheduledAt: Date?
    var sessionLink: String?
    var completedAt: Date?
    var importedAt: Date = Date()

    var handler: Handler?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.client)
    var messages: [ChatMessage]? = []

    init(
        name: String,
        age: Int,
        location: String,
        phone: String = "",
        mentalHealthScore: Double = 0,
        notes: String = ""
    ) {
        self.uuid = UUID()
        self.name = name
        self.age = age
        self.location = location
        self.phone = phone
        self.mentalHealthScore = mentalHealthScore
        self.notes = notes
        self.isInBali = BaliRegion.isInBali(location)
        self.importedAt = .now
    }

    // MARK: - Convenience wrappers

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .others }
        set { priorityRaw = newValue.rawValue }
    }

    var status: ClientStatus {
        get { ClientStatus(rawValue: statusRaw) ?? .newIntake }
        set {
            statusRaw = newValue.rawValue
            if newValue == .completed, completedAt == nil { completedAt = .now }
            if newValue != .completed { completedAt = nil }
        }
    }

    var sortedMessages: [ChatMessage] {
        (messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// Demo thread — drafted and answered by the on-device model.
    var demoMessages: [ChatMessage] {
        sortedMessages.filter { !$0.isLive }
    }

    /// Live thread — messages that really went out, plus replies the owner
    /// logged after reading them in WhatsApp or Messages.
    var liveMessages: [ChatMessage] {
        sortedMessages.filter(\.isLive)
    }

    var hasLiveConversation: Bool { !liveMessages.isEmpty }

    /// When the client last wrote back on the live thread. Used as the
    /// starting point when polling a relay for new inbound messages.
    var lastLiveInboundAt: Date? {
        liveMessages.last { !$0.isFromOwner }?.timestamp
    }

    var hasResponded: Bool {
        (messages ?? []).contains { $0.isFromOwner }
    }

    var hasUsablePhone: Bool {
        PhoneNumber.e164(phone) != nil
    }

    var scheduleDescription: String {
        guard let scheduledAt else { return "—" }
        return scheduledAt.formatted(date: .abbreviated, time: .shortened)
    }

    var scoreDescription: String {
        String(format: "%.1f", mentalHealthScore)
    }

    /// Non-optional stand-in so the schedule table can sort by session time.
    /// Unbooked people sort to the bottom.
    var sortDate: Date {
        scheduledAt ?? .distantFuture
    }

    /// Sortable rank for the priority column.
    var priorityRank: Int { priority.rank }

    /// Sortable handler name; unassigned people sort last.
    var handlerName: String { handler?.name ?? "—" }
}
