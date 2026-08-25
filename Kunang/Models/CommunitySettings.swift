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

    var updatedAt: Date = Date()

    init() {}

    // MARK: - Singleton access

    /// Fetches the one settings row, creating it the first time.
    static func current(in context: ModelContext) -> CommunitySettings {
        let descriptor = FetchDescriptor<CommunitySettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = CommunitySettings()
        context.insert(fresh)
        try? context.save()
        return fresh
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
