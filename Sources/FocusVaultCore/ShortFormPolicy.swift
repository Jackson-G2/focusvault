import Foundation

/// The short-form surfaces Vaulty protects. TikTok is treated as short-form by
/// design; Instagram and Facebook are scoped to their Reels/Stories routes,
/// while YouTube is scoped to Shorts in browser policy.
public enum ShortFormPlatform: String, CaseIterable, Codable, Equatable {
    case tiktok
    case instagram
    case youtube
    case facebook

    public var displayName: String {
        switch self {
        case .tiktok:
            return "TikTok"
        case .instagram:
            return "Instagram Reels"
        case .youtube:
            return "YouTube Shorts"
        case .facebook:
            return "Facebook Reels"
        }
    }
}

public enum ShortFormDecisionState: String, Codable, Equatable {
    case outside
    case notShortForm
    case blocked
}

public struct ShortFormURLDecision: Codable, Equatable {
    public let state: ShortFormDecisionState
    public let platform: ShortFormPlatform?
    public let reason: String

    public init(
        state: ShortFormDecisionState,
        platform: ShortFormPlatform? = nil,
        reason: String
    ) {
        self.state = state
        self.platform = platform
        self.reason = reason
    }

    public var isBlocked: Bool {
        state == .blocked
    }
}

/// URL and hosts-file policy for short-form content.
///
/// A browser can make path-level decisions. The native hosts-file vault cannot
/// see paths, so enabling the native vault blocks the supported platform hosts
/// completely. This conservative fallback guarantees that a short-form route
/// cannot bypass the protection in another browser.
public enum ShortFormPolicy {
    public static let tiktokHosts = [
        "tiktok.com",
        "www.tiktok.com",
        "m.tiktok.com",
        "vm.tiktok.com",
        "vt.tiktok.com"
    ]

    public static let instagramHosts = [
        "instagram.com",
        "www.instagram.com",
        "m.instagram.com"
    ]

    public static let youtubeHosts = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com"
    ]

    public static let facebookHosts = [
        "facebook.com",
        "www.facebook.com",
        "m.facebook.com",
        "web.facebook.com",
        "fb.watch"
    ]

    /// Every hostname written by the native, system-wide short-form vault.
    public static let hostsFileDomains: [String] = unique(
        tiktokHosts + instagramHosts + youtubeHosts + facebookHosts
    )

    /// The short-form hosts that can remain blocked during a timed YouTube
    /// lease. YouTube Shorts continue to be enforced by the browser companion.
    public static let nonYouTubeHosts: [String] = unique(
        tiktokHosts + instagramHosts + facebookHosts
    )

    public static let defaultDomains = hostsFileDomains
    public static let blockedHosts = hostsFileDomains

    /// The hostnames grouped by platform for validation and UI diagnostics.
    public static func hosts(for platform: ShortFormPlatform) -> [String] {
        switch platform {
        case .tiktok:
            return tiktokHosts
        case .instagram:
            return instagramHosts
        case .youtube:
            return youtubeHosts
        case .facebook:
            return facebookHosts
        }
    }

    /// Returns the short-form platform represented by a URL hostname.
    public static func platform(for rawURL: String) -> ShortFormPlatform? {
        guard let url = URL(string: rawURL),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return platform(forHost: host)
    }

    /// Returns the short-form platform represented by a host, including
    /// platform-owned subdomains that are not listed individually.
    public static func platform(forHost rawHost: String) -> ShortFormPlatform? {
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return nil }

        if matches(host: host, anyOf: tiktokHosts) {
            return .tiktok
        }
        if matches(host: host, anyOf: instagramHosts) {
            return .instagram
        }
        if matches(host: host, anyOf: youtubeHosts) {
            return .youtube
        }
        if matches(host: host, anyOf: facebookHosts) {
            return .facebook
        }
        return nil
    }

    /// Evaluates a URL using browser-level path rules.
    public static func decision(for rawURL: String) -> ShortFormURLDecision {
        guard let url = URL(string: rawURL), let host = url.host?.lowercased() else {
            return ShortFormURLDecision(
                state: .blocked,
                reason: "invalid-url"
            )
        }

        guard let platform = platform(forHost: host) else {
            return ShortFormURLDecision(
                state: .outside,
                reason: "outside-supported-platforms"
            )
        }

        let path = normalizedPath(url.path)
        switch platform {
        case .tiktok:
            return ShortFormURLDecision(
                state: .blocked,
                platform: platform,
                reason: "tiktok-is-short-form-by-design"
            )
        case .instagram:
            return routeDecision(
                platform: platform,
                path: path,
                segments: ["reel", "reels", "stories"]
            )
        case .youtube:
            return routeDecision(
                platform: platform,
                path: path,
                segments: ["shorts"]
            )
        case .facebook:
            if matches(host: host, anyOf: ["fb.watch"]) {
                return ShortFormURLDecision(
                    state: .blocked,
                    platform: platform,
                    reason: "facebook-short-link"
                )
            }
            return routeDecision(
                platform: platform,
                path: path,
                segments: ["reel", "reels"]
            )
        }
    }

    public static func isShortFormURL(_ rawURL: String) -> Bool {
        decision(for: rawURL).isBlocked
    }

    public static func isBlocked(_ rawURL: String) -> Bool {
        decision(for: rawURL).isBlocked
    }

    private static func routeDecision(
        platform: ShortFormPlatform,
        path: String,
        segments: Set<String>
    ) -> ShortFormURLDecision {
        let firstSegment = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)?.lowercased()

        guard let firstSegment, segments.contains(firstSegment) else {
            return ShortFormURLDecision(
                state: .notShortForm,
                platform: platform,
                reason: "not-a-known-short-form-route"
            )
        }

        return ShortFormURLDecision(
            state: .blocked,
            platform: platform,
            reason: "known-short-form-route"
        )
    }

    private static func normalizedPath(_ value: String) -> String {
        let path = value.isEmpty ? "/" : value
        return "/" + path
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private static func matches(host: String, anyOf domains: [String]) -> Bool {
        domains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
