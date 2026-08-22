//
//  UploadView.swift
//  Mentalzz
//
//  Attach a spreadsheet, let the on-device model triage it, then auto-build
//  the schedule.
//

import SwiftUI
import SwiftData
import Foundation
import UniformTypeIdentifiers

struct UploadView: View {
    @Environment(\.modelContext) private var context
    @Environment(TriageService.self) private var triage
    @Query private var clients: [Client]
    @Query(sort: \Handler.createdAt) private var handlers: [Handler]

    @AppStorage("triageInstructions") private var instructions = TriageService.defaultInstructions
    @AppStorage("replaceOnImport") private var replaceExisting = true

    @State private var isPickingFile = false
    @State private var rows: [ImportedRow] = []
    @State private var errorMessage: String?
    @State private var report: SchedulingReport?
    @State private var isEditingPrompt = false

    var onFinished: () -> Void

    var body: some View {
        Form {
            fileSection
            promptSection
            if !rows.isEmpty { previewSection }
            if let report { resultSection(report) }
        }
        .formStyle(.grouped)
        .navigationTitle("Upload")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .alert("Import failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var fileSection: some View {
        Section {
            Button {
                isPickingFile = true
            } label: {
                Label("Choose spreadsheet…", systemImage: "doc.badge.plus")
            }

            Toggle("Replace existing clients", isOn: $replaceExisting)

            if handlers.isEmpty {
                Label("Add at least one handler before importing.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Spreadsheet")
        } footer: {
            Text("CSV or TSV. Mentalzz looks for Name, Age, Location, Phone, Mental Health Score and Notes columns — any extra columns are passed to the model too. If your file is .xlsx, export it as CSV first.")
        }
    }

    private var promptSection: some View {
        Section {
            Label(triage.availabilityMessage, systemImage: triage.isModelAvailable ? "sparkles" : "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            DisclosureGroup("Triage instructions", isExpanded: $isEditingPrompt) {
                TextEditor(text: $instructions)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 220)

                Button("Reset to default") {
                    instructions = TriageService.defaultInstructions
                }
                .foregroundStyle(.red)
            }
        } header: {
            Text("How priority is decided")
        } footer: {
            Text("Every column from the row is sent to the model, with location last, and the model returns a category, an urgency and a one-line reason. Anyone outside Bali is always filed as Referral Required.")
        }
    }

    private var previewSection: some View {
        Section {
            ForEach(rows.prefix(8)) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.body.weight(.medium))
                    Text("\(row.age) · \(row.location.isEmpty ? "unknown location" : row.location) · score \(String(format: "%.1f", row.mentalHealthScore))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if rows.count > 8 {
                Text("+ \(rows.count - 8) more")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if triage.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: triage.progress)
                    Text(triage.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await runImport() }
                } label: {
                    Label("Triage \(rows.count) people & build schedule", systemImage: "wand.and.stars")
                }
                .disabled(handlers.isEmpty)
            }
        } header: {
            Text("Preview — \(rows.count) rows")
        }
    }

    private func resultSection(_ report: SchedulingReport) -> some View {
        Section("Done") {
            LabeledContent("Sessions booked", value: "\(report.scheduled)")
            LabeledContent("Referred out of area", value: "\(report.referred)")
            if report.unplaced > 0 {
                LabeledContent("Waiting for a slot", value: "\(report.unplaced)")
            }
            LabeledContent("Handlers used", value: "\(report.handlersUsed)")
            if triage.usedFallback {
                Label("Some rows used score-based rules because the model wasn't available.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Open schedule", action: onFinished)
        }
    }

    // MARK: - Actions

    private func handle(_ result: Result<[URL], Error>) {
        report = nil
        do {
            guard let url = try result.get().first else { return }
            rows = try CSVImporter.parse(fileAt: url)
        } catch {
            rows = []
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() async {
        if replaceExisting {
            for client in clients { context.delete(client) }
            try? context.save()
        }

        await triage.triage(rows: rows, instructions: instructions) { row, outcome in
            let client = Client(
                name: row.name,
                age: row.age,
                location: row.location,
                phone: row.phone,
                mentalHealthScore: row.mentalHealthScore,
                notes: row.notes
            )
            client.priority = outcome.priority
            client.urgency = outcome.urgency
            client.triageReason = outcome.reason
            client.triagedAt = .now
            client.status = .waitingForAppointment
            context.insert(client)
        }

        try? context.save()

        let fresh = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let allHandlers = (try? context.fetch(FetchDescriptor<Handler>())) ?? []
        report = SchedulingService.autoSchedule(clients: fresh, handlers: allHandlers)
        try? context.save()
        rows = []
    }
}

#Preview {
    NavigationStack {
        UploadView(onFinished: {})
    }
    .modelContainer(PreviewData.container)
    .previewServices()
}
