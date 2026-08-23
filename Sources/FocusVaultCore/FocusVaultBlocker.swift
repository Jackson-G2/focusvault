import Foundation

public enum FocusVaultError: Error, LocalizedError, Equatable {
    case emptyDomain
    case invalidDomain(String)
    case malformedManagedBlock(path: String)
    case unableToRead(path: String, reason: String)
    case unableToWrite(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .emptyDomain:
            return "At least one non-empty hostname is required."
        case let .invalidDomain(domain):
            return "Invalid hostname: \(domain). Use a hostname such as youtube.com, not a wildcard or IP address."
        case let .malformedManagedBlock(path):
            return "The managed FocusVault section in \(path) is malformed or duplicated; refusing to edit the file."
        case let .unableToRead(path, reason):
            return "Could not read \(path): \(reason)"
        case let .unableToWrite(path, reason):
            return "Could not write \(path): \(reason) If this is /etc/hosts, rerun the command with sudo."
        }
    }
}

public struct FocusVaultBlocker {
    public static let appName = "FocusVault"
    public static let version = "0.2.0"

    public static let defaultDomains = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com"
    ]

    public static let beginMarker = "# BEGIN FOCUSVAULT MANAGED BLOCK"
    public static let endMarker = "# END FOCUSVAULT MANAGED BLOCK"
    public static let legacyBeginMarker = "# BEGIN FROSTWALL MANAGED BLOCK"
    public static let legacyEndMarker = "# END FROSTWALL MANAGED BLOCK"
    public static let defaultHostsFileURL = URL(fileURLWithPath: "/etc/hosts")

    public let hostsFileURL: URL
    public let domains: [String]

    private struct MarkerSet {
        let begin: String
        let end: String
    }

    private struct MarkerLine {
        let setIndex: Int
        let isBegin: Bool
        let range: Range<String.Index>
    }

    private enum PrefixEnding: String {
        case empty
        case newline
        case none
        case unknown
    }

    private struct ManagedSection {
        let range: Range<String.Index>
        let prefixEnding: PrefixEnding
    }

    private static let prefixEndingMetadata = "# FocusVault original prefix ending: "

    private static let markerSets = [
        MarkerSet(begin: beginMarker, end: endMarker),
        MarkerSet(begin: legacyBeginMarker, end: legacyEndMarker)
    ]

    public init(
        hostsFileURL: URL = FocusVaultBlocker.defaultHostsFileURL,
        domains: [String] = FocusVaultBlocker.defaultDomains
    ) throws {
        let normalized = try domains.map(Self.normalizeDomain)
        guard !normalized.isEmpty else {
            throw FocusVaultError.emptyDomain
        }

        var unique: [String] = []
        var seen = Set<String>()
        for domain in normalized where seen.insert(domain).inserted {
            unique.append(domain)
        }

        self.hostsFileURL = hostsFileURL
        self.domains = unique
    }

    public var managedBlock: String {
        managedBlock(using: "\n")
    }

    public func managedBlock(using lineEnding: String) -> String {
        managedBlock(using: lineEnding, prefixEnding: .unknown)
    }

    private func managedBlock(using lineEnding: String, prefixEnding: PrefixEnding) -> String {
        var lines = [
            Self.beginMarker,
            "# This section is managed by FocusVault. Vault in and get work done.",
            "\(Self.prefixEndingMetadata)\(prefixEnding.rawValue)"
        ]
        lines.append(contentsOf: domains.map { "0.0.0.0 \($0)" })
        lines.append(Self.endMarker)
        return lines.joined(separator: lineEnding)
    }

    @discardableResult
    public func block() throws -> Bool {
        let existing = try readContents()
        let withoutManagedBlock = try removingManagedBlock(from: existing)
        let lineEnding = existing.contains("\r\n") ? "\r\n" : "\n"
        let prefixEnding = Self.prefixEnding(for: withoutManagedBlock)
        var updated = withoutManagedBlock

        if !updated.isEmpty && !Self.hasLineEnding(updated) {
            updated.append(lineEnding)
        }
        updated.append(managedBlock(using: lineEnding, prefixEnding: prefixEnding))
        updated.append(lineEnding)

        guard updated != existing else {
            return false
        }

        try writeContents(updated, preservingAttributesOf: hostsFileURL)
        return true
    }

    @discardableResult
    public func unblock() throws -> Bool {
        let existing = try readContents()
        let updated = try removingManagedBlock(from: existing)

        guard updated != existing else {
            return false
        }

        try writeContents(updated, preservingAttributesOf: hostsFileURL)
        return true
    }

    public func isBlocked() throws -> Bool {
        let contents = try readContents()
        return try managedSection(in: contents) != nil
    }

    public func readContents() throws -> String {
        guard FileManager.default.fileExists(atPath: hostsFileURL.path) else {
            return ""
        }

        do {
            return try String(contentsOf: hostsFileURL, encoding: .utf8)
        } catch {
            throw FocusVaultError.unableToRead(
                path: hostsFileURL.path,
                reason: error.localizedDescription
            )
        }
    }

    public func removingManagedBlock(from contents: String) throws -> String {
        guard let section = try managedSection(in: contents) else {
            return contents
        }

        var prefix = String(contents[..<section.range.lowerBound])
        if section.prefixEnding == .none {
            if prefix.hasSuffix("\r\n") {
                prefix.removeLast()
                prefix.removeLast()
            } else if prefix.hasSuffix("\n") {
                prefix.removeLast()
            }
        }

        return prefix + String(contents[section.range.upperBound...])
    }

    public static func normalizeDomain(_ value: String) throws -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            throw FocusVaultError.emptyDomain
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

            if candidate.contains(":") {
                throw FocusVaultError.invalidDomain(value)
            }
        }

        candidate = candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !candidate.isEmpty,
              candidate.count <= 253,
              !candidate.contains(where: { $0.isWhitespace }),
              !candidate.contains(where: { $0.isASCII && !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "-" }),
              candidate.unicodeScalars.allSatisfy({ $0.isASCII }),
              !candidate.contains("#"),
              !candidate.contains("*") else {
            throw FocusVaultError.invalidDomain(value)
        }

        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else {
            throw FocusVaultError.invalidDomain(value)
        }

        if labels.count == 4,
           labels.allSatisfy({ Int($0) != nil }),
           labels.allSatisfy({ (0...255).contains(Int($0) ?? -1) }) {
            throw FocusVaultError.invalidDomain(value)
        }

        for label in labels {
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-",
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                throw FocusVaultError.invalidDomain(value)
            }
        }

        return candidate
    }

    private func managedSection(in contents: String) throws -> ManagedSection? {
        var matches: [MarkerLine] = []

        for (setIndex, markerSet) in Self.markerSets.enumerated() {
            matches.append(contentsOf: markerLines(for: markerSet.begin, setIndex: setIndex, isBegin: true, in: contents))
            matches.append(contentsOf: markerLines(for: markerSet.end, setIndex: setIndex, isBegin: false, in: contents))
        }

        guard !matches.isEmpty else {
            return nil
        }

        guard matches.count == 2,
              let begin = matches.first(where: { $0.isBegin }),
              let end = matches.first(where: { !$0.isBegin }),
              begin.setIndex == end.setIndex,
              begin.range.lowerBound < end.range.lowerBound else {
            throw FocusVaultError.malformedManagedBlock(path: hostsFileURL.path)
        }

        let interior = String(contents[begin.range.upperBound..<end.range.lowerBound])
        let normalizedInterior = interior
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let metadataValue = normalizedInterior
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(Self.prefixEndingMetadata) }
            .map { String($0.dropFirst(Self.prefixEndingMetadata.count)) }
        let prefixEnding = PrefixEnding(rawValue: metadataValue ?? "") ?? .unknown

        return ManagedSection(
            range: begin.range.lowerBound..<end.range.upperBound,
            prefixEnding: prefixEnding
        )
    }

    private static func prefixEnding(for contents: String) -> PrefixEnding {
        if contents.isEmpty {
            return .empty
        }
        return hasLineEnding(contents) ? .newline : .none
    }

    private static func hasLineEnding(_ contents: String) -> Bool {
        contents.hasSuffix("\n") || contents.hasSuffix("\r\n")
    }

    private func markerLines(
        for marker: String,
        setIndex: Int,
        isBegin: Bool,
        in contents: String
    ) -> [MarkerLine] {
        var matches: [MarkerLine] = []
        var lineStart = contents.startIndex
        var cursor = lineStart

        while cursor < contents.endIndex {
            let character = contents[cursor]
            let isLineBreak = character == "\n" || character == "\r" || character == "\r\n"
            guard isLineBreak else {
                cursor = contents.index(after: cursor)
                continue
            }

            if String(contents[lineStart..<cursor]) == marker {
                let rangeEnd = contents.index(after: cursor)
                matches.append(
                    MarkerLine(
                        setIndex: setIndex,
                        isBegin: isBegin,
                        range: lineStart..<rangeEnd
                    )
                )
            }

            lineStart = contents.index(after: cursor)
            cursor = lineStart
        }

        if lineStart < contents.endIndex,
           String(contents[lineStart..<contents.endIndex]) == marker {
            matches.append(
                MarkerLine(
                    setIndex: setIndex,
                    isBegin: isBegin,
                    range: lineStart..<contents.endIndex
                )
            )
        }

        return matches
    }

    private func writeContents(_ contents: String, preservingAttributesOf sourceURL: URL?) throws {
        let fileManager = FileManager.default
        var attributesToRestore: [FileAttributeKey: Any] = [:]

        if let sourceURL,
           fileManager.fileExists(atPath: sourceURL.path),
           let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path) {
            for key in [
                FileAttributeKey.posixPermissions,
                FileAttributeKey.ownerAccountID,
                FileAttributeKey.groupOwnerAccountID
            ] {
                if let value = attributes[key] {
                    attributesToRestore[key] = value
                }
            }
        }

        do {
            try Data(contents.utf8).write(to: hostsFileURL, options: .atomic)
        } catch {
            throw FocusVaultError.unableToWrite(
                path: hostsFileURL.path,
                reason: error.localizedDescription
            )
        }

        if !attributesToRestore.isEmpty {
            do {
                try fileManager.setAttributes(attributesToRestore, ofItemAtPath: hostsFileURL.path)
            } catch {
                throw FocusVaultError.unableToWrite(
                    path: hostsFileURL.path,
                    reason: "the file changed but its original permissions could not be restored: \(error.localizedDescription)"
                )
            }
        }
    }
}
