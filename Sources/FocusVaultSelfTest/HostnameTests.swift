import Foundation
import VaultyCore

enum HostnameTests {
    static let tests: [SelfTestCase] = [
        ("domain order and deduplication", testCustomDomainOrderAndDeduplication),
        ("HTTPS normalization", testHTTPSNormalization),
        ("bare path normalization", testBarePathNormalization),
        ("case and dot normalization", testCaseAndDotNormalization),
        ("empty domain rejection", testRejectEmptyDomain),
        ("whitespace domain rejection", testRejectWhitespaceDomain),
        ("wildcard rejection", testRejectWildcard),
        ("comment injection rejection", testRejectCommentInjection),
        ("newline injection rejection", testRejectNewlineInjection),
        ("IPv4 rejection", testRejectIPv4Literal),
        ("IPv6 rejection", testRejectIPv6Literal),
        ("empty label rejection", testRejectEmptyLabel),
        ("hyphen label rejection", testRejectHyphenLabel),
        ("long label rejection", testRejectLongLabel),
        ("long domain rejection", testRejectLongDomain),
        ("Unicode hostname rejection", testRejectUnicodeHostname),
        ("localhost acceptance", testAcceptLocalhost),
        ("punycode acceptance", testAcceptPunycode),
        ("HTTPS port acceptance", testAcceptHTTPSPort),
        ("empty custom list rejection", testEmptyCustomDomainListThrows)
    ]
}

private func testCustomDomainOrderAndDeduplication() throws {
    let blocker = try FocusVaultBlocker(
        domains: ["Example.com", "example.com", "EXAMPLE.org", "example.com"]
    )
    try checkEqual(blocker.domains, ["example.com", "example.org"], "domains were not normalized and deduplicated in order")
}
private func testHTTPSNormalization() throws {
    try checkEqual(
        try FocusVaultBlocker.normalizeDomain("HTTPS://Example.COM:8443/path?q=1"),
        "example.com",
        "HTTPS URL was not normalized"
    )
}
private func testBarePathNormalization() throws {
    try checkEqual(
        try FocusVaultBlocker.normalizeDomain("example.com/watch"),
        "example.com",
        "hostname path was not stripped"
    )
}
private func testCaseAndDotNormalization() throws {
    try checkEqual(
        try FocusVaultBlocker.normalizeDomain("...WWW.Example.COM..."),
        "www.example.com",
        "case and dots were not normalized"
    )
}
private func testRejectEmptyDomain() throws {
    try expectFocusVaultError({ _ = try FocusVaultBlocker.normalizeDomain("") }, "empty domain") { error in
        if case .emptyDomain = error { return true }
        return false
    }
}
private func testRejectWhitespaceDomain() throws {
    try expectInvalidDomain(" youtube .com ")
}
private func testRejectWildcard() throws {
    try expectInvalidDomain("*.youtube.com")
}
private func testRejectCommentInjection() throws {
    try expectInvalidDomain("youtube.com#comment")
}
private func testRejectNewlineInjection() throws {
    try expectInvalidDomain("youtube.com\n0.0.0.0 evil.com")
}
private func testRejectIPv4Literal() throws {
    try expectInvalidDomain("127.0.0.1")
}
private func testRejectIPv6Literal() throws {
    try expectInvalidDomain("[::1]")
}
private func testRejectEmptyLabel() throws {
    try expectInvalidDomain("youtube..com")
}
private func testRejectHyphenLabel() throws {
    try expectInvalidDomain("-youtube.com")
    try expectInvalidDomain("youtube-.com")
}
private func testRejectLongLabel() throws {
    try expectInvalidDomain(String(repeating: "a", count: 64) + ".com")
}
private func testRejectLongDomain() throws {
    let longDomain = (0..<60).map { _ in "aaaa" }.joined(separator: ".")
    try expectInvalidDomain(longDomain)
}
private func testRejectUnicodeHostname() throws {
    try expectInvalidDomain("münich.example")
}
private func testAcceptLocalhost() throws {
    try checkEqual(try FocusVaultBlocker.normalizeDomain("localhost"), "localhost", "localhost should be accepted")
}
private func testAcceptPunycode() throws {
    try checkEqual(try FocusVaultBlocker.normalizeDomain("xn--mnich-kva.example"), "xn--mnich-kva.example", "punycode should be accepted")
}
private func testAcceptHTTPSPort() throws {
    try checkEqual(try FocusVaultBlocker.normalizeDomain("https://example.com:443"), "example.com", "HTTPS port should be normalized")
}
private func testEmptyCustomDomainListThrows() throws {
    try expectFocusVaultError({ _ = try FocusVaultBlocker(domains: []) }, "empty custom domain list") { error in
        if case .emptyDomain = error { return true }
        return false
    }
}
