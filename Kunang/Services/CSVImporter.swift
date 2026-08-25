//
//  CSVImporter.swift
//  Kunang
//
//  Parses a CSV/TSV export into draft clients. Column names are matched
//  loosely so owners don't have to rename their spreadsheet headers.
//

import Foundation

struct ImportedRow: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var age: Int
    var location: String
    var phone: String
    var mentalHealthScore: Double
    var notes: String
    /// Every column from the sheet, kept so the triage prompt can see extras.
    var extras: [String: String]

    /// Flattened "Key: value" list handed to the on-device model.
    var promptSummary: String {
        var lines = [
            "Name: \(name)",
            "Age: \(age)",
            "Location: \(location)",
            "Mental health score: \(String(format: "%.1f", mentalHealthScore)) out of 10 (10 = thriving, 0 = severe distress)"
        ]
        if !notes.isEmpty { lines.append("Notes: \(notes)") }
        for (key, value) in extras.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            lines.append("\(key): \(value)")
        }
        return lines.joined(separator: "\n")
    }
}

enum CSVImportError: LocalizedError {
    case emptyFile
    case noNameColumn
    case unreadable

    var errorDescription: String? {
        switch self {
        case .emptyFile: "That file looks empty."
        case .noNameColumn: "Couldn't find a name column. Add a header called \"Name\"."
        case .unreadable: "Couldn't read that file. Export it as CSV and try again."
        }
    }
}

enum CSVImporter {

    // Header aliases, all lowercased.
    private static let nameKeys = ["name", "full name", "client", "client name", "nama"]
    private static let ageKeys = ["age", "usia", "umur"]
    private static let locationKeys = ["location", "city", "region", "domicile", "lokasi", "kota", "address"]
    private static let phoneKeys = ["phone", "phone number", "whatsapp", "wa", "contact", "no hp", "nomor"]
    private static let scoreKeys = ["mental health score", "score", "mh score", "mental score", "wellbeing score", "skor"]
    private static let notesKeys = ["notes", "note", "story", "description", "detail", "catatan", "keterangan"]

    static func parse(fileAt url: URL) throws -> [ImportedRow] {
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw CSVImportError.unreadable }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { throw CSVImportError.unreadable }
        return try parse(text: text)
    }

    static func parse(text: String) throws -> [ImportedRow] {
        let rows = splitRows(text)
        guard rows.count > 1, let header = rows.first else { throw CSVImportError.emptyFile }

        let keys = header.map { $0.trimmingCharacters(in: .whitespaces) }
        let lowered = keys.map { $0.lowercased() }

        guard let nameIndex = index(in: lowered, matching: nameKeys) else {
            throw CSVImportError.noNameColumn
        }
        let ageIndex = index(in: lowered, matching: ageKeys)
        let locationIndex = index(in: lowered, matching: locationKeys)
        let phoneIndex = index(in: lowered, matching: phoneKeys)
        let scoreIndex = index(in: lowered, matching: scoreKeys)
        let notesIndex = index(in: lowered, matching: notesKeys)
        let claimed = Set([nameIndex, ageIndex, locationIndex, phoneIndex, scoreIndex, notesIndex].compactMap { $0 })

        var result: [ImportedRow] = []
        for row in rows.dropFirst() {
            func field(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let name = field(nameIndex)
            guard !name.isEmpty else { continue }

            var extras: [String: String] = [:]
            for (offset, key) in keys.enumerated() where !claimed.contains(offset) {
                let value = field(offset)
                if !value.isEmpty { extras[key] = value }
            }

            result.append(
                ImportedRow(
                    name: name,
                    age: Int(field(ageIndex).filter(\.isNumber)) ?? 0,
                    location: field(locationIndex),
                    phone: field(phoneIndex),
                    mentalHealthScore: parseScore(field(scoreIndex)),
                    notes: field(notesIndex),
                    extras: extras
                )
            )
        }

        guard !result.isEmpty else { throw CSVImportError.emptyFile }
        return result
    }

    // MARK: - Helpers

    private static func parseScore(_ raw: String) -> Double {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(cleaned) ?? 0
    }

    private static func index(in headers: [String], matching aliases: [String]) -> Int? {
        if let exact = headers.firstIndex(where: { aliases.contains($0) }) { return exact }
        return headers.firstIndex { header in
            aliases.contains { header.contains($0) }
        }
    }

    /// Splits a CSV/TSV document, honouring quoted fields and embedded newlines.
    private static func splitRows(_ text: String) -> [[String]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let separator: Character = normalized.contains("\t") && !normalized.contains(",") ? "\t" : ","

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var iterator = normalized.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil

            if insideQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else {
                            insideQuotes = false
                            pending = next
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                insideQuotes = true
            case separator:
                row.append(field)
                field = ""
            case "\n":
                row.append(field)
                field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    rows.append(row)
                }
                row = []
            default:
                field.append(character)
            }
        }

        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            rows.append(row)
        }
        return rows
    }
}
