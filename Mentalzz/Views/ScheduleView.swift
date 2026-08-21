//
//  ScheduleView.swift
//  Mentalzz
//
//  The sortable session table. Pass a priority to show one category,
//  or nil for the full schedule.
//

import SwiftUI
import SwiftData
import Foundation

struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var clients: [Client]
    @Query(sort: \Handler.createdAt) private var handlers: [Handler]

    let priority: Priority?

    @State private var sortOrder = [KeyPathComparator(\Client.sortDate, order: .forward)]
    @State private var search = ""
    @State private var selectedClient: Client?
    @State private var showingRebuildConfirm = false
    @State private var lastReport: SchedulingReport?

    var body: some View {
        Group {
            if visibleClients.isEmpty {
                ContentUnavailableView {
                    Label(priority?.rawValue ?? "Nothing scheduled", systemImage: priority?.symbol ?? "calendar")
                } description: {
                    Text(clients.isEmpty
                         ? "Upload a spreadsheet to get started."
                         : "Nobody is in this category right now.")
                }
            } else if sizeClass == .compact {
                compactList
            } else {
                table
            }
        }
        .navigationTitle(priority?.rawValue ?? "Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search name or location")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                fractionBadge
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingRebuildConfirm = true
                    } label: {
                        Label("Rebuild schedule", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Divider()
                    Section("Sort by") {
                        Button("Session time") { sortOrder = [KeyPathComparator(\Client.sortDate, order: .forward)] }
                        Button("Name") { sortOrder = [KeyPathComparator(\Client.name, order: .forward)] }
                        Button("Age") { sortOrder = [KeyPathComparator(\Client.age, order: .forward)] }
                        Button("Wellbeing score") { sortOrder = [KeyPathComparator(\Client.mentalHealthScore, order: .forward)] }
                        Button("Priority") { sortOrder = [KeyPathComparator(\Client.priorityRank, order: .forward)] }
                        Button("Handler") { sortOrder = [KeyPathComparator(\Client.handlerName, order: .forward)] }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(item: $selectedClient) { client in
            ClientDetailView(client: client)
        }
        .confirmationDialog(
            "Rebuild the whole schedule?",
            isPresented: $showingRebuildConfirm,
            titleVisibility: .visible
        ) {
            Button("Rebuild", role: .destructive) { rebuild() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone gets a freshly randomised handler and a new slot. Chats are kept.")
        }
        .alert(
            "Schedule rebuilt",
            isPresented: Binding(
                get: { lastReport != nil },
                set: { if !$0 { lastReport = nil } }
            )
        ) {
            Button("OK") { lastReport = nil }
        } message: {
            Text(lastReport?.summary ?? "")
        }
    }

    // MARK: - Table (iPad / regular width)

    private var table: some View {
        Table(visibleClients, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { client in
                Button {
                    selectedClient = client
                } label: {
                    Text(client.name)
                        .underline()
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            .width(min: 140)

            TableColumn("Age", value: \.age) { client in
                Text(client.age == 0 ? "—" : "\(client.age)")
            }
            .width(min: 44, max: 70)

            TableColumn("Location", value: \.location) { client in
                Text(client.location.isEmpty ? "—" : client.location)
            }
            .width(min: 100)

            TableColumn("Score", value: \.mentalHealthScore) { client in
                Text(client.scoreDescription)
                    .monospacedDigit()
            }
            .width(min: 60, max: 90)

            TableColumn("Priority", value: \.priorityRank) { client in
                PriorityChip(priority: client.priority)
            }
            .width(min: 130)

            TableColumn("Status", value: \.statusRaw) { client in
                Label(client.status.rawValue, systemImage: client.status.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
                    .foregroundStyle(client.status.tint)
            }
            .width(min: 140)

            TableColumn("Handler", value: \.handlerName) { client in
                Text(client.handlerName)
            }
            .width(min: 110)

            TableColumn("Session", value: \.sortDate) { client in
                Text(client.scheduleDescription)
                    .monospacedDigit()
            }
            .width(min: 150)

            TableColumn("Link") { client in
                if let link = client.sessionLink {
                    Text(link)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 140)
        }
    }

    // MARK: - List (iPhone / compact width)

    private var compactList: some View {
        List(visibleClients) { client in
            Button {
                selectedClient = client
            } label: {
                ClientRow(client: client)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Toolbar bits

    private var fractionBadge: some View {
        let group = visibleClients
        let metric = priority?.metric ?? .scheduled
        let done = switch metric {
        case .scheduled: group.filter { $0.scheduledAt != nil }.count
        case .responded: group.filter(\.hasResponded).count
        }
        return VStack(alignment: .trailing, spacing: 0) {
            Text("\(done)/\(group.count)")
                .font(.headline.monospacedDigit())
            Text(metric.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private var visibleClients: [Client] {
        var result = clients
        if let priority {
            result = result.filter { $0.priority == priority }
        }
        if !search.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || $0.location.localizedCaseInsensitiveContains(search)
            }
        }
        return result.sorted(using: sortOrder)
    }

    private func rebuild() {
        lastReport = SchedulingService.autoSchedule(clients: clients, handlers: handlers)
        try? context.save()
    }
}

// MARK: - Row pieces

struct PriorityChip: View {
    let priority: Priority

    var body: some View {
        Label(priority.rawValue, systemImage: priority.symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priority.tint.opacity(0.16), in: .capsule)
            .foregroundStyle(priority.tint)
    }
}

struct ClientRow: View {
    let client: Client

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(client.name)
                    .font(.body.weight(.semibold))
                Spacer()
                PriorityChip(priority: client.priority)
            }
            Text("\(client.age == 0 ? "—" : "\(client.age)") · \(client.location.isEmpty ? "—" : client.location) · score \(client.scoreDescription)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(client.scheduleDescription, systemImage: "calendar")
                if let handler = client.handler {
                    Label(handler.name, systemImage: "person")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

#Preview {
    NavigationStack {
        ScheduleView(priority: nil)
    }
    .modelContainer(PreviewData.container)
    .environment(ChatService())
}
