//
//  ChatService.swift
//  Mentalzz
//
//  Drafts the opening outreach message for a client and generates the
//  client's reply after the owner sends something. All on-device.
//

import Foundation
import FoundationModels

@Observable
@MainActor
final class ChatService {

    private(set) var isDrafting = false
    private(set) var isReplying = false

    var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: - Opening draft

    /// Pre-fills the input field with something the owner can edit before sending.
    func draftOpener(for client: Client) async -> String {
        isDrafting = true
        defer { isDrafting = false }

        guard isModelAvailable else { return fallbackOpener(for: client) }

        let instructions: String
        let prompt: String

        if client.priority == .referralRequired {
            let hint = BaliRegion.referralHint(for: client.location)
            instructions = """
                You write short WhatsApp messages for a community mental health group based in Bali.
                This person lives outside Bali, so the group cannot see them in person. Write a warm, \
                gentle message that acknowledges them, explains kindly that the group only runs \
                sessions in Bali, and points them toward support closer to home. Never sound like a \
                rejection letter. Two to three sentences. No emoji. Sign off as "Mentalzz Community".
                """
            prompt = """
                Person: \(client.name), age \(client.age), in \(client.location).
                Wellbeing score: \(client.scoreDescription) out of 10.
                Notes: \(client.notes.isEmpty ? "none" : client.notes)
                \(hint.map { "Nearby support you may mention: \($0)" } ?? "")
                Write the message.
                """
        } else {
            instructions = """
                You write short WhatsApp messages for a community mental health group in Bali.
                Write a warm first outreach to someone who filled in the community's intake form. \
                Acknowledge how they might be feeling without diagnosing them, then invite them to \
                the session that has been booked for them. Two to three sentences, plain language, \
                no emoji, no clinical jargon. Sign off as "Mentalzz Community".
                """
            let when = client.scheduledAt?.formatted(date: .complete, time: .shortened) ?? "a time we'll confirm shortly"
            prompt = """
                Person: \(client.name), age \(client.age), in \(client.location).
                Wellbeing score: \(client.scoreDescription) out of 10.
                Notes: \(client.notes.isEmpty ? "none" : client.notes)
                Their session: \(when), 90 minutes, with \(client.handler?.name ?? "one of our handlers").
                Write the invitation.
                """
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.8)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return fallbackOpener(for: client)
        }
    }

    // MARK: - Client reply

    /// Generates what the client writes back after the owner sends a message.
    func generateReply(for client: Client, history: [ChatMessage]) async -> String {
        isReplying = true
        defer { isReplying = false }

        guard isModelAvailable else { return fallbackReply(for: client) }

        let instructions = """
            You are role-playing a member of a mental health community replying to a message \
            from the community team. Stay in character as \(client.name), age \(client.age), \
            living in \(client.location). Reply the way a real person texts: one to three short \
            sentences, casual, sometimes hesitant. Do not give medical advice, do not describe \
            self-harm, and never break character to mention you are an AI. If a session time was \
            offered, respond to it — accept, ask to move it, or say you need to think about it.
            """

        // Keep the transcript short so we stay inside the context window.
        let recent = history.suffix(8).map { message in
            "\(message.isFromOwner ? "Community" : client.name): \(message.text)"
        }.joined(separator: "\n")

        let prompt = """
            Conversation so far:
            \(recent)

            Write \(client.name)'s next reply.
            """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.9)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return fallbackReply(for: client)
        }
    }

    // MARK: - Fallbacks

    private func fallbackOpener(for client: Client) -> String {
        if client.priority == .referralRequired {
            let hint = BaliRegion.referralHint(for: client.location)
            return """
                Hi \(client.name), thank you for reaching out to us. Our sessions run in person in Bali, \
                so we're not able to see you from \(client.location) — but we really don't want to leave \
                you without anything. \(hint ?? "There are community and hospital counselling services near you, and we're happy to help you find one.")
                — Mentalzz Community
                """
        }
        let when = client.scheduledAt?.formatted(date: .complete, time: .shortened) ?? "a time we'll confirm shortly"
        return """
            Hi \(client.name), thanks for filling in our form — it takes something to do that. \
            We've saved you a 90-minute session on \(when) with \(client.handler?.name ?? "one of our handlers"). \
            Let us know if that time works for you.
            — Mentalzz Community
            """
    }

    private func fallbackReply(for client: Client) -> String {
        let options = [
            "Hi, thank you for reaching out. That time works for me.",
            "Thanks for the message. Could we do a later slot? Mornings are hard for me.",
            "I appreciate this. I've been meaning to talk to someone for a while.",
            "Okay, I'll be there. Do I need to bring anything?",
            "Thank you. I'm a bit nervous but I'll come."
        ]
        return options.randomElement() ?? "Thank you for reaching out."
    }
}
