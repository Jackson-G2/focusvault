import AppKit
import Darwin
import Foundation
import SwiftUI
import VaultyCore

enum FocusSessionPhase: Equatable {
    case ready
    case active
    case paused
    case completed
}

struct UnlockChallengeRequest: Identifiable, Equatable {
    let id = UUID()
}

final class FocusVaultAppModel: ObservableObject {
    // Mutations are implemented in the model's focused, same-target extensions.
    @Published var isSystemBlocked = false
    @Published var isShortFormBlocked = false
    @Published var isGuardInstalled = false
    @Published var youtubeUnlockRemainingSeconds = 0
    @Published var unlockChallengeRequest: UnlockChallengeRequest?
    @Published var selectedUnlockChallengeKind: UnlockChallengeKind?
    @Published var unlockSubmissionError: String?
    @Published var isBusy = false
    @Published var lastError: String?
    @Published var statusMessage = "Ready when you are."
    @Published var intention = ""
    @Published var sessionPhase: FocusSessionPhase = .ready
    @Published var sessionDuration: TimeInterval = 50 * 60
    @Published var remainingSessionSeconds = 0
    @Published var sessionProgress = 0.0

    let defaultChannels = YouTubeChannelDefaults.channels

    let blocker: FocusVaultBlocker
    let shortFormBlocker: ShortFormBlocker
    let privilegedAction: VaultyPrivilegedActionRunner
    let guardRequest: VaultyGuardRequestRunner
    let guardInstalled: () -> Bool
    let adminUnlock: VaultyAdminUnlockRunner
    let guardStorage: YouTubeGuardStorage
    let defaults: UserDefaults
    let now: () -> Date
    var taskClock: FocusTaskClock?
    var sessionTimer: Timer?
    var guardStatusTimer: Timer?

    private static let intentionKey = "Vaulty.intention"
    private static let intermediateIntentionKey = "Kivlet.intention"
    private static let legacyIntentionKey = "FocusVault.intention"

    init(
        hostsFileURL: URL = FocusVaultBlocker.defaultHostsFileURL,
        privilegedAction: @escaping VaultyPrivilegedActionRunner = { arguments, completion in
            PrivilegedHelper.run(arguments: arguments, completion: completion)
        },
        guardRequest: @escaping VaultyGuardRequestRunner = VaultyGuardClient.submit,
        guardInstalled: @escaping () -> Bool = { VaultyGuardClient.isInstalled },
        adminUnlock: @escaping VaultyAdminUnlockRunner = { completion in
            PrivilegedHelper.run(
                arguments: [
                    "internal-admin-unlock-request",
                    "--user-home", NSHomeDirectory(),
                    "--uid", String(getuid()),
                    "--gid", String(getgid())
                ]
            ) { result in
                completion(result.map { _ in () })
            }
        },
        guardStorage: YouTubeGuardStorage = YouTubeGuardStorage(),
        defaults: UserDefaults = .standard,
        startsStatusTimer: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        blocker = try! FocusVaultBlocker(hostsFileURL: hostsFileURL)
        shortFormBlocker = try! ShortFormBlocker(hostsFileURL: hostsFileURL)
        self.privilegedAction = privilegedAction
        self.guardRequest = guardRequest
        self.guardInstalled = guardInstalled
        self.adminUnlock = adminUnlock
        self.guardStorage = guardStorage
        self.defaults = defaults
        self.now = now
        intention = defaults.string(forKey: Self.intentionKey)
            ?? defaults.string(forKey: Self.intermediateIntentionKey)
            ?? defaults.string(forKey: Self.legacyIntentionKey)
            ?? ""
        if !intention.isEmpty, defaults.string(forKey: Self.intentionKey) == nil {
            defaults.set(intention, forKey: Self.intentionKey)
        }
        refresh()
        if startsStatusTimer {
            guardStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.refreshGuardStatus()
            }
            guardStatusTimer?.tolerance = 0.2
        }
    }

    deinit {
        sessionTimer?.invalidate()
        guardStatusTimer?.invalidate()
    }

    func refresh() {
        do {
            let blocked = try blocker.isFullyBlocked()
            let shortFormBlocked = try shortFormBlocker.isBlocked()
            if isSystemBlocked != blocked { isSystemBlocked = blocked }
            if isShortFormBlocked != shortFormBlocked { isShortFormBlocked = shortFormBlocked }
            refreshGuardStatus()
            if lastError == nil {
                updateStatusMessage(vaultStatusMessage)
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Vaulty could not read its status."
        }
    }

    func refreshGuardStatus() {
        let installed = guardInstalled()
        if isGuardInstalled != installed { isGuardInstalled = installed }
        let state = guardStorage.readState()
        let previousRemaining = youtubeUnlockRemainingSeconds
        let remaining = state.remainingSeconds(at: now())
        if youtubeUnlockRemainingSeconds != remaining { youtubeUnlockRemainingSeconds = remaining }
        if remaining > 0, state.restoreShortForm == true, !isShortFormBlocked {
            isShortFormBlocked = true
        }

        if previousRemaining > 0, youtubeUnlockRemainingSeconds == 0 {
            try? refreshBlockerOnly()
        }
        if lastError == nil, !isBusy, unlockChallengeRequest == nil {
            updateStatusMessage(vaultStatusMessage)
        }
    }

    func refreshBlockerOnly() throws {
        let blocked = try blocker.isFullyBlocked()
        if isSystemBlocked != blocked { isSystemBlocked = blocked }
    }

    func updateStatusMessage(_ message: String) {
        if statusMessage != message { statusMessage = message }
    }

    var isAnyVaultBlocked: Bool {
        isSystemBlocked || isShortFormBlocked
    }

    var youtubeUnlockTimeText: String {
        let minutes = youtubeUnlockRemainingSeconds / 60
        let seconds = youtubeUnlockRemainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var vaultStatusMessage: String {
        if !isSystemBlocked, youtubeUnlockRemainingSeconds > 0 {
            return "YouTube open · \(youtubeUnlockTimeText) until automatic lock."
        }
        switch (isSystemBlocked, isShortFormBlocked) {
        case (true, true):
            return "YouTube and short-form vaults engaged."
        case (true, false):
            return "YouTube blocker engaged."
        case (false, true):
            return "Short-form blocker engaged."
        case (false, false):
            return "Ready when you are."
        }
    }

    func saveIntention(_ value: String) {
        let normalized = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(normalized.prefix(80))
        guard clipped != intention else { return }

        intention = clipped
        if clipped.isEmpty {
            defaults.removeObject(forKey: Self.intentionKey)
        } else {
            defaults.set(clipped, forKey: Self.intentionKey)
        }
    }

    func clearError() {
        lastError = nil
    }

    func revealBrowserCompanion() {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRepository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.url(forResource: "BrowserExtension", withExtension: nil),
            currentDirectory.appendingPathComponent("BrowserExtension", isDirectory: true),
            sourceRepository.appendingPathComponent("BrowserExtension", isDirectory: true)
        ].compactMap { $0 }

        guard let extensionURL = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            lastError = "The browser companion was not included in this app bundle."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([extensionURL])
    }

}
