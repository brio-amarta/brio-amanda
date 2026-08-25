//
//  HandlersView.swift
//  Kunang
//
//  Add handlers, see the leaderboard, and drill into one handler's load.
//

import SwiftUI
import SwiftData
import Foundation

struct HandlersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Handler.createdAt) private var handlers: [Handler]
    @Query private var clients: [Client]

    @State private var isAdding = false
    @State private var newName = ""
    @State private var bulkCount = 1

    var body: some View {
        List {
            if handlers.isEmpty {
                ContentUnavailableView {
                    Label("No handlers yet", systemImage: "person.2")
                } description: {
                    Text("Add the people who run sessions. Clients are shared out evenly between them.")
                } actions: {
                    Button("Add handler") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section("Leaderboard") {
                    ForEach(Array(leaderboard.enumerated()), id: \.element.persistentModelID) { index, handler in
                        NavigationLink {
                            HandlerDetailView(handler: handler)
                        } label: {
                            HandlerRow(handler: handler, rank: index + 1)
                        }
                    }
                    .onDelete(perform: delete)
                }

                Section("Capacity") {
                    LabeledContent("Clients", value: "\(clients.count)")
                    LabeledContent("Handlers", value: "\(handlers.filter { !$0.isPaused }.count)")
                    LabeledContent("Even split", value: "\(evenSplit) each")
                    LabeledContent("Slots per handler per day", value: "\(SchedulingService.slotsPerDay)")
                }
            }
        }
        .navigationTitle("Handlers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add handler", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $isAdding) {
            addSheet
        }
    }

    // MARK: - Add sheet

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("One handler") {
                    TextField("Name", text: $newName)
                    Button("Add") { addSingle() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    Stepper("Add \(bulkCount) placeholder handler\(bulkCount == 1 ? "" : "s")", value: $bulkCount, in: 1...20)
                    Button("Add \(bulkCount)") { addBulk() }
                } header: {
                    Text("Several at once")
                } footer: {
                    Text("Creates Handler 1, Handler 2 and so on. Rename them later.")
                }
            }
            .navigationTitle("New handler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isAdding = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Data

    private var leaderboard: [Handler] {
        handlers.sorted { $0.leaderboardScore > $1.leaderboardScore }
    }

    private var evenSplit: Int {
        let active = handlers.filter { !$0.isPaused }.count
        guard active > 0 else { return 0 }
        return Int(ceil(Double(clients.count) / Double(active)))
    }

    private func addSingle() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(Handler(name: trimmed, colorIndex: handlers.count % Handler.palette.count))
        try? context.save()
        newName = ""
        isAdding = false
    }

    private func addBulk() {
        let offset = handlers.count
        for index in 0..<bulkCount {
            context.insert(
                Handler(
                    name: "Handler \(offset + index + 1)",
                    colorIndex: (offset + index) % Handler.palette.count
                )
            )
        }
        try? context.save()
        isAdding = false
    }

    private func delete(_ offsets: IndexSet) {
        let board = leaderboard
        for index in offsets where index < board.count {
            context.delete(board[index])
        }
        try? context.save()
    }
}

// MARK: - Rows

struct HandlerAvatar: View {
    let handler: Handler
    var size: CGFloat = 40

    private var color: Color {
        [Color.blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown][
            handler.colorIndex % 8
        ]
    }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(handler.initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct HandlerRow: View {
    let handler: Handler
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(rank <= 3 ? .primary : .secondary)
                .frame(width: 24)

            HandlerAvatar(handler: handler)

            VStack(alignment: .leading, spacing: 2) {
                Text(handler.name)
                    .font(.body.weight(.medium))
                Text("\(handler.ongoingClients.count) ongoing · \(handler.completedClients.count) completed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", handler.averagePerWeek))
                    .font(.headline.monospacedDigit())
                Text("per week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if handler.isPaused {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct HandlerDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var handler: Handler

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    HandlerAvatar(handler: handler, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $handler.name)
                            .font(.title2.bold())
                        TextField("Role", text: $handler.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Picker("Avatar colour", selection: $handler.colorIndex) {
                    ForEach(Array(Handler.palette.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }

                Toggle("Paused", isOn: $handler.isPaused)
            }

            Section("Statistics") {
                LabeledContent("Total handled", value: "\(handler.totalHandled)")
                LabeledContent("Ongoing", value: "\(handler.ongoingClients.count)")
                LabeledContent("Completed", value: "\(handler.completedClients.count)")
                LabeledContent("Average per week", value: String(format: "%.1f", handler.averagePerWeek))
                LabeledContent("Completion rate", value: handler.totalHandled == 0 ? "—" : "\(Int(handler.completionRate * 100))%")
            }

            if !handler.ongoingClients.isEmpty {
                Section("Ongoing") {
                    ForEach(handler.ongoingClients.sorted { $0.sortDate < $1.sortDate }) { client in
                        NavigationLink {
                            ClientDetailView(client: client)
                        } label: {
                            miniRow(client)
                        }
                    }
                }
            }

            if !handler.completedClients.isEmpty {
                Section("Completed") {
                    ForEach(handler.completedClients.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) { client in
                        NavigationLink {
                            ClientDetailView(client: client)
                        } label: {
                            miniRow(client)
                        }
                    }
                }
            }
        }
        .navigationTitle(handler.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }

    private func miniRow(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(client.name)
                Spacer()
                PriorityChip(priority: client.priority)
            }
            Text(client.scheduleDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        HandlersView()
    }
    .modelContainer(PreviewData.container)
    .previewServices()
}
