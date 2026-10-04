import Foundation
import VaultyCore

enum ShortFormTests {
    static let tests: [SelfTestCase] = [
        ("short-form policy covers requested platforms", testShortFormPolicyCoversRequestedPlatforms),
        ("short-form blocker covers requested hosts", testShortFormBlockerCoversRequestedHosts),
        ("short-form blocker is independent from YouTube blocker", testShortFormBlockerIsIndependentFromYouTubeBlocker),
        ("default YouTube channel allowlist", testDefaultYouTubeChannelAllowlist)
    ]
}

private func testShortFormPolicyCoversRequestedPlatforms() throws {
    let samples: [(String, ShortFormPlatform)] = [
        ("https://www.tiktok.com/@creator/video/123", .tiktok),
        ("https://www.instagram.com/reel/123/", .instagram),
        ("https://www.youtube.com/shorts/abc123", .youtube),
        ("https://www.facebook.com/reels/videos/123", .facebook),
        ("https://fb.watch/abc123/", .facebook)
    ]

    for (url, platform) in samples {
        let decision = ShortFormPolicy.decision(for: url)
        try checkEqual(decision.state, .blocked, "short-form URL was not blocked: \(url)")
        try checkEqual(decision.platform, platform, "wrong short-form platform for \(url)")
        try check(ShortFormPolicy.isShortFormURL(url), "short-form URL was not recognized: \(url)")
    }

    try checkEqual(
        ShortFormPolicy.decision(for: "https://www.youtube.com/watch?v=abc").state,
        .notShortForm,
        "regular YouTube watch URL was classified as Shorts"
    )
    try checkEqual(
        ShortFormPolicy.decision(for: "https://www.instagram.com/p/123/").state,
        .notShortForm,
        "regular Instagram post URL was classified as a Reel"
    )
    try checkEqual(
        ShortFormPolicy.decision(for: "https://www.facebook.com/groups/work").state,
        .notShortForm,
        "regular Facebook URL was classified as a Reel"
    )
    try checkEqual(
        ShortFormPolicy.decision(for: "https://example.com/reel/123").state,
        .outside,
        "unrelated host was treated as short-form"
    )
}
private func testShortFormBlockerCoversRequestedHosts() throws {
    try withFixture { hostsFile in
        let blocker = try ShortFormBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.isBlocked()), "fresh short-form vault is incorrectly blocked")
        try check(try blocker.block(), "short-form block did not change the hosts file")
        try check(try blocker.isBlocked(), "short-form vault did not report complete coverage")

        let contents = try read(hostsFile)
        try check(contents.contains(ShortFormBlocker.beginMarker), "short-form begin marker is missing")
        try check(contents.contains(ShortFormBlocker.endMarker), "short-form end marker is missing")
        for platform in ShortFormPlatform.allCases {
            for domain in ShortFormPolicy.hosts(for: platform) {
                try check(
                    contents.contains("0.0.0.0 \(domain)"),
                    "missing \(platform.displayName) host mapping: \(domain)"
                )
            }
        }

        try check(try blocker.unblock(), "short-form vault did not unblock")
        try checkEqual(try read(hostsFile), defaultFixtureContents, "short-form unblock damaged existing hosts content")
    }
}
private func testShortFormBlockerIsIndependentFromYouTubeBlocker() throws {
    try withFixture { hostsFile in
        let youtubeOnly = try FocusVaultBlocker(
            hostsFileURL: hostsFile,
            domains: FocusVaultBlocker.youtubeDomains
        )
        let shortForm = try ShortFormBlocker(hostsFileURL: hostsFile)

        try check(try youtubeOnly.block(), "YouTube-only fixture block failed")
        try check(try youtubeOnly.isBlocked(), "YouTube blocker did not report its own section")
        try check(!(try shortForm.isBlocked()), "YouTube block was mistaken for short-form coverage")

        try check(try shortForm.block(), "separate short-form block did not change the hosts file")
        try check(try shortForm.isBlocked(), "short-form block is incomplete")
        try check(try youtubeOnly.isBlocked(), "short-form block damaged the YouTube blocker")

        try check(try shortForm.unblock(), "short-form block did not unblock independently")
        try check(!(try shortForm.isBlocked()), "short-form block remained after independent unblock")
        try check(try youtubeOnly.isBlocked(), "short-form unblock damaged the YouTube blocker")

        try check(try youtubeOnly.unblock(), "YouTube block did not unblock independently")
        try checkEqual(try read(hostsFile), defaultFixtureContents, "independent block cycles damaged existing hosts content")
    }
}
private func testDefaultYouTubeChannelAllowlist() throws {
    try checkEqual(YouTubeChannelDefaults.channels.count, 2, "unexpected default YouTube channel count")
    try checkEqual(YouTubeChannelDefaults.channels[0].displayHandle, "@AlexHormozi", "Alex Hormozi default handle changed")
    try checkEqual(YouTubeChannelDefaults.channels[0].channelID, "UCUyDOdBWhC1MCxEjC46d-zw", "Alex Hormozi default ID changed")
    try checkEqual(YouTubeChannelDefaults.channels[1].displayHandle, "@MoreMozi", "MoreMozi default handle changed")
    try checkEqual(YouTubeChannelDefaults.channels[1].channelID, "UCrvchO1h6lWZAuGaa1LqX9Q", "MoreMozi default ID changed")
}
