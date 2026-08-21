//
//  ContentView.swift
//  Mentalzz
//
//  Created by I Made Debrio Amarta on 20/08/26.
//
//  Holds RootView, the split-view shell every other screen hangs off.
//

import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case overview
    case upload
    case schedule
    case handlers
    case category(Priority)

    var title: String {
        switch self {
        case .overview: "Overview"
        case .upload: "Upload"
        case .schedule: "Schedule"
        case .handlers: "Handlers"
        case .category(let priority): priority.rawValue
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .upload: "tray.and.arrow.down"
        case .schedule: "calendar"
        case .handlers: "person.2"
        case .category(let priority): priority.symbol
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var clients: [Client]

    @State private var selection: SidebarItem? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var triage = TriageService()
    @State private var chat = ChatService()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack {
                detail
            }
        }
        .environment(triage)
        .environment(chat)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                row(.overview)
                row(.upload)
                row(.schedule)
                row(.handlers)
            }

            Section("Categories") {
                ForEach(Priority.allCases) { priority in
                    NavigationLink(value: SidebarItem.category(priority)) {
                        Label {
                            HStack {
                                Text(priority.rawValue)
                                Spacer()
                                if needsAttention(priority) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                } else {
                                    Text("\(count(for: priority))")
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                }
                            }
                        } icon: {
                            Image(systemName: priority.symbol)
                                .foregroundStyle(priority.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Mentalzz")
        .listStyle(.sidebar)
    }

    private func row(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label(item.title, systemImage: item.symbol)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview, nil:
            OverviewView(onSelectCategory: { selection = .category($0) })
        case .upload:
            UploadView(onFinished: { selection = .schedule })
        case .schedule:
            ScheduleView(priority: nil)
        case .handlers:
            HandlersView()
        case .category(let priority):
            ScheduleView(priority: priority)
        }
    }

    // MARK: - Badges

    private func count(for priority: Priority) -> Int {
        clients.filter { $0.priority == priority }.count
    }

    /// A red dot means somebody in that bucket still has nothing booked and no reply sent.
    private func needsAttention(_ priority: Priority) -> Bool {
        clients.contains {
            $0.priority == priority
                && !$0.status.isClosed
                && $0.scheduledAt == nil
                && !$0.hasResponded
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
