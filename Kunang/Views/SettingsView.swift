//
//  SettingsView.swift
//  Kunang
//
//  Everything the owner can change. Scheduling edits show a live preview of
//  the slots they'd produce, so nobody has to re-run a whole import to find
//  out that eight 90-minute sessions don't fit in a 6-hour day.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TriageService.self) private var triage
    @Environment(ChatService.self) private var chat
    @Environment(MessagingService.self) private var messaging

    @Query private var settingsRows: [CommunitySettings]
    @Query private var clients: [Client]
    @Query private var handlers: [Handler]

    @AppStorage("ownerName") private var ownerName = "Community Owner"
    @AppStorage("ownerRole") private var ownerRole = "Admin"

    @State private var showRescheduleConfirm = false
    @State private var rescheduleReport: SchedulingReport?
    @State private var inboxResult: InboxSync.Result?

    private var settings: CommunitySettings? { settingsRows.first }

    var body: some View {
        Form {
            if let settings {
                profileSection
                hoursSection(settings)
                sessionSection(settings)
                previewSection(settings)
                messagingSection(settings)
                demoChatSection(settings)
                intelligenceSection
                resetSection(settings)
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let current = CommunitySettings.current(in: context)
            current.apply()
            chat.adopt(current)
            messaging.adopt(current)
        }
        .alert("Rebuild the schedule?", isPresented: $showRescheduleConfirm) {
            Button("Rebuild", role: .destructive) { rebuildSchedule() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone currently booked will be moved into the new slots. Handlers may change.")
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: $ownerName)
            TextField("Role", text: $ownerRole)
        }
    }

    // MARK: - Community hours

    private func hoursSection(_ settings: CommunitySettings) -> some View {
        Section {
            Stepper(value: binding(settings, \.openingHour), in: 0...22) {
                LabeledContent("Opens", value: timeLabel(settings.openingHour, settings.openingMinute))
            }
            Picker("Opening minute", selection: binding(settings, \.openingMinute)) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: ":%02d", $0)).tag($0) }
            }
            .pickerStyle(.segmented)

            Stepper(value: binding(settings, \.closingHour), in: 1...23) {
                LabeledContent("Closes", value: timeLabel(settings.closingHour, settings.closingMinute))
            }
            Picker("Closing minute", selection: binding(settings, \.closingMinute)) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: ":%02d", $0)).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Weekdays only", isOn: binding(settings, \.weekdaysOnly))

            if settings.closingMinutesFromMidnight <= settings.openingMinutesFromMidnight {
                Label("Closing time is before opening time.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        } header: {
            Text("Community hours")
        } footer: {
            Text("The window sessions are allowed to start and finish in. Currently \(settings.hoursDescription).")
        }
    }

    // MARK: - Session shape

    private func sessionSection(_ settings: CommunitySettings) -> some View {
        Section {
            Picker("Session length", selection: binding(settings, \.sessionMinutes)) {
                ForEach([30, 45, 60, 75, 90, 105, 120], id: \.self) { minutes in
                    Text(lengthLabel(minutes)).tag(minutes)
                }
            }

            Picker("Break between sessions", selection: binding(settings, \.breakMinutes)) {
                ForEach([0, 10, 15, 30], id: \.self) { minutes in
                    Text(minutes == 0 ? "Back to back" : "\(minutes) min").tag(minutes)
                }
            }

            Stepper(value: binding(settings, \.slotsPerDay), in: 1...16) {
                LabeledContent("Slots per day", value: "\(settings.slotsPerDay)")
            }

            if settings.slotsOverflow {
                Label(
                    "Only \(settings.maximumSlotsPerDay) fit between \(settings.hoursDescription). The extra slots are ignored.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.footnote)

                Button("Set to \(settings.maximumSlotsPerDay)") {
                    settings.slotsPerDay = max(1, settings.maximumSlotsPerDay)
                    save(settings)
                }
            }
        } header: {
            Text("Sessions")
        } footer: {
            Text("A \(settings.sessionLengthDescription) session, \(settings.breakMinutes == 0 ? "run back to back" : "with a \(settings.breakMinutes) minute gap"). Changing these doesn't move anyone who's already booked — use Rebuild schedule below for that.")
        }
    }

    // MARK: - Slot preview

    private func previewSection(_ settings: CommunitySettings) -> some View {
        Section {
            let slots = SchedulingService.slotTimes(on: .now, configuration: settings.schedulingConfiguration)

            if slots.isEmpty {
                Text("No sessions fit in this window.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    LabeledContent("Slot \(index + 1)", value: slot.label)
                        .font(.callout.monospacedDigit())
                }
                LabeledContent("Capacity", value: "\(slots.count * max(1, handlers.filter { !$0.isPaused }.count)) per day")
                    .foregroundStyle(.secondary)
            }

            Button {
                showRescheduleConfirm = true
            } label: {
                Label("Rebuild schedule with these settings", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(clients.isEmpty || handlers.isEmpty)

            if let report = rescheduleReport {
                Label(report.summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }
        } header: {
            Text("A day at a glance")
        } footer: {
            Text("Capacity assumes every active handler runs every slot.")
        }
    }

    // MARK: - Messaging

    private func messagingSection(_ settings: CommunitySettings) -> some View {
        Section {
            Picker("Live channel", selection: channelBinding(settings)) {
                ForEach(MessagingChannel.allCases) { channel in
                    Label(channel.rawValue, systemImage: channel.symbol).tag(channel)
                }
            }

            Text(settings.messagingChannel.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent("Default country code") {
                TextField("62", text: binding(settings, \.defaultCountryCode))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            LabeledContent("Community WhatsApp number") {
                TextField("6282338514166", text: binding(settings, \.communityWhatsAppNumber))
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.trailing)
            }

            if messaging.isRelayConfigured {
                LabeledContent("Inbox") {
                    if messaging.isSyncingInbox {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else if let last = messaging.lastInboxSyncAt {
                        Text("Checked \(last.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Not checked yet")
                    }
                }
                .foregroundStyle(.secondary)
                .font(.footnote)

                Button {
                    Task { inboxResult = await InboxSync.run(messaging: messaging, settings: settings, context: context) }
                } label: {
                    Label("Check for new messages now", systemImage: "tray.and.arrow.down")
                }
                .disabled(messaging.isSyncingInbox)

                if let inboxResult {
                    Text(inboxResult.summary)
                        .font(.footnote)
                        .foregroundStyle(inboxResult.isEmpty ? Color.secondary : Color.green)
                }
            }

            if settings.messagingChannel == .relay {
                LabeledContent("Relay address") {
                    TextField("https://…", text: binding(settings, \.relayBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                if !messaging.isRelayConfigured {
                    Label("No relay set — Live sending is off.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }

            if settings.messagingChannel == .iMessage && !SystemMessageComposer.canSend {
                Label("This device can't send text messages.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        } header: {
            Text("Messaging")
        } footer: {
            Text("""
                Live mode sends for real. Demo mode never leaves the iPad.

                Anyone who messages the community number turns up here — a \
                known number lands in that person's chat, an unknown one \
                arrives as a new intake in Others. This needs the relay \
                running; deep links can't receive anything.

                Two things worth knowing: WhatsApp's business policy restricts \
                health information, so keep live messages to invitations and \
                times — not scores, categories or notes. And outside 24 hours \
                from a client's last message, WhatsApp only allows pre-approved \
                template messages, so first contact through a relay must use one.
                """)
        }
    }

    // MARK: - Demo chat

    private func demoChatSection(_ settings: CommunitySettings) -> some View {
        Section {
            Stepper(value: binding(settings, \.replyDelayMinSeconds), in: 0...30, step: 1) {
                LabeledContent("Shortest pause", value: "\(Int(settings.replyDelayMinSeconds))s")
            }
            Stepper(value: binding(settings, \.replyDelayMaxSeconds), in: 0...60, step: 1) {
                LabeledContent("Longest pause", value: "\(Int(settings.replyDelayMaxSeconds))s")
            }
            if settings.replyDelayMaxSeconds < settings.replyDelayMinSeconds {
                Label("Longest pause is shorter than the shortest.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        } header: {
            Text("Demo replies")
        } footer: {
            Text("How long the typing dots run before a simulated client answers. A random moment between the two is picked each time.")
        }
    }

    // MARK: - Model

    private var intelligenceSection: some View {
        Section("On-device intelligence") {
            Label(triage.availabilityMessage, systemImage: triage.isModelAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(triage.isModelAvailable ? .primary : .secondary)
        }
    }

    private func resetSection(_ settings: CommunitySettings) -> some View {
        Section {
            Button("Restore defaults", role: .destructive) {
                let fresh = CommunitySettings()
                settings.openingHour = fresh.openingHour
                settings.openingMinute = fresh.openingMinute
                settings.closingHour = fresh.closingHour
                settings.closingMinute = fresh.closingMinute
                settings.sessionMinutes = fresh.sessionMinutes
                settings.breakMinutes = fresh.breakMinutes
                settings.slotsPerDay = fresh.slotsPerDay
                settings.weekdaysOnly = fresh.weekdaysOnly
                settings.replyDelayMinSeconds = fresh.replyDelayMinSeconds
                settings.replyDelayMaxSeconds = fresh.replyDelayMaxSeconds
                save(settings)
            }
        }
    }

    // MARK: - Plumbing

    /// Writes straight through to the model, then pushes the new values into
    /// the services that keep their own copy.
    private func binding<Value>(
        _ settings: CommunitySettings,
        _ keyPath: ReferenceWritableKeyPath<CommunitySettings, Value>
    ) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { newValue in
            settings[keyPath: keyPath] = newValue
            save(settings)
        }
    }

    private func channelBinding(_ settings: CommunitySettings) -> Binding<MessagingChannel> {
        Binding {
            settings.messagingChannel
        } set: { newValue in
            settings.messagingChannel = newValue
            save(settings)
        }
    }

    private func save(_ settings: CommunitySettings) {
        settings.apply()
        chat.adopt(settings)
        messaging.adopt(settings)
        try? context.save()
    }

    private func rebuildSchedule() {
        rescheduleReport = SchedulingService.autoSchedule(clients: clients, handlers: handlers)
        try? context.save()
    }

    // MARK: - Labels

    private func timeLabel(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func lengthLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) hour\(minutes == 60 ? "" : "s")" : "\(minutes) min"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewData.container)
    .previewServices()
}
