//
//  SchedulingService.swift
//  Mentalzz
//
//  Community hours are 08:00–17:00, six 90-minute slots a day.
//  Clients are sorted by priority, then urgency, then score, and dropped into
//  the earliest slot where their randomly assigned handler is free.
//

import Foundation
import SwiftData

struct SessionSlot: Identifiable, Hashable {
    let start: Date
    var id: Date { start }
    var end: Date { start.addingTimeInterval(SchedulingService.sessionLength) }

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

    /// 90 minutes per session.
    static let sessionLength: TimeInterval = 90 * 60
    static let openingHour = 8
    static let closingHour = 17
    /// Slots per working day: 08:00, 09:30, 11:00, 12:30, 14:00, 15:30.
    static let slotsPerDay = 6
    /// Set false to also book weekends.
    static var weekdaysOnly = true

    // MARK: - Slot generation

    static func slots(startingFrom day: Date, days: Int) -> [SessionSlot] {
        let calendar = Calendar.current
        var result: [SessionSlot] = []
        var cursor = calendar.startOfDay(for: day)
        var produced = 0

        while produced < days {
            let weekday = calendar.component(.weekday, from: cursor)
            let isWeekend = weekday == 1 || weekday == 7
            if !(weekdaysOnly && isWeekend) {
                for index in 0..<slotsPerDay {
                    let minutesIn = index * Int(sessionLength / 60)
                    if let start = calendar.date(
                        bySettingHour: openingHour + minutesIn / 60,
                        minute: minutesIn % 60,
                        second: 0,
                        of: cursor
                    ), calendar.component(.hour, from: start.addingTimeInterval(sessionLength - 60)) < closingHour {
                        result.append(SessionSlot(start: start))
                    }
                }
                produced += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// True when the community is shut on that date.
    static func isClosed(on day: Date) -> Bool {
        guard weekdaysOnly else { return false }
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
        return slots(startingFrom: day, days: 1).filter { !taken.contains($0.start) }
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
        return "mentalzz.community/s/\(day)-\(token)"
    }
}
