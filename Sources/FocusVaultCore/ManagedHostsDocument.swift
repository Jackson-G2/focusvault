import Foundation

struct ManagedHostsMarkers {
    let scope: String
    let begin: String
    let end: String
    let metadataPrefix: String

    static let youtube = ManagedHostsMarkers(
        scope: "youtube", begin: FocusVaultBlocker.beginMarker, end: FocusVaultBlocker.endMarker,
        metadataPrefix: "# Vaulty original prefix ending: "
    )
    static let shortForm = ManagedHostsMarkers(
        scope: "short-form", begin: ShortFormBlocker.beginMarker, end: ShortFormBlocker.endMarker,
        metadataPrefix: "# Vaulty short-form original prefix ending: "
    )
    static let known = [
        youtube,
        ManagedHostsMarkers(scope: "youtube", begin: FocusVaultBlocker.kivletBeginMarker,
                            end: FocusVaultBlocker.kivletEndMarker, metadataPrefix: "# Kivlet original prefix ending: "),
        ManagedHostsMarkers(scope: "youtube", begin: FocusVaultBlocker.focusVaultBeginMarker,
                            end: FocusVaultBlocker.focusVaultEndMarker, metadataPrefix: "# FocusVault original prefix ending: "),
        ManagedHostsMarkers(scope: "youtube", begin: FocusVaultBlocker.legacyBeginMarker,
                            end: FocusVaultBlocker.legacyEndMarker, metadataPrefix: "# FocusVault original prefix ending: "),
        shortForm
    ]
}

enum HostsPrefixEnding: String {
    case empty, newline, none, unknown

    static func of(_ contents: String) -> HostsPrefixEnding {
        contents.isEmpty ? .empty : (hasLineEnding(contents) ? .newline : .none)
    }

    static func hasLineEnding(_ contents: String) -> Bool {
        contents.utf8.last == 10 || contents.utf8.last == 13
    }
}

struct ManagedHostsSection {
    let markers: ManagedHostsMarkers
    let range: Range<String.Index>
    let interiorStart: String.Index
    let prefixEnding: HostsPrefixEnding
    let metadataRange: Range<String.Index>?
}

/// One UTF-8 pass validates every known section before any edit. Ranges always
/// refer to the original string, preserving Unicode, CRLF and unmanaged bytes.
struct ManagedHostsDocument {
    let contents: String
    let sections: [ManagedHostsSection]
    let lineEnding: String

    init(_ contents: String, path: String, additionalMarkers: ManagedHostsMarkers? = nil) throws {
        self.contents = contents
        var families = ManagedHostsMarkers.known
        if let additionalMarkers, !families.contains(where: { $0.begin == additionalMarkers.begin }) {
            families.append(additionalMarkers)
        }
        let markers = Dictionary(uniqueKeysWithValues: families.enumerated().flatMap { index, family in
            [(family.begin, (index, true)), (family.end, (index, false))]
        })
        let metadataPrefixes = Array(Set(families.map(\.metadataPrefix)))
        let bytes = contents.utf8
        var cursor = bytes.startIndex
        var found: [ManagedHostsSection] = []
        var scopes = Set<String>()
        var open: (family: Int, start: String.Index, interior: String.Index)?
        var prefixEnding = HostsPrefixEnding.unknown
        var metadataRange: Range<String.Index>?
        var sawLF = false
        var sawCR = false
        var sawCRLF = false

        while cursor < bytes.endIndex {
            let start = cursor
            while cursor < bytes.endIndex, bytes[cursor] != 10, bytes[cursor] != 13 {
                bytes.formIndex(after: &cursor)
            }
            let contentEnd = cursor
            if cursor < bytes.endIndex {
                if bytes[cursor] == 13 {
                    sawCR = true
                    bytes.formIndex(after: &cursor)
                    if cursor < bytes.endIndex, bytes[cursor] == 10 {
                        sawCRLF = true
                        bytes.formIndex(after: &cursor)
                    }
                } else {
                    sawLF = true
                    bytes.formIndex(after: &cursor)
                }
            }
            // Only comment lines can be markers or restoration metadata. Avoid
            // materializing every ordinary hosts entry in a large file.
            guard start < contentEnd, bytes[start] == 35 else { continue }
            let line = String(contents[start..<contentEnd])
            if let (familyIndex, isBegin) = markers[line] {
                let family = families[familyIndex]
                if isBegin {
                    guard open == nil, scopes.insert(family.scope).inserted else {
                        throw FocusVaultError.malformedManagedBlock(path: path)
                    }
                    open = (familyIndex, start, cursor)
                    prefixEnding = .unknown
                    metadataRange = nil
                } else {
                    guard let opening = open, opening.family == familyIndex else {
                        throw FocusVaultError.malformedManagedBlock(path: path)
                    }
                    if prefixEnding == .none,
                       !HostsPrefixEnding.hasLineEnding(String(contents[..<opening.start])) {
                        throw FocusVaultError.malformedManagedBlock(path: path)
                    }
                    found.append(ManagedHostsSection(
                        markers: family, range: opening.start..<cursor, interiorStart: opening.interior,
                        prefixEnding: prefixEnding, metadataRange: metadataRange
                    ))
                    open = nil
                }
            } else if open != nil,
                      let prefix = metadataPrefixes.first(where: { line.hasPrefix($0) }) {
                guard metadataRange == nil,
                      let ending = HostsPrefixEnding(rawValue: String(line.dropFirst(prefix.count))) else {
                    throw FocusVaultError.malformedManagedBlock(path: path)
                }
                prefixEnding = ending
                metadataRange = start..<contentEnd
            }
        }
        guard open == nil else { throw FocusVaultError.malformedManagedBlock(path: path) }
        sections = found
        lineEnding = sawCRLF ? "\r\n" : (sawCR && !sawLF ? "\r" : "\n")
    }

    func section(for scope: String) -> ManagedHostsSection? {
        sections.first { $0.markers.scope == scope }
    }

    func replacing(_ section: ManagedHostsSection, with block: String) -> String {
        String(contents[..<section.range.lowerBound]) + block + String(contents[section.range.upperBound...])
    }

    func removing(_ section: ManagedHostsSection) -> String {
        var prefix = String(contents[..<section.range.lowerBound])
        var suffix = String(contents[section.range.upperBound...])
        if section.prefixEnding == .none || section.prefixEnding == .empty,
           let successor = sections.first(where: { $0.range.lowerBound == section.range.upperBound }) {
            // The next independent section inherits ownership of the separator.
            // Removing the first block must not merge its marker into user text.
            let replacement = successor.markers.metadataPrefix + section.prefixEnding.rawValue
            if let metadata = successor.metadataRange {
                suffix = String(contents[section.range.upperBound..<metadata.lowerBound])
                    + replacement + String(contents[metadata.upperBound...])
            } else {
                suffix = String(contents[section.range.upperBound..<successor.interiorStart])
                    + replacement + lineEnding + String(contents[successor.interiorStart...])
            }
        } else if section.prefixEnding == .none,
                  suffix.isEmpty || suffix.utf8.first == 10 || suffix.utf8.first == 13 {
            // A CRLF is a single Swift Character. Remove ONE grapheme, not two.
            if HostsPrefixEnding.hasLineEnding(prefix) { prefix.removeLast() }
        }
        return prefix + suffix
    }
}
