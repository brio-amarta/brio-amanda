//
//  OverviewView.swift
//  Kunang
//
//  Home screen: profile header plus one card per category.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit

struct OverviewView: View {
    @Query private var clients: [Client]
    @Query private var handlers: [Handler]

    @AppStorage("ownerName") private var ownerName = "Community Owner"
    @AppStorage("ownerRole") private var ownerRole = "Admin"

    var onSelectCategory: (Priority) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                profileHeader

                if clients.isEmpty {
                    emptyState
                } else {
                    section("Overview") {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Priority.allCases) { priority in
                                Button {
                                    onSelectCategory(priority)
                                } label: {
                                    CategoryCard(
                                        priority: priority,
                                        numerator: numerator(for: priority),
                                        denominator: denominator(for: priority)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section("This week") {
                        LazyVGrid(columns: columns, spacing: 16) {
                            StatTile(title: "Clients", value: "\(clients.count)", symbol: "person.3.fill", tint: .blue)
                            StatTile(title: "Sessions booked", value: "\(bookedCount)", symbol: "calendar.badge.checkmark", tint: .green)
                            StatTile(title: "Handlers active", value: "\(handlers.filter { !$0.isPaused }.count)", symbol: "person.2.badge.gearshape", tint: .purple)
                            StatTile(title: "Avg. wellbeing", value: averageScore, symbol: "heart.text.square.fill", tint: .pink)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Pieces

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(ownerName)
                    .font(.largeTitle.bold())
                NavigationLink {
                    SettingsView()
                } label: {
                    HStack(spacing: 4) {
                        Text(ownerRole)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No clients yet", systemImage: "tray")
        } description: {
            Text("Upload a spreadsheet to triage your community and build a schedule.")
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Numbers

    private func members(of priority: Priority) -> [Client] {
        clients.filter { $0.priority == priority }
    }

    private func denominator(for priority: Priority) -> Int {
        members(of: priority).count
    }

    private func numerator(for priority: Priority) -> Int {
        let group = members(of: priority)
        return switch priority.metric {
        case .scheduled: group.filter { $0.scheduledAt != nil }.count
        case .responded: group.filter(\.hasResponded).count
        }
    }

    private var bookedCount: Int {
        clients.filter { $0.scheduledAt != nil }.count
    }

    private var averageScore: String {
        guard !clients.isEmpty else { return "—" }
        let total = clients.reduce(0) { $0 + $1.mentalHealthScore }
        return String(format: "%.1f", total / Double(clients.count))
    }
}

// MARK: - Cards

struct CategoryCard: View {
    let priority: Priority
    let numerator: Int
    let denominator: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Crisis" and "Others" fit on one line while "High Priority" and
            // "Referral Required" wrap, which used to leave every card with a
            // different title height and icon position. Reserving two lines and
            // giving the icon a fixed frame pins all five to the same grid.
            HStack(alignment: .top, spacing: 8) {
                Text(priority.rawValue)
                    .font(.title.bold())
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Image(systemName: priority.symbol)
                    .font(.title3)
                    .foregroundStyle(priority.tint)
                    .frame(width: 28, height: 28, alignment: .topTrailing)
            }

            Spacer(minLength: 16)

            HStack(alignment: .bottom) {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    FractionView(numerator: numerator, denominator: denominator)
                    Text(priority.metric.rawValue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(minHeight: 190, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

/// The slashed "10/13" numeral from the mockups.
struct FractionView: View {
    let numerator: Int
    let denominator: Int

    var body: some View {
        HStack(spacing: 2) {
            Text("\(numerator)")
                .font(.title.bold())
                .offset(y: -6)
            Text("/")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.primary)
            Text("\(denominator)")
                .font(.title.bold())
                .offset(y: 6)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}

#Preview {
    NavigationStack {
        OverviewView(onSelectCategory: { _ in })
    }
    .modelContainer(PreviewData.container)
    .previewServices()
}
