//
//  TriageService.swift
//  Mentalzz
//
//  Runs each imported row through the on-device Foundation Model to decide a
//  priority category. Location is always appended last so the model weighs it
//  when deciding. If Apple Intelligence isn't available the rule-based
//  fallback keeps the import working.
//

import Foundation
import FoundationModels

// MARK: - Guided output

@Generable(description: "Triage assessment for one mental health community client")
nonisolated struct TriageAssessment {
    @Guide(
        description: "The priority bucket for this client",
        .anyOf(["Crisis", "High Priority", "Moderate", "Others"])
    )
    var category: String

    @Guide(description: "Urgency from 1 (can wait) to 10 (needs contact today)", .range(1...10))
    var urgency: Int

    @Guide(description: "One short sentence, max 20 words, explaining the decision")
    var reason: String
}

// MARK: - Service

@Observable
@MainActor
final class TriageService {

    /// The editable instructions the owner can tune in the Upload screen.
    static let defaultInstructions = """
        You are the intake triage assistant for a community mental health group in Bali.
        For each person you receive a row from the community's spreadsheet.

        Weigh the mental health score first. It runs 0 to 10, where 10 means thriving \
        and 0 means severe distress. As a guide: 0.0-3.0 is Crisis, 3.1-5.0 is High Priority, \
        5.1-7.0 is Moderate, above 7.0 is Others. Adjust up or down when the notes, age or \
        other columns clearly justify it — mentions of self-harm, suicidal thoughts, abuse or \
        acute panic always mean Crisis regardless of score.

        The location line matters: it is the last thing you read before deciding, and it tells \
        you whether the community can physically see this person. Judge urgency on the person's \
        need, not on their distance.

        Answer only with the requested fields. Keep the reason to one short sentence.
        """

    private(set) var isRunning = false
    private(set) var progress: Double = 0
    private(set) var statusText = ""
    private(set) var usedFallback = false

    var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var availabilityMessage: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            "Apple Intelligence is ready. Triage runs entirely on this device."
        case .unavailable(.deviceNotEligible):
            "This device can't run Apple Intelligence. Mentalzz will use score-based rules instead."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings to let the model triage. Score-based rules will be used until then."
        case .unavailable(.modelNotReady):
            "The model is still downloading. Score-based rules will be used until it's ready."
        case .unavailable:
            "The model is unavailable right now. Score-based rules will be used instead."
        }
    }

    // MARK: - Batch triage

    struct Outcome {
        var priority: Priority
        var urgency: Int
        var reason: String
    }

    /// Triages every row, reporting progress as it goes.
    func triage(
        rows: [ImportedRow],
        instructions: String,
        onEach: @MainActor (ImportedRow, Outcome) -> Void
    ) async {
        isRunning = true
        progress = 0
        usedFallback = !isModelAvailable
        defer {
            isRunning = false
            statusText = ""
            progress = 1
        }

        for (offset, row) in rows.enumerated() {
            statusText = "Triaging \(row.name)…"
            let outcome = await triage(row: row, instructions: instructions)
            onEach(row, outcome)
            progress = Double(offset + 1) / Double(max(rows.count, 1))
        }
    }

    /// Triages a single row. Falls back to score rules on any model failure.
    func triage(row: ImportedRow, instructions: String) async -> Outcome {
        // Out-of-area people are always a referral — the community can't see them.
        // The model still runs so the urgency and reason stay meaningful.
        let outOfArea = !BaliRegion.isInBali(row.location)

        guard isModelAvailable else {
            usedFallback = true
            return fallback(for: row, outOfArea: outOfArea)
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: row.promptSummary,
                generating: TriageAssessment.self
            )
            let assessment = response.content
            let modelPriority = Priority(rawValue: assessment.category) ?? .others
            return Outcome(
                priority: outOfArea ? .referralRequired : modelPriority,
                urgency: min(max(assessment.urgency, 1), 10),
                reason: outOfArea
                    ? "\(assessment.reason) Outside Bali, so referred to a service near them."
                    : assessment.reason
            )
        } catch {
            usedFallback = true
            return fallback(for: row, outOfArea: outOfArea)
        }
    }

    // MARK: - Rule-based fallback

    private func fallback(for row: ImportedRow, outOfArea: Bool) -> Outcome {
        let score = row.mentalHealthScore
        let notes = row.notes.lowercased()
        let redFlags = ["suicid", "self-harm", "self harm", "kill myself", "abuse", "panic attack", "hopeless", "bunuh diri"]
        let hasRedFlag = redFlags.contains { notes.contains($0) }

        let base: Priority
        if hasRedFlag || score <= 3 {
            base = .crisis
        } else if score <= 5 {
            base = .highPriority
        } else if score <= 7 {
            base = .moderate
        } else {
            base = .others
        }

        let urgency = hasRedFlag ? 10 : max(1, min(10, Int((10 - score).rounded())))
        let reason = outOfArea
            ? "Scored \(String(format: "%.1f", score)) but lives outside Bali, so referred nearby."
            : "Score \(String(format: "%.1f", score)) places them in \(base.rawValue)."

        return Outcome(
            priority: outOfArea ? .referralRequired : base,
            urgency: urgency,
            reason: reason
        )
    }
}
