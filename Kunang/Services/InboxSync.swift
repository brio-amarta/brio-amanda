//
//  InboxSync.swift
//  Kunang
//
//  Pulls whatever has arrived at the community's WhatsApp Business number and
//  files it against the right person.
//
//  Three cases:
//    • the relay already knows the client (clientRef) — file it there
//    • the sender's number matches someone we have — file it there
//    • nobody matches — create a new intake so the message is never dropped
//
//  A brand-new intake lands in Others with no triage and no booking. The owner
//  sees it in the sidebar with a red dot and decides what it is.
//

import Foundation
import SwiftData

@MainActor
enum InboxSync {

    struct Result {
        var newMessages = 0
        var newClients = 0

        var isEmpty: Bool { newMessages == 0 }

        var summary: String {
            guard !isEmpty else { return "No new messages." }
            var parts = ["\(newMessages) new message\(newMessages == 1 ? "" : "s")"]
            if newClients > 0 {
                parts.append("\(newClients) new intake\(newClients == 1 ? "" : "s")")
            }
            return parts.joined(separator: ", ")
        }
    }

    /// Fetches and files everything newer than the stored watermark.
    @discardableResult
    static func run(
        messaging: MessagingService,
        settings: CommunitySettings,
        context: ModelContext
    ) async -> Result {
        guard messaging.isRelayConfigured else { return Result() }
        // An open Live thread polls every 5s while the background loop runs
        // every 10s. Without this the two interleave and race on the
        // watermark. Skipping is safe — the other run is already fetching.
        guard !messaging.isSyncingInbox else { return Result() }

        messaging.beginInboxSync()
        defer { messaging.finishInboxSync(at: .now) }

        // First run reaches back a week rather than pulling the entire history.
        let since = settings.lastInboxSyncAt ?? Date.now.addingTimeInterval(-7 * 24 * 3600)
        let inbound = await messaging.fetchInbox(since: since)
        guard !inbound.isEmpty else {
            // Advance to just short of now, never to now itself: a message the
            // relay stamps while this request is in flight would otherwise fall
            // behind the watermark and never be fetched.
            settings.lastInboxSyncAt = max(since, .now - overlap)
            try? context.save()
            return Result()
        }

        let existing = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var result = Result()
        var newest = since

        // Index by normalised phone so "+62 813…", "0813…" and "62813…" all
        // resolve to the same person.
        var byNumber: [String: Client] = [:]
        for client in existing {
            if let key = PhoneNumber.e164(client.phone, defaultCountryCode: messaging.defaultCountryCode) {
                byNumber[key] = client
            }
        }
        var byUUID: [UUID: Client] = [:]
        for client in existing { byUUID[client.uuid] = client }

        for message in inbound.sorted(by: { $0.timestamp < $1.timestamp }) {
            let normalised = PhoneNumber.e164(message.from, defaultCountryCode: messaging.defaultCountryCode)

            let client: Client
            if let ref = message.clientRef, let known = byUUID[ref] {
                client = known
            } else if let normalised, let known = byNumber[normalised] {
                client = known
            } else {
                let fresh = makeIntake(from: message, normalised: normalised)
                context.insert(fresh)
                byUUID[fresh.uuid] = fresh
                if let normalised { byNumber[normalised] = fresh }
                result.newClients += 1
                client = fresh
            }

            guard !alreadyStored(message, on: client) else { continue }

            let record = ChatMessage(
                text: message.text,
                isFromOwner: false,
                isLive: true,
                channel: .relay,
                delivery: .delivered,
                timestamp: message.timestamp
            )
            record.client = client
            context.insert(record)
            result.newMessages += 1

            // Somebody who writes in is no longer waiting silently.
            if client.status == .noResponse || client.status == .newIntake {
                client.status = .inProgress
            }
            newest = max(newest, message.timestamp)
        }

        // The newest message we actually saw — not the clock. Anything the
        // relay timestamps between that moment and now is still ahead of the
        // watermark and gets picked up next time. Replays are caught by
        // `alreadyStored`.
        settings.lastInboxSyncAt = newest
        try? context.save()
        return result
    }

    /// How far back the watermark stays behind the clock on an empty poll.
    private static let overlap: TimeInterval = 120

    // MARK: - Helpers

    /// Guards against the relay replaying a message we already filed.
    private static func alreadyStored(_ message: MessagingService.InboundMessage, on client: Client) -> Bool {
        client.liveMessages.contains { stored in
            stored.isFromOwner == false
                && stored.text == message.text
                && abs(stored.timestamp.timeIntervalSince(message.timestamp)) < 1
        }
    }

    private static func makeIntake(
        from message: MessagingService.InboundMessage,
        normalised: String?
    ) -> Client {
        let name = message.profileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = normalised.map { "+" + $0 } ?? message.from

        let client = Client(
            name: (name?.isEmpty == false ? name! : "WhatsApp \(phone.suffix(4))"),
            age: 0,
            location: "",
            phone: phone,
            mentalHealthScore: 5,
            notes: "Started the conversation on WhatsApp. Not triaged yet."
        )
        client.priority = .others
        client.status = .inProgress
        client.triageReason = "Arrived by WhatsApp rather than the spreadsheet."
        return client
    }
}
