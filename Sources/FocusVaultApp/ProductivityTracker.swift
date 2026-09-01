import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import FocusVaultCore

final class ProductivityTracker: ObservableObject {
    @Published private(set) var log: ProductivityLog
    @Published private(set) var isTracking = false
    @Published private(set) var lastError: String?

    private let store: ProductivityLogStore?
    private let calendar = Calendar.current
    private var timer: Timer?
    private var lastRecordedMinute: Int?

    private let productiveBundleIdentifiers: Set<String> = [
        "com.apple.dt.Xcode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "com.jetbrains.AppCode",
        "md.obsidian"
    ]

    private let productiveNameFragments = [
        "xcode",
        "terminal",
        "iterm",
        "cursor",
        "visual studio code",
        "sublime",
        "jetbrains",
        "obsidian",
        "warp"
    ]

    init() {
        store = try? ProductivityLogStore()
        log = store?.log ?? ProductivityLog()
        if store == nil {
            lastError = "FocusVault could not open its local productivity log."
        }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        isTracking = true
        recordIfProductive()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.recordIfProductive()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isTracking = false
    }

    func refresh() {
        do {
            try store?.reload()
            log = store?.log ?? ProductivityLog()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func recordIfProductive() {
        let minute = Int(Date().timeIntervalSince1970 / 60)
        guard minute != lastRecordedMinute else { return }
        guard isProductiveApplication(NSWorkspace.shared.frontmostApplication) else { return }
        guard hasRecentInput else { return }

        do {
            try store?.record(minutes: 1, at: Date(), calendar: calendar)
            log = store?.log ?? log
            lastRecordedMinute = minute
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func isProductiveApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        if let bundleIdentifier = application.bundleIdentifier,
           productiveBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        let name = (application.localizedName ?? "").lowercased()
        return productiveNameFragments.contains { name.contains($0) }
    }

    private var hasRecentInput: Bool {
        let state = CGEventSourceStateID.combinedSessionState
        let recentEvents: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .mouseMoved,
            .scrollWheel
        ]
        return recentEvents.contains {
            CGEventSource.secondsSinceLastEventType(state, eventType: $0) < 300
        }
    }
}
