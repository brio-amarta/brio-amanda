//
//  Handler.swift
//  Mentalzz
//

import Foundation
import SwiftData

@Model
final class Handler {
    /// Our own stable identifier. SwiftData supplies `id` / `persistentModelID`.
    var uuid: UUID = UUID()
    var name: String = ""
    /// Optional note, e.g. speciality or shift.
    var role: String = ""
    /// Index into `Handler.palette`, used for the avatar colour.
    var colorIndex: Int = 0
    var createdAt: Date = Date()
    /// When set, the scheduler skips this handler.
    var isPaused: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Client.handler)
    var clients: [Client]? = []

    init(name: String, role: String = "Handler", colorIndex: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.role = role
        self.colorIndex = colorIndex
        self.createdAt = .now
    }

    // MARK: - Derived stats

    var allClients: [Client] { clients ?? [] }

    var ongoingClients: [Client] {
        allClients.filter { !$0.status.isClosed }
    }

    var completedClients: [Client] {
        allClients.filter { $0.status == .completed }
    }

    var totalHandled: Int { allClients.count }

    var scheduledSessions: [Client] {
        allClients.filter { $0.scheduledAt != nil }
    }

    /// Average number of sessions this handler covers per calendar week.
    var averagePerWeek: Double {
        let dates = scheduledSessions.compactMap(\.scheduledAt)
        guard !dates.isEmpty else { return 0 }
        let weeks = Set(dates.map { date -> String in
            let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
        })
        return Double(dates.count) / Double(max(weeks.count, 1))
    }

    var completionRate: Double {
        guard totalHandled > 0 else { return 0 }
        return Double(completedClients.count) / Double(totalHandled)
    }

    /// Leaderboard score: completed work counts double, ongoing load counts once.
    var leaderboardScore: Double {
        Double(completedClients.count) * 2 + Double(ongoingClients.count)
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    static let palette: [String] = [
        "Blue", "Purple", "Teal", "Orange", "Pink", "Green", "Indigo", "Brown"
    ]
}
