//
//  SchedulingService.swift
//  Kunang
//
//  Community hours, session length and slots per day all come from
//  CommunitySettings, which the owner edits in Settings. This file holds the
//  live snapshot of those values plus the assignment logic.
//
//  Clients are sorted by priority, then urgency, then score, and dropped into
//  the earliest slot where their randomly assigned handler is free.
//

import Foundation
import SwiftData

/// A plain value snapshot of the owner's scheduling preferences.
/// Explicitly nonisolated so the scheduler can read it from default arguments
/// and background contexts without hopping to the main actor.
nonisolated struct SchedulingConfiguration: Equatable, Sendable {
    var openingHour: Int = 8
    var openingMinute: Int = 0
    var closingHour: Int = 17
    var closingMinute: Int = 0
    var sessionMinutes: Int = 90
    var breakMinutes: Int = 0
    var slotsPerDay: Int = 6
    var weekdaysOnly: Bool = true

    var sessionLength: TimeInterval { TimeInterval(sessionMinutes * 60) }
    var openingMinutesFromMidnight: Int { openingHour * 60 + openingMinute }
    var closingMinutesFromMidnight: Int { closingHour * 60 + closingMinute }

    static let `default` = SchedulingConfiguration()
}

struct SessionSlot: Identifiable, Hashable {
    let start: Date
    /// Carried on the slot so a booking keeps its length even if the owner
    /// changes the default afterwards.
    let minutes: Int

    var id: Date { start }
    var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }

    init(start: Date, minutes: Int = SchedulingService.configuration.sessionMinutes) {
        self.start = start
        self.minutes = minutes
    }

    var label: String {
        start.formatted(date: .omitted, time: .shortened)
            + "–" + end.formatted(date: .omitted, time: .shortened)
    }
}

struct SchedulingReport {
    var scheduled: Int = 0
    var referred: Int = 0
    var unplaced: Int = 0
    var handlersUsed: Int = 0

    var summary: String {
        var parts = ["\(scheduled) booked"]
        if referred > 0 { parts.append("\(referred) referred out") }
        if unplaced > 0 { parts.append("\(unplaced) couldn't fit") }
        return parts.joined(separator: ", ")
    }
}

enum SchedulingService {

    /// The owner's current preferences. Replaced whenever Settings is saved.
    nonisolated(unsafe) static var configuration: SchedulingConfiguration = .default

    // MARK: - Convenience readers

    static var sessionLength: TimeInterval { configuration.sessionLength }
    static var sessionMinutes: Int { configuration.sessionMinutes }
    static var openingHour: Int { configuration.openingHour }
    static var closingHour: Int { configuration.closingHour }
    static var slotsPerDay: Int { configuration.slotsPerDay }
    static var weekdaysOnly: Bool {
        get { configuration.weekdaysOnly }
        set { configuration.weekdaysOnly = newValue }
    }

    /// "90 minutes", "1 hour", "45 minutes" — for message copy.
    static var sessionLengthPhrase: String {
        let minutes = configuration.sessionMinutes
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) minutes"
    }

    // MARK: - Slot generation

    /// The slot start times for one day, before checking who's booked.
    /// Stops early when the day runs out of room, so an over-ambitious
    /// `slotsPerDay` can never push a session past closing time.
    static func slotTimes(on day: Date, configuration config: SchedulingConfiguration = configuration) -> [SessionSlot] {
        let calendar = Calendar.current
        guard config.sessionMinutes > 0, config.slotsPerDay > 0 else { return [] }

        var result: [SessionSlot] = []
        let stride = config.sessionMinutes + max(0, config.breakMinutes)

        for index in 0..<config.slotsPerDay {
            let offset = index * stride
            let startMinutes = config.openingMinutesFromMidnight + offset
            let endMinutes = startMinutes + config.sessionMinutes
            guard endMinutes <= config.closingMinutesFromMidnight else { break }

            if let start = calendar.date(
                bySettingHour: startMinutes / 60,
                minute: startMinutes % 60,
                second: 0,
                of: calendar.startOfDay(for: day)
            ) {
                result.append(SessionSlot(start: start, minutes: config.sessionMinutes))
            }
        }
        return result
    }

    static func slots(startingFrom day: Date, days: Int) -> [SessionSlot] {
        let calendar = Calendar.current
        var result: [SessionSlot] = []
        var cursor = calendar.startOfDay(for: day)
        var produced = 0
        // Guard against a settings combination that closes every day.
        var safety = 0

        while produced < days && safety < days * 7 + 14 {
            safety += 1
            if !isClosed(on: cursor) {
                result.append(contentsOf: slotTimes(on: cursor))
                produced += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// True when the community is shut on that date.
    static func isClosed(on day: Date) -> Bool {
        guard configuration.weekdaysOnly else { return false }
        let weekday = Calendar.current.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    /// Slots for one handler on one day that nobody else has taken.
    /// Returns nothing when the community is closed that day, so the picker
    /// can never silently book a different date than the one shown.
    static func availableSlots(
        for handler: Handler,
        on day: Date,
        excluding client: Client? = nil,
        allClients: [Client]
    ) -> [SessionSlot] {
        guard !isClosed(on: day) else { return [] }
        let taken = Set(
            allClients
                .filter { $0.handler?.id == handler.id && $0.id != client?.id }
                .compactMap(\.scheduledAt)
        )
        return slotTimes(on: day).filter { !taken.contains($0.start) }
    }

    // MARK: - Auto scheduling

    /// Assigns handlers and books sessions for everyone who needs one.
    /// - Parameter capacityPerHandler: max clients one handler may carry. When
    ///   nil, the load is split evenly across the available handlers.
    @discardableResult
    static func autoSchedule(
        clients: [Client],
        handlers: [Handler],
        startingFrom startDay: Date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
        capacityPerHandler: Int? = nil,
        horizonDays: Int = 30
    ) -> SchedulingReport {
        var report = SchedulingReport()
        let activeHandlers = handlers.filter { !$0.isPaused }
        guard !activeHandlers.isEmpty else { return report }
        report.handlersUsed = activeHandlers.count

        // Referrals and low-priority folks get a status, not a booking.
        let bookable = clients.filter { $0.priority.isSchedulable && $0.status != .completed }
        for client in clients where !client.priority.isSchedulable {
            client.handler = nil
            client.scheduledAt = nil
            client.sessionLink = nil
            if client.priority == .referralRequired {
                client.status = .referredOut
                report.referred += 1
            } else if !client.status.isClosed {
                // Low-priority folks aren't booked — they just get a message.
                client.status = client.hasResponded ? .inProgress : .noResponse
            }
        }

        let capacity = capacityPerHandler
            ?? max(1, Int(ceil(Double(bookable.count) / Double(activeHandlers.count))))

        // Highest need first; ties broken by urgency then by the lowest score.
        let queue = bookable.sorted { lhs, rhs in
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
            if lhs.urgency != rhs.urgency { return lhs.urgency > rhs.urgency }
            return lhs.mentalHealthScore < rhs.mentalHealthScore
        }

        let allSlots = slots(startingFrom: startDay, days: horizonDays)
        var load: [PersistentIdentifier: Int] = [:]
        var booked: [PersistentIdentifier: Set<Date>] = [:]

        for client in queue {
            client.scheduledAt = nil
            client.handler = nil

            // Randomised, but always among the least-loaded handlers with room left.
            let eligible = activeHandlers.filter { (load[$0.id] ?? 0) < capacity }
            let pool = eligible.isEmpty ? activeHandlers : eligible
            let minimumLoad = pool.map { load[$0.id] ?? 0 }.min() ?? 0
            let candidates = pool.filter { (load[$0.id] ?? 0) == minimumLoad }.shuffled()

            var placed = false
            for handler in candidates {
                let taken = booked[handler.id] ?? []
                guard let slot = allSlots.first(where: { !taken.contains($0.start) }) else { continue }
                client.handler = handler
                client.scheduledAt = slot.start
                client.sessionLink = sessionLink(for: client, at: slot.start)
                client.status = .scheduled
                booked[handler.id, default: []].insert(slot.start)
                load[handler.id, default: 0] += 1
                report.scheduled += 1
                placed = true
                break
            }

            if !placed {
                client.status = .waitingForAppointment
                report.unplaced += 1
            }
        }

        return report
    }

    /// Books one client into a specific slot, refusing if the handler is busy.
    @discardableResult
    static func book(
        client: Client,
        with handler: Handler,
        at start: Date,
        allClients: [Client]
    ) -> Bool {
        let clash = allClients.contains {
            $0.id != client.id && $0.handler?.id == handler.id && $0.scheduledAt == start
        }
        guard !clash else { return false }
        client.handler = handler
        client.scheduledAt = start
        client.sessionLink = sessionLink(for: client, at: start)
        if client.status == .newIntake || client.status == .waitingForAppointment {
            client.status = .scheduled
        }
        return true
    }

    private static func sessionLink(for client: Client, at date: Date) -> String {
        let token = String(client.uuid.uuidString.prefix(8)).lowercased()
        let day = date.formatted(.iso8601.year().month().day())
        return "kunang.community/s/\(day)-\(token)"
    }
}
