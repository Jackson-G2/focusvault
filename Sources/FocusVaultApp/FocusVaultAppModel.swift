import AppKit
import Darwin
import Foundation
import SwiftUI
import VaultyCore

private enum FocusVaultAppError: LocalizedError {
    case bundledHelperMissing
    case commandFailed(String)
    case sessionAlreadyActive
    case invalidSessionDuration
    case busy
    case unlockNotApplied

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "The bundled Vaulty helper was not found. Build the app with scripts/package-app.sh."
        case let .commandFailed(message):
            return message
        case .sessionAlreadyActive:
            return "A task clock is already running."
        case .invalidSessionDuration:
            return "Choose a task estimate between 1 and 240 minutes."
        case .busy:
            return "Vaulty is already working on that change."
        case .unlockNotApplied:
            return "The guard answered, but YouTube is still locked. Close this window and try the unlock again."
        }
    }
}

typealias VaultyPrivilegedActionRunner = (
    [String],
    @escaping (Result<String, Error>) -> Void
) -> Void

typealias VaultyAdminUnlockRunner = (
    @escaping (Result<Void, Error>) -> Void
) -> Void

private enum PrivilegedHelper {
    static func run(arguments: [String], completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let helperURL = try locateHelper()
                let commandParts = [helperURL.path] + arguments
                let shellCommand = commandParts.map(shellQuote).joined(separator: " ")
                let appleScript = "do shell script \"\(appleScriptQuote(shellCommand))\" with administrator privileges"

                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                try process.run()
                process.waitUntilExit()

                let output = String(
                    data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let error = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard process.terminationStatus == 0 else {
                    throw FocusVaultAppError.commandFailed(
                        error.isEmpty ? "The administrator action was cancelled or failed." : error
                    )
                }

                DispatchQueue.main.async {
                    completion(.success(output))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func locateHelper() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "vaulty-cli", withExtension: nil) {
            return bundled
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRepository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = [currentDirectory, sourceRepository]

        for root in roots {
            let developmentHelper = root.appendingPathComponent(".build/release/vaulty")
            if FileManager.default.isExecutableFile(atPath: developmentHelper.path) {
                return developmentHelper
            }
        }

        throw FocusVaultAppError.bundledHelperMissing
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

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
    @Published private(set) var isSystemBlocked = false
    @Published private(set) var isShortFormBlocked = false
    @Published private(set) var isGuardInstalled = false
    @Published private(set) var youtubeUnlockRemainingSeconds = 0
    @Published private(set) var unlockChallengeRequest: UnlockChallengeRequest?
    @Published private(set) var selectedUnlockChallengeKind: UnlockChallengeKind?
    @Published private(set) var unlockSubmissionError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage = "Ready when you are."
    @Published private(set) var intention = ""
    @Published private(set) var sessionPhase: FocusSessionPhase = .ready
    @Published private(set) var sessionDuration: TimeInterval = 50 * 60
    @Published private(set) var remainingSessionSeconds = 0
    @Published private(set) var sessionProgress = 0.0

    let defaultChannels = YouTubeChannelDefaults.channels

    private let blocker: FocusVaultBlocker
    private let shortFormBlocker: ShortFormBlocker
    private let privilegedAction: VaultyPrivilegedActionRunner
    private let guardRequest: VaultyGuardRequestRunner
    private let guardInstalled: () -> Bool
    private let adminUnlock: VaultyAdminUnlockRunner
    private let guardStorage: YouTubeGuardStorage
    private var taskClock: FocusTaskClock?
    private var sessionTimer: Timer?
    private var guardStatusTimer: Timer?

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
        guardStorage: YouTubeGuardStorage = YouTubeGuardStorage()
    ) {
        blocker = try! FocusVaultBlocker(hostsFileURL: hostsFileURL)
        shortFormBlocker = try! ShortFormBlocker(hostsFileURL: hostsFileURL)
        self.privilegedAction = privilegedAction
        self.guardRequest = guardRequest
        self.guardInstalled = guardInstalled
        self.adminUnlock = adminUnlock
        self.guardStorage = guardStorage
        intention = UserDefaults.standard.string(forKey: Self.intentionKey)
            ?? UserDefaults.standard.string(forKey: Self.intermediateIntentionKey)
            ?? UserDefaults.standard.string(forKey: Self.legacyIntentionKey)
            ?? ""
        if !intention.isEmpty, UserDefaults.standard.string(forKey: Self.intentionKey) == nil {
            UserDefaults.standard.set(intention, forKey: Self.intentionKey)
        }
        refresh()
        guardStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshGuardStatus()
        }
    }

    deinit {
        sessionTimer?.invalidate()
        guardStatusTimer?.invalidate()
    }

    func refresh() {
        do {
            isSystemBlocked = try blocker.isBlocked()
            isShortFormBlocked = try shortFormBlocker.isBlocked()
            refreshGuardStatus()
            if lastError == nil {
                statusMessage = vaultStatusMessage
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Vaulty could not read its status."
        }
    }

    private func refreshGuardStatus() {
        isGuardInstalled = guardInstalled()
        let state = guardStorage.readState()
        let previousRemaining = youtubeUnlockRemainingSeconds
        youtubeUnlockRemainingSeconds = state.remainingSeconds(at: Date())
        if youtubeUnlockRemainingSeconds > 0, state.restoreShortForm == true {
            isShortFormBlocked = true
        }

        if previousRemaining > 0, youtubeUnlockRemainingSeconds == 0 {
            try? refreshBlockerOnly()
        }
        if lastError == nil, !isBusy, unlockChallengeRequest == nil {
            statusMessage = vaultStatusMessage
        }
    }

    private func refreshBlockerOnly() throws {
        isSystemBlocked = try blocker.isBlocked()
    }

    var isAnyVaultBlocked: Bool {
        isSystemBlocked || isShortFormBlocked
    }

    var youtubeUnlockTimeText: String {
        let minutes = youtubeUnlockRemainingSeconds / 60
        let seconds = youtubeUnlockRemainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var vaultStatusMessage: String {
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
            UserDefaults.standard.removeObject(forKey: Self.intentionKey)
        } else {
            UserDefaults.standard.set(clipped, forKey: Self.intentionKey)
        }
    }

    func toggleFullVault() {
        if isSystemBlocked {
            beginYouTubeUnlock()
        } else {
            lockYouTube(completion: nil)
        }
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "vaulty",
              url.host?.lowercased() == "unlock-youtube" else { return }
        if isSystemBlocked {
            beginYouTubeUnlock()
        }
    }

    func chooseUnlockChallenge(_ kind: UnlockChallengeKind) {
        guard unlockChallengeRequest != nil,
              UnlockChallengeKind.taskHubChoices.contains(kind),
              !isBusy else { return }
        selectedUnlockChallengeKind = kind
        unlockSubmissionError = nil
        statusMessage = "Complete \(kind.displayName), then confirm the unlock."
    }

    func returnToUnlockTaskHub() {
        guard unlockChallengeRequest != nil, !isBusy else { return }
        selectedUnlockChallengeKind = nil
        unlockSubmissionError = nil
        statusMessage = "Choose your unlock task."
    }

    func completeUnlockChallenge() {
        guard selectedUnlockChallengeKind != nil else {
            unlockSubmissionError = "Choose an unlock task first."
            return
        }
        guard !isBusy else { return }

        isBusy = true
        unlockSubmissionError = nil
        statusMessage = "Approve the 45-minute YouTube unlock…"
        adminUnlock { [weak self] result in
            guard let self else { return }
            self.isBusy = false

            switch result {
            case .success:
                do {
                    let state = self.guardStorage.readState()
                    let stillBlocked = try self.blocker.isBlocked()
                    guard !state.locked,
                          state.remainingSeconds(at: Date()) > 0,
                          !stillBlocked else {
                        throw FocusVaultAppError.unlockNotApplied
                    }

                    self.lastError = nil
                    self.unlockSubmissionError = nil
                    self.refresh()
                    guard !self.isSystemBlocked, self.youtubeUnlockRemainingSeconds > 0 else {
                        throw FocusVaultAppError.unlockNotApplied
                    }
                    self.selectedUnlockChallengeKind = nil
                    self.unlockChallengeRequest = nil
                    self.statusMessage = "YouTube open · \(self.youtubeUnlockTimeText) until automatic lock."
                } catch {
                    let message = error.localizedDescription
                    self.unlockSubmissionError = message
                    self.lastError = message
                    self.statusMessage = "YouTube stayed locked."
                    try? self.refreshBlockerOnly()
                }
            case let .failure(error):
                let message = error.localizedDescription
                self.unlockSubmissionError = message
                self.lastError = message
                self.statusMessage = "YouTube stayed locked."
                try? self.refreshBlockerOnly()
            }
        }
    }

    func failUnlockChallenge() {
        selectedUnlockChallengeKind = nil
        unlockSubmissionError = nil
        unlockChallengeRequest = nil
        statusMessage = "Challenge failed. Enter your password again to retry."
    }

    func cancelUnlockChallenge() {
        selectedUnlockChallengeKind = nil
        unlockSubmissionError = nil
        unlockChallengeRequest = nil
        statusMessage = vaultStatusMessage
    }

    func toggleShortFormVault() {
        guard youtubeUnlockRemainingSeconds == 0 else {
            lastError = "Lock YouTube before changing system-wide short-form protection."
            return
        }
        setShortFormVault(shouldBlock: !isShortFormBlocked, completion: nil)
    }

    func startFocusSession(minutes: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard sessionPhase != .active && sessionPhase != .paused else {
            let error = FocusVaultAppError.sessionAlreadyActive
            lastError = error.localizedDescription
            completion(.failure(error))
            return
        }
        guard (1...240).contains(minutes) else {
            let error = FocusVaultAppError.invalidSessionDuration
            lastError = error.localizedDescription
            completion(.failure(error))
            return
        }

        lastError = nil
        if isSystemBlocked {
            beginFocusSession(minutes: minutes)
            completion(.success(()))
            return
        }

        lockYouTube { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.beginFocusSession(minutes: minutes)
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func pauseFocusSession() {
        guard sessionPhase == .active, var taskClock else { return }
        guard taskClock.pause(at: Date()) else { return }

        self.taskClock = taskClock
        sessionTimer?.invalidate()
        sessionTimer = nil
        publish(taskClock)
        sessionPhase = .paused
        statusMessage = "Task clock paused."
    }

    func resumeFocusSession() {
        guard sessionPhase == .paused, var taskClock else { return }
        guard taskClock.resume(at: Date()) else { return }

        self.taskClock = taskClock
        sessionPhase = .active
        statusMessage = "Focus session in progress."
        tickSession()
        guard sessionPhase == .active else { return }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickSession()
        }
    }

    func endFocusSession() {
        guard sessionPhase == .active || sessionPhase == .paused else { return }
        if var taskClock {
            _ = taskClock.stop(at: Date())
        }
        sessionTimer?.invalidate()
        sessionTimer = nil
        taskClock = nil
        remainingSessionSeconds = 0
        sessionProgress = 0
        sessionPhase = .ready
        statusMessage = vaultStatusMessage
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

    private func beginYouTubeUnlock() {
        guard !isBusy, unlockChallengeRequest == nil else {
            lastError = FocusVaultAppError.busy.localizedDescription
            return
        }
        lastError = nil
        selectedUnlockChallengeKind = nil
        unlockSubmissionError = nil

        ensureGuardInstalled { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.selectedUnlockChallengeKind = nil
                self.unlockSubmissionError = nil
                self.unlockChallengeRequest = UnlockChallengeRequest()
                self.statusMessage = "Choose a task. Administrator approval comes after you win."
            case let .failure(error):
                self.lastError = error.localizedDescription
                self.statusMessage = "YouTube stayed locked."
            }
        }
    }

    private func lockYouTube(completion: ((Result<Void, Error>) -> Void)?) {
        guard !isBusy else {
            let error = FocusVaultAppError.busy
            lastError = error.localizedDescription
            completion?(.failure(error))
            return
        }
        lastError = nil

        ensureGuardInstalled { [weak self] setupResult in
            guard let self else { return }
            switch setupResult {
            case .success:
                self.isBusy = true
                self.statusMessage = "Locking YouTube…"
                self.guardRequest(YouTubeGuardRequest(command: .lock)) { [weak self] result in
                    guard let self else { return }
                    self.isBusy = false
                    switch result {
                    case .success:
                        self.refresh()
                        self.statusMessage = "YouTube locked. No password needed."
                        completion?(.success(()))
                    case let .failure(error):
                        self.lastError = error.localizedDescription
                        self.statusMessage = "YouTube could not be locked."
                        completion?(.failure(error))
                    }
                }
            case let .failure(error):
                self.lastError = error.localizedDescription
                self.statusMessage = "YouTube could not be locked."
                completion?(.failure(error))
            }
        }
    }

    private func ensureGuardInstalled(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if guardInstalled() {
            isGuardInstalled = true
            completion(.success(()))
            return
        }

        isBusy = true
        statusMessage = "One-time setup: installing the automatic YouTube guard…"
        let arguments = [
            "internal-install-guard",
            "--user-home", NSHomeDirectory(),
            "--uid", String(getuid()),
            "--gid", String(getgid())
        ]
        privilegedAction(arguments) { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success:
                self.isGuardInstalled = self.guardInstalled()
                self.refresh()
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func setShortFormVault(
        shouldBlock: Bool,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        setVault(
            shouldBlock: shouldBlock,
            action: shouldBlock ? "short-form-block" : "short-form-unblock",
            inProgressMessage: shouldBlock ? "Engaging the short-form blocker…" : "Opening the short-form blocker…",
            completion: completion
        )
    }

    private func setVault(
        shouldBlock: Bool,
        action: String,
        inProgressMessage: String,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard !isBusy else {
            let error = FocusVaultAppError.busy
            lastError = error.localizedDescription
            completion?(.failure(error))
            return
        }

        isBusy = true
        lastError = nil
        statusMessage = inProgressMessage

        privilegedAction([action]) { [weak self] result in
            guard let self else { return }
            self.isBusy = false

            switch result {
            case .success:
                self.refresh()
                completion?(.success(()))
            case let .failure(error):
                self.lastError = error.localizedDescription
                self.statusMessage = "No changes were made."
                completion?(.failure(error))
            }
        }
    }

    private func beginFocusSession(minutes: Int) {
        sessionTimer?.invalidate()
        guard var taskClock = try? FocusTaskClock(minutes: minutes), taskClock.start(at: Date()) else {
            lastError = FocusVaultAppError.invalidSessionDuration.localizedDescription
            return
        }
        self.taskClock = taskClock
        publish(taskClock)
        sessionPhase = .active
        statusMessage = "Focus session in progress."
        tickSession()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickSession()
        }
    }

    private func tickSession() {
        guard var taskClock else { return }
        taskClock.update(at: Date())
        self.taskClock = taskClock
        publish(taskClock)

        if taskClock.state == .completed {
            sessionTimer?.invalidate()
            sessionTimer = nil
            sessionPhase = .completed
            sessionProgress = 1
            statusMessage = "You kept the room."
        }
    }

    private func publish(_ taskClock: FocusTaskClock) {
        sessionDuration = taskClock.durationSeconds
        remainingSessionSeconds = taskClock.remainingWholeSeconds
        sessionProgress = taskClock.progress
    }
}
