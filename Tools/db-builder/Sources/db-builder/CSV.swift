import Foundation

/// A minimal RFC 4180 CSV reader.
///
/// Hand-written rather than pulled in as a dependency: the USDA files are the
/// only CSV this project will ever read, and a parser small enough to audit in
/// one sitting is worth more here than a general-purpose one.
///
/// Handles the two things the USDA files actually do — quoted fields containing
/// commas, and doubled quotes as an escaped quote.
struct CSVReader {

    /// Streams rows as arrays of fields, skipping the header.
    ///
    /// Reads the whole file into memory: the largest of these is ~38 MB, this
    /// runs on a developer Mac, and streaming would add real complexity for no
    /// benefit at that size.
    static func rows(at url: URL) throws -> [[String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            // Ignore the blank row a trailing newline produces.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if character == "\"" {
                    // A doubled quote inside quotes is a literal quote.
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",":  endField()
                case "\n": endRow()
                case "\r": break  // handled by the \n that follows
                default:   field.append(character)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }

        return rows.isEmpty ? [] : Array(rows.dropFirst())
    }
}

extension Array where Element == String {
    /// Field at `index`, or empty if the row is short — USDA rows occasionally
    /// omit trailing empty fields.
    func field(_ index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }

    func double(_ index: Int) -> Double? {
        Double(field(index).trimmingCharacters(in: .whitespaces))
    }

    func int(_ index: Int) -> Int? {
        Int(field(index).trimmingCharacters(in: .whitespaces))
    }
}
