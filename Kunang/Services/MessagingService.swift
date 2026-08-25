//
//  MessagingService.swift
//  Kunang
//
//  Live messaging. Unlike the demo chat, nothing here invents a reply — a
//  message either really leaves the iPad or it doesn't.
//
//  Three channels:
//
//  • .whatsApp  — opens WhatsApp on a wa.me link with the text pre-filled.
//                 The owner taps send inside WhatsApp. No token, no server.
//  • .iMessage  — the system message sheet (MFMessageComposeViewController),
//                 which reports back whether it was actually sent.
//  • .relay     — POSTs to a server the owner hosts, which holds the Meta
//                 Cloud API token and does the real send. Off until they set
//                 a URL in Settings.
//
//  Apple gives no public API for sending iMessage or WhatsApp silently, and
//  Meta's terms forbid shipping a Cloud API access token inside a mobile app.
//  Every channel here is therefore either owner-confirmed or server-brokered
//  on purpose, not as a shortcut.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Channel

enum MessagingChannel: String, CaseIterable, Identifiable, Codable {
    case whatsApp = "WhatsApp"
    case iMessage = "iMessage"
    case relay = "Relay server"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .whatsApp: "bubble.left.and.text.bubble.right"
        case .iMessage: "message"
        case .relay: "antenna.radiowaves.left.and.right"
        }
    }

    /// True when the owner has to confirm the send in another app.
    var needsHandoff: Bool { self != .relay }

    var explanation: String {
        switch self {
        case .whatsApp:
            "Opens WhatsApp with the message ready. You tap send there, then log their reply back here."
        case .iMessage:
            "Opens the system message sheet. You tap send; iOS tells Kunang whether it went."
        case .relay:
            "Sends through a server you host, which holds the WhatsApp Cloud API token. Two-way, but only once the relay is running."
        }
    }
}

// MARK: - Delivery state

enum MessageDelivery: String, Codable, CaseIterable {
    /// Written by the on-device model in demo mode. Never left the iPad.
    case simulated
    /// Typed, not sent yet.
    case pending
    /// Handed to WhatsApp or Messages; we can't see what happened after that.
    case handedOff
    /// Confirmed sent — either by the system sheet or by the owner ticking it.
    case sent
    /// The relay accepted it.
    case delivered
    /// The send failed or the owner cancelled.
    case failed

    var symbol: String {
        switch self {
        case .simulated: "sparkles"
        case .pending: "clock"
        case .handedOff: "arrow.up.forward.app"
        case .sent: "checkmark"
        case .delivered: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .simulated: "Demo"
        case .pending: "Not sent"
        case .handedOff: "Opened — confirm sent"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .failed: "Failed"
        }
    }
}

// MARK: - Errors

enum MessagingError: LocalizedError {
    case noPhoneNumber
    case unusablePhoneNumber(String)
    case channelUnavailable(MessagingChannel)
    case relayNotConfigured
    case relayRejected(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noPhoneNumber:
            "This client has no phone number. Add one on their profile first."
        case .unusablePhoneNumber(let raw):
            "\"\(raw)\" doesn't look like a phone number Kunang can dial."
        case .channelUnavailable(let channel):
            "\(channel.rawValue) isn't available on this device."
        case .relayNotConfigured:
            "No relay server set. Add its address in Settings → Messaging."
        case .relayRejected(let code, let body):
            "The relay refused the message (HTTP \(code)). \(body)"
        case .transport(let detail):
            "Couldn't reach the relay: \(detail)"
        }
    }
}

// MARK: - Phone numbers

enum PhoneNumber {

    /// Turns "+62 812-3456-7890", "0812 3456 7890" or "812 3456 7890" into
    /// the digits-only E.164 form wa.me and the Cloud API both expect.
    static func e164(_ raw: String, defaultCountryCode: String = "62") -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var digits = trimmed.filter(\.isNumber)
        guard digits.count >= 6 else { return nil }

        let code = defaultCountryCode.filter(\.isNumber)

        if trimmed.hasPrefix("+") || trimmed.hasPrefix("00") {
            if trimmed.hasPrefix("00") { digits = String(digits.dropFirst(2)) }
        } else if digits.hasPrefix("0") {
            // Local trunk prefix — swap it for the country code.
            digits = code + digits.dropFirst()
        } else if !code.isEmpty && !digits.hasPrefix(code) {
            digits = code + digits
        }

        return digits.count >= 8 ? digits : nil
    }

    /// Pretty form for display, e.g. "+62 812 3456 7890".
    static func display(_ raw: String, defaultCountryCode: String = "62") -> String {
        guard let digits = e164(raw, defaultCountryCode: defaultCountryCode) else { return raw }
        return "+" + digits
    }
}

// MARK: - Service

@Observable
@MainActor
final class MessagingService {

    /// Mirrors CommunitySettings so views don't have to pass it around.
    var channel: MessagingChannel = .whatsApp
    var defaultCountryCode: String = "62"
    var relayBaseURL: String = ""

    private(set) var isSending = false
    /// Set when a send fails, so the chat can surface it.
    var lastError: MessagingError?

    var isRelayConfigured: Bool {
        URL(string: relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http") == true
    }

    func adopt(_ settings: CommunitySettings) {
        channel = settings.messagingChannel
        defaultCountryCode = settings.defaultCountryCode
        relayBaseURL = settings.relayBaseURL
    }

    // MARK: - Outcome

    enum SendOutcome {
        /// Another app is now showing the message; the owner finishes there.
        case handedOff
        /// The relay took it.
        case delivered
        case failed(MessagingError)

        var delivery: MessageDelivery {
            switch self {
            case .handedOff: .handedOff
            case .delivered: .delivered
            case .failed: .failed
            }
        }
    }

    /// Sends `text` to `client` over the current channel.
    ///
    /// `.iMessage` is not handled here — it needs a view controller, so the
    /// chat presents `SystemMessageComposer` instead and reports the result.
    func send(_ text: String, to client: Client) async -> SendOutcome {
        isSending = true
        defer { isSending = false }
        lastError = nil

        guard !client.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fail(.noPhoneNumber)
        }
        guard let number = PhoneNumber.e164(client.phone, defaultCountryCode: defaultCountryCode) else {
            return fail(.unusablePhoneNumber(client.phone))
        }

        switch channel {
        case .whatsApp:
            return await openWhatsApp(number: number, text: text)
        case .iMessage:
            // The caller presents the sheet; reaching here means it couldn't.
            return fail(.channelUnavailable(.iMessage))
        case .relay:
            return await sendViaRelay(number: number, text: text, client: client)
        }
    }

    private func fail(_ error: MessagingError) -> SendOutcome {
        lastError = error
        return .failed(error)
    }

    // MARK: - WhatsApp deep link

    /// wa.me opens the installed app when there is one and the web client
    /// otherwise, so there's no need to query for the whatsapp:// scheme.
    private func openWhatsApp(number: String, text: String) async -> SendOutcome {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/" + number
        components.queryItems = [URLQueryItem(name: "text", value: text)]

        guard let url = components.url else {
            return fail(.channelUnavailable(.whatsApp))
        }
        let opened = await UIApplication.shared.open(url)
        return opened ? .handedOff : fail(.channelUnavailable(.whatsApp))
    }

    // MARK: - Relay

    /// POST {relay}/messages  {"to": "...", "text": "...", "clientRef": "..."}
    ///
    /// The relay is the piece that holds the Meta access token and receives
    /// WhatsApp's inbound webhooks. See RELAY.md for the contract.
    private func sendViaRelay(number: String, text: String, client: Client) async -> SendOutcome {
        let base = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: base) else { return fail(.relayNotConfigured) }
        url.append(path: "messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "to": number,
            "text": text,
            "clientRef": client.uuid.uuidString
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return fail(.relayRejected(status, String(body.prefix(200))))
            }
            return .delivered
        } catch {
            return fail(.transport(error.localizedDescription))
        }
    }

    /// Pulls messages the relay has received since `since`.
    /// Returns an empty list when no relay is configured, so callers can call
    /// it unconditionally.
    func fetchInbound(for client: Client, since: Date) async -> [(text: String, timestamp: Date)] {
        guard channel == .relay, isRelayConfigured else { return [] }
        let base = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: base) else { return [] }
        url.append(path: "messages")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "clientRef", value: client.uuid.uuidString),
            URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since))
        ]
        guard let query = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: query)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            let formatter = ISO8601DateFormatter()
            return rows.compactMap { row in
                guard let text = row["text"] as? String else { return nil }
                let stamp = (row["timestamp"] as? String).flatMap(formatter.date(from:)) ?? .now
                return (text, stamp)
            }
        } catch {
            return []
        }
    }
}
