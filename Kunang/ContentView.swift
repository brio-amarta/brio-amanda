//
//  ContentView.swift
//  Kunang
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
    case settings
    case category(Priority)

    var title: String {
        switch self {
        case .overview: "Overview"
        case .upload: "Upload"
        case .schedule: "Schedule"
        case .handlers: "Handlers"
        case .settings: "Settings"
        case .category(let priority): priority.rawValue
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .upload: "tray.and.arrow.down"
        case .schedule: "calendar.day.timeline.left"
        case .handlers: "person.2"
        case .settings: "gearshape"
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
    @State private var messaging = MessagingService()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack {
                detail
            }
        }
        // .automatic resolves to prominentDetail on iPad, which floats the
        // sidebar *over* the detail column — that's what was covering the
        // table. .balanced makes the two share the width instead.
        .navigationSplitViewStyle(.balanced)
        .environment(triage)
        .environment(chat)
        .environment(messaging)
        .task {
            // Load the owner's saved settings before anything schedules or sends.
            let settings = CommunitySettings.current(in: context)
            settings.apply()
            chat.adopt(settings)
            messaging.adopt(settings)

            // Keep pulling whatever arrives at the community's WhatsApp number
            // so a message shows up here without the owner going looking.
            while !Task.isCancelled {
                await InboxSync.run(messaging: messaging, settings: settings, context: context)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                row(.overview)
                row(.upload)
                row(.schedule)
                row(.handlers)
                row(.settings)
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
        .navigationTitle("Kunang Workspace")
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
            CalendarView()
        case .handlers:
            HandlersView()
        case .settings:
            SettingsView()
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

// MARK: - Preview helpers

extension View {
    /// The three services every screen expects, wired up for previews.
    func previewServices() -> some View {
        self
            .environment(TriageService())
            .environment(ChatService())
            .environment(MessagingService())
    }
}
