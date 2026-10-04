import Foundation

/// Public facade for the original YouTube vault. Policy parsing, normalization,
/// and file replacement are independent internal modules; all public aliases,
/// marker families, and entry points remain source compatible.
public struct FocusVaultBlocker {
    public static let appName = "Vaulty"
    public static let version = "0.13.0"
    public static let youtubeDomains = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com"
    ]
    public static let shortFormDomains = ShortFormPolicy.hostsFileDomains
    public static let defaultDomains = youtubeDomains
    public static let beginMarker = "# BEGIN VAULTY MANAGED BLOCK"
    public static let endMarker = "# END VAULTY MANAGED BLOCK"
    public static let kivletBeginMarker = "# BEGIN KIVLET MANAGED BLOCK"
    public static let kivletEndMarker = "# END KIVLET MANAGED BLOCK"
    public static let focusVaultBeginMarker = "# BEGIN FOCUSVAULT MANAGED BLOCK"
    public static let focusVaultEndMarker = "# END FOCUSVAULT MANAGED BLOCK"
    public static let legacyBeginMarker = "# BEGIN FROSTWALL MANAGED BLOCK"
    public static let legacyEndMarker = "# END FROSTWALL MANAGED BLOCK"
    public static let defaultHostsFileURL = URL(fileURLWithPath: "/etc/hosts")

    public let hostsFileURL: URL
    public let domains: [String]
    private let markers: ManagedHostsMarkers
    private var store: HostsFileStore { HostsFileStore(url: hostsFileURL) }

    public init(
        hostsFileURL: URL = FocusVaultBlocker.defaultHostsFileURL,
        domains: [String] = FocusVaultBlocker.defaultDomains
    ) throws {
        self.hostsFileURL = hostsFileURL
        self.domains = try HostnameNormalizer.uniqueDomains(domains)
        markers = .youtube
    }

    /// Independent features share the document and I/O engine, not ownership of
    /// the YouTube section. Kept internal rather than exposing new public API.
    init(
        hostsFileURL: URL, domains: [String], managedBeginMarker: String,
        managedEndMarker: String, managedPrefixEndingMetadata: String
    ) throws {
        self.hostsFileURL = hostsFileURL
        self.domains = try HostnameNormalizer.uniqueDomains(domains)
        markers = ManagedHostsMarkers(
            scope: managedBeginMarker == ShortFormBlocker.beginMarker ? "short-form" : managedBeginMarker,
            begin: managedBeginMarker, end: managedEndMarker, metadataPrefix: managedPrefixEndingMetadata
        )
    }

    public var managedBlock: String { managedBlock(using: "\n") }

    public func managedBlock(using lineEnding: String) -> String {
        renderBlock(using: lineEnding, prefixEnding: .unknown)
    }

    @discardableResult
    public func block() throws -> Bool {
        try store.withExclusiveAccess { lockedStore in
            let document = try readDocument(from: lockedStore)
            let updated: String
            if let section = document.section(for: markers.scope) {
                let ending = section.prefixEnding == .unknown
                    ? HostsPrefixEnding.of(String(document.contents[..<section.range.lowerBound]))
                    : section.prefixEnding
                // Replace IN PLACE. Moving independent sections on each enforcement
                // cycle caused needless file writes and restoration-metadata drift.
                updated = document.replacing(section, with: renderBlock(using: document.lineEnding, prefixEnding: ending) + document.lineEnding)
            } else {
                let ending = HostsPrefixEnding.of(document.contents)
                let separator = document.contents.isEmpty || HostsPrefixEnding.hasLineEnding(document.contents) ? "" : document.lineEnding
                updated = document.contents + separator + renderBlock(using: document.lineEnding, prefixEnding: ending) + document.lineEnding
            }
            return try saveIfChanged(updated, original: document.contents, store: lockedStore)
        }
    }

    @discardableResult
    public func unblock() throws -> Bool {
        try store.withExclusiveAccess { lockedStore in
            let document = try readDocument(from: lockedStore)
            guard let section = document.section(for: markers.scope) else { return false }
            return try saveIfChanged(document.removing(section), original: document.contents, store: lockedStore)
        }
    }

    public func isBlocked() throws -> Bool {
        try readDocument().section(for: markers.scope) != nil
    }

    /// Keep the legacy marker-presence API, but use effective coverage when
    /// promising that protection was applied successfully.
    public func isFullyBlocked() throws -> Bool {
        guard let contents = try managedContents() else { return false }
        return HostsBlockCoverage.missingDomains(in: contents, required: domains).isEmpty
    }

    public func managedContents() throws -> String? {
        let document = try readDocument()
        guard let section = document.section(for: markers.scope) else { return nil }
        return String(document.contents[section.range])
    }

    public func readContents() throws -> String { try store.read() }

    public func removingManagedBlock(from contents: String) throws -> String {
        let document = try ManagedHostsDocument(contents, path: hostsFileURL.path, additionalMarkers: markers)
        guard let section = document.section(for: markers.scope) else { return contents }
        return document.removing(section)
    }

    public static func normalizeDomain(_ value: String) throws -> String {
        try HostnameNormalizer.normalize(value)
    }

    private func readDocument(from suppliedStore: HostsFileStore? = nil) throws -> ManagedHostsDocument {
        try ManagedHostsDocument((suppliedStore ?? store).read(), path: hostsFileURL.path, additionalMarkers: markers)
    }

    private func renderBlock(using lineEnding: String, prefixEnding: HostsPrefixEnding) -> String {
        let lines = [markers.begin, "# This section is managed by Vaulty. Vault in and get work done.",
                     markers.metadataPrefix + prefixEnding.rawValue]
            + domains.map { "0.0.0.0 \($0)" } + [markers.end]
        return lines.joined(separator: lineEnding)
    }

    private func saveIfChanged(_ updated: String, original: String, store: HostsFileStore) throws -> Bool {
        guard !updated.utf8.elementsEqual(original.utf8) else { return false }
        try store.write(updated)
        return true
    }
}

public typealias VaultyBlocker = FocusVaultBlocker
