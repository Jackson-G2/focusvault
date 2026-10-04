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
        guard let contents = try blocker.managedContents() else { return false }
        return missingDomains(in: contents).isEmpty
    }

    public func missingDomains() throws -> [String] {
        missingDomains(in: try blocker.managedContents() ?? "")
    }

    private func missingDomains(in contents: String) -> [String] {
        HostsBlockCoverage.missingDomains(in: contents, required: domains)
    }
}

public typealias VaultyShortFormBlocker = ShortFormBlocker
