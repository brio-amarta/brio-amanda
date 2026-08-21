//
//  ClientDetailView.swift
//  Mentalzz
//
//  Left: the client record with editable handler, category, status and slot.
//  Right: the chat, drafted and answered by the on-device model.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit

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

            Section("Notes") {
                TextEditor(text: $client.notes)
                    .frame(minHeight: 120)
                    .font(.callout)
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

            Section("Status") {
                Picker("Status", selection: statusBinding) {
                    ForEach(ClientStatus.allCases) { status in
                        Label(status.rawValue, systemImage: status.symbol).tag(status)
                    }
                }
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
                Text("Only slots the handler has free are offered. Sessions run 90 minutes between 08:00 and 17:00.")
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            slotDay = client.scheduledAt ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        }
        .onDisappear { try? context.save() }
        .alert("That slot just got taken", isPresented: $clashWarning) {
            Button("OK", role: .cancel) {}
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

struct ClientChatPane: View {
    @Environment(\.modelContext) private var context
    @Environment(ChatService.self) private var chat
    @Bindable var client: Client

    @State private var draft = ""
    @State private var hasPrefilled = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        Text("Today")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)

                        ForEach(client.sortedMessages) { message in
                            MessageBubble(message: message)
                                .id(message.persistentModelID)
                        }

                        if chat.isReplying {
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
                .onChange(of: client.sortedMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(client.sortedMessages.last?.persistentModelID, anchor: .bottom)
                    }
                }
            }

            Divider()
            composer
        }
        .background(Color(.systemGroupedBackground))
        .task {
            guard !hasPrefilled, client.sortedMessages.isEmpty, draft.isEmpty else { return }
            hasPrefilled = true
            draft = await chat.draftOpener(for: client)
        }
    }

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

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground), in: .capsule)

                Button {
                    Task { await regenerate() }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(chat.isDrafting || chat.isReplying)
                .help("Redraft with the on-device model")

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isReplying)
            }
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Actions

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let outgoing = ChatMessage(text: text, isFromOwner: true)
        outgoing.client = client
        context.insert(outgoing)
        draft = ""
        try? context.save()

        Task {
            let reply = await chat.generateReply(for: client, history: client.sortedMessages)
            let incoming = ChatMessage(text: reply, isFromOwner: false, isGenerated: true)
            incoming.client = client
            context.insert(incoming)
            if client.status == .waitingForAppointment && client.scheduledAt != nil {
                client.status = .scheduled
            }
            try? context.save()
        }
    }

    private func regenerate() async {
        draft = await chat.draftOpener(for: client)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromOwner { Spacer(minLength: 60) }

            VStack(alignment: message.isFromOwner ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(message.isFromOwner ? .white : .primary)
                    .background(
                        message.isFromOwner ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: .rect(cornerRadius: 20)
                    )

                HStack(spacing: 4) {
                    if message.isGenerated {
                        Image(systemName: "sparkles")
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !message.isFromOwner { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
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
