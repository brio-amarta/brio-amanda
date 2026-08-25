//
//  PreviewData.swift
//  Kunang
//
//  In-memory sample data so Xcode previews have something to draw.
//

import Foundation
import SwiftData

@MainActor
enum PreviewData {

    static let container: ModelContainer = {
        let schema = Schema([Client.self, Handler.self, ChatMessage.self, CommunitySettings.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(into: container.mainContext)
        return container
    }()

    static func seed(into context: ModelContext) {
        // Settings first — the scheduler reads them while seeding.
        CommunitySettings.current(in: context).apply()

        let handlers = ["Winda Ratnasari", "Gede Arya", "Putu Melati"].enumerated().map { index, name in
            Handler(name: name, colorIndex: index)
        }
        handlers.forEach { context.insert($0) }

        let samples: [(String, Int, String, String, Double, String, Priority)] = [
            ("Davin Bonfilio", 28, "Jakarta", "+62 838 7000 0001", 6.7, "Struggling with work stress and sleep.", .referralRequired),
            ("Kadek Ayu", 24, "Denpasar", "+62 812 3456 7890", 2.4, "Feels hopeless most days, has stopped seeing friends.", .crisis),
            ("Wayan Surya", 31, "Ubud", "+62 813 1111 2222", 4.2, "Recent breakup, panic attacks twice a week.", .highPriority),
            ("Ni Luh Sari", 19, "Canggu", "+62 878 9090 1010", 6.1, "Exam anxiety and low mood.", .moderate),
            ("Made Bagus", 35, "Singaraja", "+62 819 4444 5555", 8.3, "Just checking in, generally doing well.", .others),
            ("Komang Dwi", 27, "Sanur", "+62 811 2233 4455", 3.6, "Burnout from long hospitality shifts.", .highPriority)
        ]

        var created: [Client] = []
        for (name, age, location, phone, score, notes, priority) in samples {
            let client = Client(
                name: name,
                age: age,
                location: location,
                phone: phone,
                mentalHealthScore: score,
                notes: notes
            )
            client.priority = priority
            client.urgency = max(1, Int((10 - score).rounded()))
            client.triageReason = "Score \(String(format: "%.1f", score)) with the notes places them in \(priority.rawValue)."
            client.triagedAt = .now
            client.status = .waitingForAppointment
            context.insert(client)
            created.append(client)
        }

        SchedulingService.autoSchedule(clients: created, handlers: handlers)

        if let first = created.first(where: { $0.priority == .crisis }) {
            let opener = ChatMessage(
                text: "Hi \(first.name), thanks for reaching out to us. We've saved you a 90-minute session this week — would that work?",
                isFromOwner: true,
                isGenerated: true,
                timestamp: .now.addingTimeInterval(-600)
            )
            opener.client = first
            let reply = ChatMessage(
                text: "Hi, thank you. I think I can make it. I've been meaning to talk to someone.",
                isFromOwner: false,
                isGenerated: true,
                timestamp: .now.addingTimeInterval(-540)
            )
            reply.client = first
            context.insert(opener)
            context.insert(reply)
        }

        try? context.save()
    }
}
