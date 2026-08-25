//
//  CalendarView.swift
//  Kunang
//
//  The Schedule screen, laid out the way Calendar.app does it: hours running
//  down the left, sessions drawn as blocks at their real time and height.
//  Day and Week modes; overlapping sessions split the width between them.
//
//  Positions come from CommunitySettings, so a community that opens at 06:00
//  with 45-minute sessions gets a calendar that starts at 06:00 with
//  proportionally shorter blocks.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit

struct CalendarView: View {
    @Query private var clients: [Client]

    @State private var scope: CalendarScope = .day
    @State private var anchorDay: Date = .now
    @State private var selectedClient: Client?

    /// Points per hour. Enough that a 45-minute session is still tappable.
    private let hourHeight: CGFloat = 64
    private let gutterWidth: CGFloat = 56
    /// Below this a day column can't show a name, so we scroll instead.
    private let minimumDayWidth: CGFloat = 132

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if bookedClients.isEmpty {
                ContentUnavailableView {
                    Label("Nothing booked", systemImage: "calendar")
                } description: {
                    Text(clients.isEmpty
                         ? "Upload a spreadsheet to get started."
                         : "Nobody is booked in this range. Try another week, or import again from Upload.")
                }
            } else {
                timeline
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // One control only — a second glass capsule beside this one
            // crowds it on iPadOS 26.
            ToolbarItem(placement: .topBarTrailing) {
                Picker("View", selection: $scope) {
                    ForEach(CalendarScope.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .navigationDestination(item: $selectedClient) { client in
            ClientDetailView(client: client)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(rangeTitle)
                    .font(.headline)
                Text("\(sessionsInRange.count) session\(sessionsInRange.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !Calendar.current.isDate(anchorDay, inSameDayAs: .now) {
                Button("Today") { withAnimation { anchorDay = .now } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Timeline

    private var timeline: some View {
        GeometryReader { geometry in
            // Divide whatever's left after the hour gutter between the days.
            // Only fall back to side-scrolling when that would squeeze the
            // columns below a readable width.
            let available = geometry.size.width - gutterWidth
            let dayCount = max(1, weekDays.count)
            let evenWidth = available / CGFloat(dayCount)
            let columnWidth = max(evenWidth, minimumDayWidth)
            let fits = evenWidth >= minimumDayWidth

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    hourGutter
                        .frame(width: gutterWidth)

                    if scope == .day {
                        dayColumn(for: anchorDay)
                            .frame(width: max(available, minimumDayWidth))
                    } else if fits {
                        HStack(alignment: .top, spacing: 1) {
                            ForEach(weekDays, id: \.self) { day in
                                dayColumn(for: day, showsHeading: true)
                                    .frame(width: columnWidth)
                            }
                        }
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 1) {
                                ForEach(weekDays, id: \.self) { day in
                                    dayColumn(for: day, showsHeading: true)
                                        .frame(width: columnWidth)
                                }
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            if scope == .week {
                // Line the hours up with the day headings next to them.
                Color.clear.frame(height: dayHeadingHeight)
            }
            ForEach(displayedHours, id: \.self) { hour in
                ZStack(alignment: .topTrailing) {
                    Color.clear
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                        .offset(y: -6)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private func dayColumn(for day: Date, showsHeading: Bool = false) -> some View {
        VStack(spacing: 0) {
            if showsHeading {
                dayHeading(for: day)
                    .frame(height: dayHeadingHeight)
            }

            ZStack(alignment: .topLeading) {
                hourLines

                // Overlapping sessions share the column's width between them,
                // the way Calendar.app splits simultaneous events.
                GeometryReader { geometry in
                    ForEach(layout(for: day), id: \.client.persistentModelID) { placed in
                        let slot = geometry.size.width / CGFloat(max(1, placed.columnCount))
                        SessionBlock(client: placed.client) {
                            selectedClient = placed.client
                        }
                        .frame(width: max(24, slot - 3), height: max(22, placed.height))
                        .offset(x: slot * CGFloat(placed.column) + 2, y: placed.offsetY)
                    }
                }

                if Calendar.current.isDate(day, inSameDayAs: .now), let y = nowOffset {
                    nowIndicator.offset(y: y)
                }
            }
            .frame(height: CGFloat(displayedHours.count) * hourHeight)
            .background(Color(.systemBackground))
        }
    }

    private func dayHeading(for day: Date) -> some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: .now)
        return VStack(spacing: 1) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(displayedHours, id: \.self) { _ in
                VStack(spacing: 0) {
                    Divider()
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private var nowIndicator: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(.red)
                .frame(height: 1)
        }
    }

    // MARK: - Layout maths

    /// One session, resolved to a pixel position and a share of the column.
    private struct PlacedSession {
        let client: Client
        let offsetY: CGFloat
        let height: CGFloat
        let column: Int
        let columnCount: Int
    }

    private var dayHeadingHeight: CGFloat { 40 }

    /// The hour range the calendar draws, taken from the owner's settings and
    /// widened if anything is booked outside it.
    private var displayedHours: [Int] {
        let config = SchedulingService.configuration
        var first = config.openingHour
        var last = max(config.openingHour + 1, Int(ceil(Double(config.closingMinutesFromMidnight) / 60)))

        let calendar = Calendar.current
        for client in sessionsInRange {
            guard let start = client.scheduledAt else { continue }
            let startMinutes = calendar.component(.hour, from: start) * 60
                + calendar.component(.minute, from: start)
            first = min(first, startMinutes / 60)
            last = max(last, Int(ceil(Double(startMinutes + SchedulingService.sessionMinutes) / 60)))
        }
        guard last > first else { return [first] }
        return Array(first..<last)
    }

    private func layout(for day: Date) -> [PlacedSession] {
        let calendar = Calendar.current
        let sessions = bookedClients
            .filter { calendar.isDate($0.scheduledAt ?? .distantPast, inSameDayAs: day) }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }

        guard let firstHour = displayedHours.first else { return [] }

        // Group sessions that overlap in time so they can share the width.
        var groups: [[Client]] = []
        var current: [Client] = []
        var groupEnd: Date?

        for client in sessions {
            guard let start = client.scheduledAt else { continue }
            let end = start.addingTimeInterval(SchedulingService.sessionLength)
            if let existingEnd = groupEnd, start < existingEnd {
                current.append(client)
                groupEnd = max(existingEnd, end)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [client]
                groupEnd = end
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.flatMap { group -> [PlacedSession] in
            group.enumerated().compactMap { index, client in
                guard let start = client.scheduledAt else { return nil }
                let minutesFromTop = Double(
                    calendar.component(.hour, from: start) * 60
                        + calendar.component(.minute, from: start)
                        - firstHour * 60
                )
                return PlacedSession(
                    client: client,
                    offsetY: CGFloat(minutesFromTop / 60) * hourHeight,
                    height: CGFloat(Double(SchedulingService.sessionMinutes) / 60) * hourHeight - 2,
                    column: index,
                    columnCount: group.count
                )
            }
        }
    }

    private var nowOffset: CGFloat? {
        guard let firstHour = displayedHours.first, let lastHour = displayedHours.last else { return nil }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: .now)
        let minute = calendar.component(.minute, from: .now)
        guard hour >= firstHour, hour <= lastHour else { return nil }
        let minutesFromTop = Double((hour - firstHour) * 60 + minute)
        return CGFloat(minutesFromTop / 60) * hourHeight
    }

    // MARK: - Range

    private var weekDays: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDay) else { return [anchorDay] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
            .filter { !SchedulingService.isClosed(on: $0) }
    }

    private var bookedClients: [Client] {
        clients.filter { $0.scheduledAt != nil }
    }

    private var sessionsInRange: [Client] {
        let calendar = Calendar.current
        switch scope {
        case .day:
            return bookedClients.filter { calendar.isDate($0.scheduledAt ?? .distantPast, inSameDayAs: anchorDay) }
        case .week:
            let days = weekDays
            return bookedClients.filter { client in
                guard let date = client.scheduledAt else { return false }
                return days.contains { calendar.isDate($0, inSameDayAs: date) }
            }
        }
    }

    private var rangeTitle: String {
        switch scope {
        case .day:
            return anchorDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else {
                return anchorDay.formatted(date: .abbreviated, time: .omitted)
            }
            return first.formatted(.dateTime.day().month(.abbreviated))
                + " – " + last.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    private func step(by amount: Int) {
        let component: Calendar.Component = scope == .day ? .day : .weekOfYear
        guard let next = Calendar.current.date(byAdding: component, value: amount, to: anchorDay) else { return }
        withAnimation { anchorDay = next }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour())
    }

}

// MARK: - Scope

enum CalendarScope: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"

    var id: String { rawValue }
}

// MARK: - Pieces

struct SessionBlock: View {
    let client: Client
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(client.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let handler = client.handler {
                    Text(handler.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if client.status == .completed {
                    Label("Done", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(client.priority.tint.opacity(client.status == .completed ? 0.10 : 0.20))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(client.priority.tint)
                    .frame(width: 3)
            }
            .clipShape(.rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
    .modelContainer(PreviewData.container)
    .previewServices()
}
