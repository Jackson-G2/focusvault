import Foundation

/// Input normalization only; no filesystem or managed-section responsibilities.
enum HostnameNormalizer {
    static func normalize(_ value: String) throws -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { throw FocusVaultError.emptyDomain }
        // Reject embedded controls before URL parsing can silently remove them.
        guard !candidate.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FocusVaultError.invalidDomain(value)
        }

        if candidate.contains("://") {
            guard let url = URL(string: candidate), let host = url.host else {
                throw FocusVaultError.invalidDomain(value)
            }
            candidate = host
        } else {
            if let slash = candidate.firstIndex(of: "/") {
                candidate = String(candidate[..<slash])
            }
            guard !candidate.contains(":") else { throw FocusVaultError.invalidDomain(value) }
        }

        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let bytes = candidate.utf8
        guard !bytes.isEmpty, bytes.count <= 253,
              bytes.allSatisfy({ isLetterOrNumber($0) || $0 == 46 || $0 == 45 }) else {
            throw FocusVaultError.invalidDomain(value)
        }
        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 4,
           labels.allSatisfy({ Int($0).map { (0...255).contains($0) } == true }) {
            throw FocusVaultError.invalidDomain(value)
        }
        for label in labels {
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.first != "-", label.last != "-" else {
                throw FocusVaultError.invalidDomain(value)
            }
        }
        return candidate
    }

    static func uniqueDomains(_ values: [String]) throws -> [String] {
        guard !values.isEmpty else { throw FocusVaultError.emptyDomain }
        var seen = Set<String>()
        var domains: [String] = []
        domains.reserveCapacity(values.count)
        for value in values {
            let domain = try normalize(value)
            if seen.insert(domain).inserted { domains.append(domain) }
        }
        return domains
    }

    private static func isLetterOrNumber(_ byte: UInt8) -> Bool {
        (97...122).contains(byte) || (48...57).contains(byte)
    }
}
