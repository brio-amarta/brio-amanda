//
//  ClientDetailView.swift
//  Kunang
//
//  Left: the client record with editable handler, category, status and slot.
//  Right: the chat, drafted and answered by the on-device model.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit
import MessageUI

struct ClientDetailView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var client: Client

    var body: some View {
        Group {
            if sizeClass == .compact {
                TabView {
                    Tab("Profile", systemImage: "person.text.rectangle") {
                        ClientProfilePane(client: client)
                    }
                    Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                        ClientChatPane(client: client)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ClientProfilePane(client: client)
                        .frame(width: 360)
                    Divider()
                    ClientChatPane(client: client)
                }
            }
        }
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile

struct ClientProfilePane: View {
    @Environment(\.modelContext) private var context
    @Bindable var client: Client
    @Query(sort: \Handler.createdAt) private var handlers: [Handler]
    @Query private var allClients: [Client]

    @State private var slotDay: Date = .now
    @State private var clashWarning = false
    @State private var isEditingNotes = false
    @FocusState private var notesFocused: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name)
                        .font(.largeTitle.bold())
                    Text(client.phone.isEmpty ? "No phone number" : client.phone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent("Age", value: client.age == 0 ? "—" : "\(client.age)")
                LabeledContent("Location", value: client.location.isEmpty ? "—" : client.location)
                LabeledContent("Mental Health Score", value: client.scoreDescription)
                if !client.isInBali {
                    Label("Outside Bali — referral only", systemImage: "mappin.slash")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
            }

            if !client.triageReason.isEmpty {
                Section("Why this category") {
                    Text(client.triageReason)
                        .font(.callout)
                    LabeledContent("Urgency", value: "\(client.urgency)/10")
                }
            }

            // Notes carry what the client actually said, so they're read-only
            // until the owner deliberately taps Edit. A stray tap on a
            // TextEditor used to be enough to alter them.
            Section {
                if isEditingNotes {
                    TextEditor(text: $client.notes)
                        .frame(minHeight: 140)
                        .font(.callout)
                        .focused($notesFocused)
                } else if client.notes.isEmpty {
                    Text("No notes yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(client.notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                HStack {
                    Text("Notes")
                    Spacer()
                    Button {
                        toggleNotesEditing()
                    } label: {
                        Label(
                            isEditingNotes ? "Done" : "Edit",
                            systemImage: isEditingNotes ? "checkmark" : "square.and.pencil"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .textCase(nil)
                }
            } footer: {
                if isEditingNotes {
                    Text("Tap Done to save.")
                }
            }

            Section("Handler") {
                Picker("Handler", selection: handlerBinding) {
                    Text("Unassigned").tag(nil as PersistentIdentifier?)
                    ForEach(handlers) { handler in
                        Text(handler.name).tag(handler.persistentModelID as PersistentIdentifier?)
                    }
                }
            }

            Section("Category") {
                Picker("Category", selection: categoryBinding) {
                    ForEach(Priority.allCases) { priority in
                        Label(priority.rawValue, systemImage: priority.symbol).tag(priority)
                    }
                }
            }

            Section {
                Picker("Status", selection: statusBinding) {
                    ForEach(ClientStatus.allCases) { status in
                        Label(status.rawValue, systemImage: status.symbol).tag(status)
                    }
                }

                // The common ending, one tap instead of hunting the picker.
                if client.status == .completed {
                    if let finished = client.completedAt {
                        LabeledContent("Completed", value: finished.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button {
                        statusBinding.wrappedValue = client.scheduledAt == nil ? .waitingForAppointment : .scheduled
                    } label: {
                        Label("Reopen this client", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        statusBinding.wrappedValue = .completed
                    } label: {
                        Label("Mark session completed", systemImage: "checkmark.seal.fill")
                    }
                    .tint(.green)
                }
            } header: {
                Text("Status")
            } footer: {
                Text(client.status == .completed
                     ? "Completed clients keep their slot in the calendar but are skipped when the schedule is rebuilt."
                     : "Marking someone completed stamps the finish time and takes them out of future rebuilds.")
            }

            Section {
                DatePicker("Day", selection: $slotDay, displayedComponents: .date)

                if let handler = client.handler {
                    if SchedulingService.isClosed(on: slotDay) {
                        Text("The community is closed that day.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if availableSlots.isEmpty {
                        Text("\(handler.name) is fully booked that day.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Time", selection: slotBinding) {
                            Text("Not scheduled").tag(nil as Date?)
                            ForEach(availableSlots) { slot in
                                Text(slot.label).tag(slot.start as Date?)
                            }
                        }
                    }
                } else {
                    Text("Pick a handler first to see their free slots.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let scheduled = client.scheduledAt {
                    LabeledContent("Booked", value: scheduled.formatted(date: .abbreviated, time: .shortened))
                }
                if let link = client.sessionLink {
                    LabeledContent("Session link", value: link)
                        .font(.caption)
                }
            } header: {
                Text("Scheduling")
            } footer: {
                Text("Only slots the handler has free are offered. Sessions run \(SchedulingService.sessionLengthPhrase) between \(String(format: "%02d:%02d", SchedulingService.configuration.openingHour, SchedulingService.configuration.openingMinute)) and \(String(format: "%02d:%02d", SchedulingService.configuration.closingHour, SchedulingService.configuration.closingMinute)). Change these in Settings.")
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            slotDay = client.scheduledAt ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        }
        .onDisappear {
            // Leaving the screen mid-edit still commits what was typed.
            isEditingNotes = false
            try? context.save()
        }
        .alert("That slot just got taken", isPresented: $clashWarning) {
            Button("OK", role: .cancel) {}
        }
    }

    private func toggleNotesEditing() {
        if isEditingNotes {
            isEditingNotes = false
            notesFocused = false
            try? context.save()
        } else {
            isEditingNotes = true
            notesFocused = true
        }
    }

    // MARK: - Bindings

    private var handlerBinding: Binding<PersistentIdentifier?> {
        Binding {
            client.handler?.persistentModelID
        } set: { newValue in
            let previous = client.scheduledAt
            client.handler = handlers.first { $0.persistentModelID == newValue }
            // A new handler may already be busy at the old time.
            if let previous, let handler = client.handler {
                let clash = allClients.contains {
                    $0.persistentModelID != client.persistentModelID
                        && $0.handler?.persistentModelID == handler.persistentModelID
                        && $0.scheduledAt == previous
                }
                if clash {
                    client.scheduledAt = nil
                    client.sessionLink = nil
                    clashWarning = true
                }
            }
            try? context.save()
        }
    }

    private var categoryBinding: Binding<Priority> {
        Binding {
            client.priority
        } set: { newValue in
            client.priority = newValue
            if !newValue.isSchedulable {
                client.scheduledAt = nil
                client.sessionLink = nil
            }
            try? context.save()
        }
    }

    private var statusBinding: Binding<ClientStatus> {
        Binding { client.status } set: { client.status = $0; try? context.save() }
    }

    private var slotBinding: Binding<Date?> {
        Binding {
            client.scheduledAt
        } set: { newValue in
            guard let handler = client.handler else { return }
            if let newValue {
                if !SchedulingService.book(client: client, with: handler, at: newValue, allClients: allClients) {
                    clashWarning = true
                }
            } else {
                client.scheduledAt = nil
                client.sessionLink = nil
            }
            try? context.save()
        }
    }

    private var availableSlots: [SessionSlot] {
        guard let handler = client.handler else { return [] }
        return SchedulingService.availableSlots(
            for: handler,
            on: slotDay,
            excluding: client,
            allClients: allClients
        )
    }
}

// MARK: - Chat

/// Which thread the pane is showing. Demo is the model's roleplay; Live is
/// the real conversation the owner is having on WhatsApp or Messages.
enum ChatMode: String, CaseIterable, Identifiable {
    case demo = "Demo"
    case live = "Live"

    var id: String { rawValue }
    var symbol: String { self == .demo ? "sparkles" : "paperplane.fill" }
}

struct ClientChatPane: View {
    @Environment(\.modelContext) private var context
    @Environment(ChatService.self) private var chat
    @Environment(MessagingService.self) private var messaging
    @Bindable var client: Client

    @State private var mode: ChatMode = .demo
    @State private var draft = ""
    @State private var hasPrefilled = false

    // Live mode
    @State private var showSystemComposer = false
    @State private var pendingLiveMessage: ChatMessage?
    @State private var showLogReply = false
    @State private var loggedReply = ""
    @State private var errorMessage: String?
    @State private var isPolling = false

    private var visibleMessages: [ChatMessage] {
        mode == .demo ? client.demoMessages : client.liveMessages
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding { errorMessage != nil } set: { if !$0 { errorMessage = nil } }
    }

    var body: some View {
        VStack(spacing: 0) {
            modePicker

            if mode == .live {
                liveBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if visibleMessages.isEmpty {
                            emptyThread
                        } else {
                            Text("Today")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                        }

                        ForEach(visibleMessages) { message in
                            MessageBubble(message: message) {
                                confirmSent(message)
                            }
                            .id(message.persistentModelID)
                        }

                        if mode == .demo && chat.isReplying {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .id("typing")
                        }
                    }
                    .padding(.bottom, 8)
                }
                // Pin to the bottom so a growing composer never buries the
                // message the owner just sent.
                .defaultScrollAnchor(.bottom)
                .onChange(of: visibleMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(visibleMessages.last?.persistentModelID, anchor: .bottom)
                    }
                }
                .onChange(of: draft) { _, _ in
                    proxy.scrollTo(visibleMessages.last?.persistentModelID, anchor: .bottom)
                }
            }

            Divider()
            composer
        }
        .background(Color(.systemGroupedBackground))
        .task {
            guard !hasPrefilled, client.demoMessages.isEmpty, draft.isEmpty else { return }
            hasPrefilled = true
            draft = await chat.draftOpener(for: client)
        }
        .sheet(isPresented: $showSystemComposer) {
            if let number = PhoneNumber.e164(client.phone, defaultCountryCode: messaging.defaultCountryCode),
               let pending = pendingLiveMessage {
                SystemMessageComposer(recipient: "+" + number, body: pending.text) { result in
                    finishSystemCompose(result, for: pending)
                }
                .ignoresSafeArea()
            }
        }
        .alert("What did they say?", isPresented: $showLogReply) {
            TextField("Their reply", text: $loggedReply)
            Button("Save") { saveLoggedReply() }
            Button("Cancel", role: .cancel) { loggedReply = "" }
        } message: {
            Text("Paste or type what \(client.name) sent back, so the thread here matches the real one.")
        }
        .alert("Couldn't send", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var modePicker: some View {
        Picker("Thread", selection: $mode) {
            ForEach(ChatMode.allCases) { option in
                Label(option.rawValue, systemImage: option.symbol).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Live mode is the one that can actually reach a person, so it says
    /// exactly where the message is about to go before anything is sent.
    private var liveBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: messaging.channel.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sends via \(messaging.channel.rawValue)")
                    .font(.caption.weight(.semibold))
                Text(client.hasUsablePhone
                     ? PhoneNumber.display(client.phone, defaultCountryCode: messaging.defaultCountryCode)
                     : "No usable phone number")
                .font(.caption2)
                .foregroundStyle(client.hasUsablePhone ? Color.secondary : Color.red)
            }
            Spacer()
            if messaging.channel == .relay {
                Button {
                    Task { await pollRelay() }
                } label: {
                    if isPolling {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!messaging.isRelayConfigured || isPolling)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var emptyThread: some View {
        VStack(spacing: 6) {
            Image(systemName: mode == .demo ? "sparkles" : "paperplane")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(mode == .demo ? "No demo messages yet" : "No real messages yet")
                .font(.callout.weight(.medium))
            Text(mode == .demo
                 ? "Anything here is written by the on-device model. It never leaves the iPad."
                 : "Messages you send here really go to \(client.name).")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if chat.isDrafting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Drafting a message…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // WhatsApp proportions: a slim capsule that hugs the text, with
            // the action buttons sitting outside it rather than inflating it.
            HStack(alignment: .bottom, spacing: 8) {
                // A capsule's corner radius is half its height, so once the
                // field wraps to several lines the curve cuts into the first
                // and last line of text. A fixed 18pt radius still reads as a
                // pill on one line and stays correct as it grows.
                TextField(mode == .demo ? "Message" : "Message (sends for real)", text: $draft, axis: .vertical)
                    .font(.callout)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Color(.secondarySystemBackground),
                        in: .rect(cornerRadius: 18, style: .continuous)
                    )

                if mode == .live {
                    Button {
                        loggedReply = ""
                        showLogReply = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("Log a reply you received")
                }

                Button {
                    Task { await regenerate() }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .disabled(chat.isDrafting || chat.isReplying)
                .help("Redraft with the on-device model")

                Button {
                    Task { await send() }
                } label: {
                    if messaging.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: mode == .demo ? "paperplane.fill" : "arrow.up.forward.app.fill")
                            .font(.system(size: 15))
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .disabled(sendDisabled)
            }

            if mode == .live {
                Text(messaging.channel.needsHandoff
                     ? "You'll confirm the send in \(messaging.channel.rawValue)."
                     : "Sent through your relay server.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var sendDisabled: Bool {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if messaging.isSending { return true }
        if mode == .demo { return chat.isReplying }
        return !client.hasUsablePhone
    }

    // MARK: - Sending

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch mode {
        case .demo: sendDemo(text)
        case .live: await sendLive(text)
        }
    }

    private func sendDemo(_ text: String) {
        let outgoing = ChatMessage(text: text, isFromOwner: true)
        outgoing.client = client
        context.insert(outgoing)
        draft = ""
        try? context.save()

        Task {
            let reply = await chat.generateReply(for: client, history: client.demoMessages)
            let incoming = ChatMessage(text: reply, isFromOwner: false, isGenerated: true)
            incoming.client = client
            context.insert(incoming)
            if client.status == .waitingForAppointment && client.scheduledAt != nil {
                client.status = .scheduled
            }
            try? context.save()
        }
    }

    private func sendLive(_ text: String) async {
        // The message is recorded first so nothing is lost if the handoff
        // fails or the owner backs out of the other app.
        let outgoing = ChatMessage(
            text: text,
            isFromOwner: true,
            isLive: true,
            channel: messaging.channel,
            delivery: .pending
        )
        outgoing.client = client
        context.insert(outgoing)
        draft = ""
        try? context.save()

        if messaging.channel == .iMessage {
            guard SystemMessageComposer.canSend else {
                outgoing.delivery = .failed
                errorMessage = MessagingError.channelUnavailable(.iMessage).localizedDescription
                try? context.save()
                return
            }
            pendingLiveMessage = outgoing
            showSystemComposer = true
            return
        }

        let outcome = await messaging.send(text, to: client)
        outgoing.delivery = outcome.delivery
        if case .failed(let error) = outcome {
            errorMessage = error.localizedDescription
        } else {
            markContacted()
        }
        try? context.save()
    }

    private func finishSystemCompose(_ result: MessageComposeResult, for message: ChatMessage) {
        showSystemComposer = false
        pendingLiveMessage = nil
        switch result {
        case .sent:
            message.delivery = .sent
            markContacted()
        case .cancelled:
            message.delivery = .pending
        case .failed:
            message.delivery = .failed
            errorMessage = "iOS couldn't send that message."
        @unknown default:
            message.delivery = .pending
        }
        try? context.save()
    }

    /// The owner ticking off a message they finished sending in another app.
    private func confirmSent(_ message: ChatMessage) {
        guard message.needsConfirmation else { return }
        message.delivery = .sent
        markContacted()
        try? context.save()
    }

    private func saveLoggedReply() {
        let text = loggedReply.trimmingCharacters(in: .whitespacesAndNewlines)
        loggedReply = ""
        guard !text.isEmpty else { return }

        let incoming = ChatMessage(
            text: text,
            isFromOwner: false,
            isLive: true,
            channel: messaging.channel,
            delivery: .delivered
        )
        incoming.client = client
        context.insert(incoming)
        if client.status == .noResponse || client.status == .newIntake {
            client.status = .inProgress
        }
        try? context.save()
    }

    private func pollRelay() async {
        isPolling = true
        defer { isPolling = false }

        let since = client.lastLiveInboundAt ?? Date.now.addingTimeInterval(-7 * 24 * 3600)
        let inbound = await messaging.fetchInbound(for: client, since: since)
        guard !inbound.isEmpty else { return }

        for item in inbound {
            let message = ChatMessage(
                text: item.text,
                isFromOwner: false,
                isLive: true,
                channel: .relay,
                delivery: .delivered,
                timestamp: item.timestamp
            )
            message.client = client
            context.insert(message)
        }
        if client.status == .noResponse || client.status == .newIntake {
            client.status = .inProgress
        }
        try? context.save()
    }

    /// A real message going out means this person is no longer untouched.
    private func markContacted() {
        if client.status == .newIntake || client.status == .noResponse {
            client.status = .inProgress
        }
        if client.status == .waitingForAppointment && client.scheduledAt != nil {
            client.status = .scheduled
        }
    }

    private func regenerate() async {
        draft = await chat.draftOpener(for: client)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    /// Called when the owner ticks off a message they sent in another app.
    var onConfirmSent: () -> Void = {}

    var body: some View {
        HStack {
            if message.isFromOwner { Spacer(minLength: 60) }

            VStack(alignment: message.isFromOwner ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(message.isFromOwner ? Color.white : Color.primary)
                    .background(bubbleFill, in: .rect(cornerRadius: 20))

                HStack(spacing: 4) {
                    if message.isGenerated {
                        Image(systemName: "sparkles")
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))

                    if message.isLive && message.isFromOwner {
                        Image(systemName: message.delivery.symbol)
                        Text(message.delivery.label)
                    }
                }
                .font(.caption2)
                .foregroundStyle(message.delivery == .failed ? Color.red : Color.secondary)

                // A deep link can't tell us whether the owner actually tapped
                // send in WhatsApp, so they say so here.
                if message.needsConfirmation {
                    Button("Mark as sent", systemImage: "checkmark.circle") {
                        onConfirmSent()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if !message.isFromOwner { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    private var bubbleFill: AnyShapeStyle {
        guard message.isFromOwner else {
            return AnyShapeStyle(Color(.secondarySystemGroupedBackground))
        }
        if message.delivery == .failed { return AnyShapeStyle(Color.red) }
        // Live messages sit in a deeper shade so a real send never looks like
        // a demo one at a glance.
        if message.isLive { return AnyShapeStyle(Color.green.mix(with: .black, by: 0.15)) }
        return AnyShapeStyle(Color.accentColor)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                phase = (phase + 1) % 3
            }
        }
    }
}
