//
//  Priority.swift
//  Mentalzz
//

import SwiftUI

/// The five triage buckets a client can fall into.
enum Priority: String, Codable, CaseIterable, Identifiable, Hashable {
    case crisis = "Crisis"
    case highPriority = "High Priority"
    case moderate = "Moderate"
    case referralRequired = "Referral Required"
    case others = "Others"

    var id: String { rawValue }

    /// Ordering used when the scheduler decides who gets the earliest slot.
    var rank: Int {
        switch self {
        case .crisis: 0
        case .highPriority: 1
        case .moderate: 2
        case .referralRequired: 3
        case .others: 4
        }
    }

    var symbol: String {
        switch self {
        case .crisis: "exclamationmark.triangle.fill"
        case .highPriority: "flame.fill"
        case .moderate: "figure.mind.and.body"
        case .referralRequired: "arrow.uturn.forward.circle.fill"
        case .others: "tray.fill"
        }
    }

    var tint: Color {
        switch self {
        case .crisis: .red
        case .highPriority: .orange
        case .moderate: .yellow
        case .referralRequired: .blue
        case .others: .gray
        }
    }

    /// Whether the overview card counts scheduled sessions or replies sent.
    var metric: OverviewMetric {
        switch self {
        case .crisis, .highPriority, .moderate: .scheduled
        case .referralRequired, .others: .responded
        }
    }

    /// Categories the app books sessions for. Referrals and Others are messaged, not booked.
    var isSchedulable: Bool {
        self == .crisis || self == .highPriority || self == .moderate
    }
}

enum OverviewMetric: String {
    case scheduled = "Scheduled"
    case responded = "Responded"
}

/// Where a client currently sits in the intake funnel.
enum ClientStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case newIntake = "New"
    case waitingForAppointment = "Waiting for appointment"
    case scheduled = "Scheduled"
    case inProgress = "In progress"
    case completed = "Completed"
    case referredOut = "Referred out"
    case noResponse = "No response"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .newIntake: "sparkles"
        case .waitingForAppointment: "hourglass"
        case .scheduled: "calendar.badge.checkmark"
        case .inProgress: "waveform.path.ecg"
        case .completed: "checkmark.seal.fill"
        case .referredOut: "mappin.and.ellipse"
        case .noResponse: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .newIntake: .purple
        case .waitingForAppointment: .orange
        case .scheduled: .blue
        case .inProgress: .teal
        case .completed: .green
        case .referredOut: .indigo
        case .noResponse: .secondary
        }
    }

    var isClosed: Bool { self == .completed || self == .referredOut }
}
