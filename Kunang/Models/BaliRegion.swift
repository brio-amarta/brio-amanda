//
//  BaliRegion.swift
//  Kunang
//
//  The community only books in-person sessions for people in Bali.
//  Everyone else is referred to a service closer to home.
//

import Foundation

enum BaliRegion {
    /// Regencies, cities and well-known areas that count as "in Bali".
    static let keywords: [String] = [
        "bali", "denpasar", "badung", "gianyar", "tabanan", "buleleng",
        "klungkung", "karangasem", "bangli", "jembrana",
        "kuta", "legian", "seminyak", "canggu", "kerobokan", "jimbaran",
        "nusa dua", "uluwatu", "pecatu", "sanur", "ubud", "tegallalang",
        "singaraja", "lovina", "amed", "candidasa", "negara", "semarapura",
        "mengwi", "sukawati", "payangan", "tampaksiring", "bedugul",
        "nusa penida", "nusa lembongan", "gilimanuk", "kintamani", "seririt"
    ]

    /// Rough fallback suggestions for the biggest non-Bali origins.
    private static let referralHints: [String: String] = [
        "jakarta": "Jakarta has a large public mental-health network — RSJ Dr. Soeharto Heerdjan and most Puskesmas run counselling clinics.",
        "bandung": "Bandung has campus and hospital counselling services, including RSJ Provinsi Jawa Barat in Cisarua.",
        "surabaya": "Surabaya has RSJ Menur and several university-run counselling clinics.",
        "yogyakarta": "Yogyakarta has RSJ Grhasia and a number of student counselling centres.",
        "semarang": "Semarang has RSJD Dr. Amino Gondohutomo and community Puskesmas counselling.",
        "medan": "Medan has RSJ Prof. Dr. M. Ildrem and hospital-based psychology services.",
        "makassar": "Makassar has RSKD Dadi and university counselling clinics.",
        "malang": "Malang has RSJ Lawang (Dr. Radjiman Wediodiningrat) nearby.",
        "lombok": "Lombok has RSJ Mutiara Sukma in Mataram.",
        "mataram": "Mataram has RSJ Mutiara Sukma."
    ]

    static func isInBali(_ location: String) -> Bool {
        let needle = location.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        guard !needle.isEmpty else { return false }
        return keywords.contains { needle.contains($0) }
    }

    /// A short hint the chat drafter can lean on when writing a soft referral.
    static func referralHint(for location: String) -> String? {
        let needle = location.lowercased()
        return referralHints.first { needle.contains($0.key) }?.value
    }
}
