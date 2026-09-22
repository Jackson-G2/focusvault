import Foundation

/// System-wide short-form vault backed by its own reversible Vaulty
/// hosts-file section. Unlike browser policy, a hosts file has no path
/// awareness, so the native mode deliberately blocks each supported platform
/// host in full. Its marker is independent from the YouTube blocker marker.
public struct ShortFormBlocker {
    public static let defaultDomains = ShortFormPolicy.hostsFileDomains
    public static let beginMarker = "# BEGIN VAULTY SHORT-FORM MANAGED BLOCK"
    public static let endMarker = "# END VAULTY SHORT-FORM MANAGED BLOCK"
    private static let prefixEndingMetadata = "# Vaulty short-form original prefix ending: "

    public let hostsFileURL: URL
    public let domains: [String]

    private let blocker: FocusVaultBlocker

    public init(
        hostsFileURL: URL = FocusVaultBlocker.defaultHostsFileURL,
        domains: [String] = ShortFormBlocker.defaultDomains
    ) throws {
        let blocker = try FocusVaultBlocker(
            hostsFileURL: hostsFileURL,
            domains: domains,
            managedBeginMarker: Self.beginMarker,
            managedEndMarker: Self.endMarker,
            managedPrefixEndingMetadata: Self.prefixEndingMetadata
        )
        self.blocker = blocker
        self.hostsFileURL = hostsFileURL
        self.domains = blocker.domains
    }

    public var managedBlock: String {
        blocker.managedBlock
    }

    @discardableResult
    public func block() throws -> Bool {
        try blocker.block()
    }

    @discardableResult
    public func unblock() throws -> Bool {
        try blocker.unblock()
    }

    /// A managed marker alone is not enough for this feature to report On. The
    /// status also verifies every required host mapping in this feature's own
    /// section, so the independent YouTube blocker cannot be mistaken for
    /// short-form coverage.
    public func isBlocked() throws -> Bool {
        guard try blocker.isBlocked() else { return false }
        return try missingDomains().isEmpty
    }

    public func missingDomains() throws -> [String] {
        let contents = try blocker.managedContents() ?? ""
        return domains.filter { domain in
            !Self.hasHostMapping(for: domain, in: contents)
        }
    }

    private static func hasHostMapping(for domain: String, in contents: String) -> Bool {
        contents.split(whereSeparator: \.isNewline).contains { rawLine in
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            return fields.count >= 2 && fields[0] == "0.0.0.0" && fields[1] == domain
        }
    }
}

public typealias VaultyShortFormBlocker = ShortFormBlocker
