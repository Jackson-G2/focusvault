import Foundation

public enum HostBlockerError: Error, LocalizedError, Equatable {
    case emptyDomain
    case malformedManagedBlock(path: String)
    case unableToRead(path: String, reason: String)
    case unableToWrite(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .emptyDomain:
            return "At least one non-empty domain is required."
        case let .malformedManagedBlock(path):
            return "The managed Frostwall section in \(path) is malformed; refusing to edit the file."
        case let .unableToRead(path, reason):
            return "Could not read \(path): \(reason)"
        case let .unableToWrite(path, reason):
            return "Could not write \(path): \(reason). If this is /etc/hosts, rerun the command with sudo."
        }
    }
}

public struct HostBlocker {
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

    public static let beginMarker = "# BEGIN FROSTWALL MANAGED BLOCK"
    public static let endMarker = "# END FROSTWALL MANAGED BLOCK"
    public static let defaultHostsFileURL = URL(fileURLWithPath: "/etc/hosts")

    public let hostsFileURL: URL
    public let domains: [String]

    public init(
        hostsFileURL: URL = HostBlocker.defaultHostsFileURL,
        domains: [String] = HostBlocker.defaultDomains
    ) throws {
        let normalized = try domains.map(Self.normalizeDomain)
        guard !normalized.isEmpty else {
            throw HostBlockerError.emptyDomain
        }

        self.hostsFileURL = hostsFileURL
        self.domains = Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
    }

    public var managedBlock: String {
        var lines = [
            Self.beginMarker,
            "# This section is managed by Frostwall. Do not edit inside the markers."
        ]
        lines.append(contentsOf: domains.map { "0.0.0.0 \($0)" })
        lines.append(Self.endMarker)
        return lines.joined(separator: "\n")
    }

    public func block() throws -> Bool {
        let existing = try readContents()
        let withoutManagedBlock = try removingManagedBlock(from: existing)
        var updated = withoutManagedBlock

        if !updated.isEmpty && !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        updated.append(managedBlock)
        updated.append("\n")

        guard updated != existing else {
            return false
        }

        try writeContents(updated, preservingAttributesOf: existing.isEmpty ? nil : hostsFileURL)
        return true
    }

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
        return contents.contains(Self.beginMarker) && contents.contains(Self.endMarker)
    }

    public func readContents() throws -> String {
        guard FileManager.default.fileExists(atPath: hostsFileURL.path) else {
            return ""
        }

        do {
            return try String(contentsOf: hostsFileURL, encoding: .utf8)
        } catch {
            throw HostBlockerError.unableToRead(
                path: hostsFileURL.path,
                reason: error.localizedDescription
            )
        }
    }

    public func removingManagedBlock(from contents: String) throws -> String {
        let beginRange = contents.range(of: Self.beginMarker)
        let endRange = contents.range(of: Self.endMarker)

        guard beginRange == nil && endRange == nil else {
            guard let beginRange, let endRange,
                  beginRange.lowerBound < endRange.lowerBound else {
                throw HostBlockerError.malformedManagedBlock(path: hostsFileURL.path)
            }

            let start = beginRange.lowerBound
            var finish = endRange.upperBound
            if finish < contents.endIndex, contents[finish] == "\n" {
                finish = contents.index(after: finish)
            }

            return String(contents[..<start]) + String(contents[finish...])
        }

        return contents
    }

    public static func normalizeDomain(_ value: String) throws -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: candidate), let host = url.host, candidate.contains("://") {
            candidate = host
        } else {
            candidate = candidate
                .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? candidate
            candidate = candidate
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? candidate
        }

        candidate = candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !candidate.isEmpty,
              !candidate.contains(where: { $0.isWhitespace }),
              !candidate.contains("#") else {
            throw HostBlockerError.emptyDomain
        }

        return candidate
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
            throw HostBlockerError.unableToWrite(
                path: hostsFileURL.path,
                reason: error.localizedDescription
            )
        }

        if !attributesToRestore.isEmpty {
            do {
                try fileManager.setAttributes(attributesToRestore, ofItemAtPath: hostsFileURL.path)
            } catch {
                throw HostBlockerError.unableToWrite(
                    path: hostsFileURL.path,
                    reason: "the file changed but its original permissions could not be restored: \(error.localizedDescription)"
                )
            }
        }
    }
}
