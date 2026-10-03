import Foundation

/// Parse only effective mappings, not commented text or marker presence.
enum HostsBlockCoverage {
    static func missingDomains(in contents: String, required domains: [String]) -> [String] {
        var mapped = Set<String>()
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "0.0.0.0" else { continue }
            for domain in fields.dropFirst() { mapped.insert(domain.lowercased()) }
        }
        return domains.filter { !mapped.contains($0) }
    }
}
