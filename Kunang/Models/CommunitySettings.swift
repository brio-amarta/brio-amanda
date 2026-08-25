//
//  CommunitySettings.swift
//  Kunang
//
//  Everything the owner can change about how the community runs: opening
//  hours, how long a session lasts, how many fit in a day, and how messages
//  actually leave the iPad.
//
//  There is exactly one of these rows. `current(in:)` makes it on first launch.
//

import Foundation
import SwiftData

@Model
final class CommunitySettings {

    // MARK: - Community hours

    var openingHour: Int = 8
    var openingMinute: Int = 0
    var closingHour: Int = 17
    var closingMinute: Int = 0

    /// How long one session runs, in minutes.
    var sessionMinutes: Int = 90
    /// Gap between the end of one session and the start of the next.
    var breakMinutes: Int = 0
    /// How many sessions the owner wants to run per working day.
    var slotsPerDay: Int = 6
    /// Set false to also book weekends.
    var weekdaysOnly: Bool = true

    // MARK: - Demo chat

    /// Lower bound of the pause before a simulated client reply lands.
    var replyDelayMinSeconds: Double = 3
    /// Upper bound of that pause.
    var replyDelayMaxSeconds: Double = 8

    // MARK: - Messaging

    /// Which channel Live mode hands messages to.
    var messagingChannelRaw: String = MessagingChannel.whatsApp.rawValue
    /// Dialling code assumed when a client's number has no country prefix.
    var defaultCountryCode: String = "62"
    /// Base URL of the owner's own relay server. Empty until they host one.
    /// The Meta access token lives there, never in this app.
    var relayBaseURL: String = ""

    /// The number registered on the Cloud API, in digits-only E.164.
    static let defaultCommunityNumber = "6287864894065"

    /// Numbers that shipped as the default in an earlier build and are no
    /// longer reachable. Anyone upgrading still has one of these saved, so
    /// they get swapped for the current number on launch.
    static let retiredCommunityNumbers = ["6282338514166"]

    /// The community's WhatsApp Business number — the one registered on the
    /// Cloud API, not a personal number. Anyone who messages it turns up in
    /// the app: known senders land in their own chat, unknown ones arrive as
    /// a new intake.
    var communityWhatsAppNumber: String = CommunitySettings.defaultCommunityNumber

    /// Watermark for inbox polling, so the same message is never imported twice.
    var lastInboxSyncAt: Date?

    var updatedAt: Date = Date()

    init() {}

    // MARK: - Singleton access

    /// Fetches the one settings row, creating it the first time.
    static func current(in context: ModelContext) -> CommunitySettings {
        let descriptor = FetchDescriptor<CommunitySettings>()
        if let existing = try? context.fetch(descriptor).first {
            existing.retireDeadCommunityNumber(in: context)
            return existing
        }
        let fresh = CommunitySettings()
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    /// Swaps a number that used to be the default for the current one. Without
    /// this, upgrading leaves the old value in place and inbound silently
    /// points at a number nobody can reach.
    private func retireDeadCommunityNumber(in context: ModelContext) {
        let digits = communityWhatsAppNumber.filter(\.isNumber)
        guard Self.retiredCommunityNumbers.contains(digits) else { return }
        communityWhatsAppNumber = Self.defaultCommunityNumber
        try? context.save()
    }

    // MARK: - Derived

    var messagingChannel: MessagingChannel {
        get { MessagingChannel(rawValue: messagingChannelRaw) ?? .whatsApp }
        set { messagingChannelRaw = newValue.rawValue }
    }

    var replyDelayRange: ClosedRange<Double> {
        let low = max(0, min(replyDelayMinSeconds, replyDelayMaxSeconds))
        let high = max(low, replyDelayMaxSeconds)
        return low...high
    }

    /// Minutes from midnight, so the two ends can be compared cheaply.
    var openingMinutesFromMidnight: Int { openingHour * 60 + openingMinute }
    var closingMinutesFromMidnight: Int { closingHour * 60 + closingMinute }

    /// The most sessions that actually fit between opening and closing.
    /// Used to stop the owner asking for eight 90-minute slots in a 6-hour day.
    var maximumSlotsPerDay: Int {
        let window = closingMinutesFromMidnight - openingMinutesFromMidnight
        let stride = sessionMinutes + breakMinutes
        guard window >= sessionMinutes, stride > 0 else { return 0 }
        return (window + breakMinutes) / stride
    }

    /// True when the owner has asked for more slots than the day can hold.
    var slotsOverflow: Bool { slotsPerDay > maximumSlotsPerDay }

    var sessionLengthDescription: String {
        let hours = sessionMinutes / 60
        let minutes = sessionMinutes % 60
        switch (hours, minutes) {
        case (0, let m): return "\(m) min"
        case (let h, 0): return h == 1 ? "1 hour" : "\(h) hours"
        case (let h, let m): return "\(h)h \(m)m"
        }
    }

    var hoursDescription: String {
        String(format: "%02d:%02d – %02d:%02d", openingHour, openingMinute, closingHour, closingMinute)
    }

    /// Snapshot handed to the scheduler, which is a plain enum and can't hold
    /// a SwiftData object.
    var schedulingConfiguration: SchedulingConfiguration {
        SchedulingConfiguration(
            openingHour: openingHour,
            openingMinute: openingMinute,
            closingHour: closingHour,
            closingMinute: closingMinute,
            sessionMinutes: sessionMinutes,
            breakMinutes: breakMinutes,
            slotsPerDay: slotsPerDay,
            weekdaysOnly: weekdaysOnly
        )
    }

    /// Pushes the current values into the scheduler. Call after every edit.
    func apply() {
        updatedAt = .now
        SchedulingService.configuration = schedulingConfiguration
    }
}
