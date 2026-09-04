import AppKit
import Foundation
import SwiftUI
import FocusVaultCore

private enum FocusVaultAppError: LocalizedError {
    case bundledHelperMissing
    case commandFailed(String)
    case sessionAlreadyActive
    case invalidSessionDuration
    case busy

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "The bundled FocusVault helper was not found. Build the app with scripts/package-app.sh."
        case let .commandFailed(message):
            return message
        case .sessionAlreadyActive:
            return "A task clock is already running."
        case .invalidSessionDuration:
            return "Choose a task estimate between 1 and 240 minutes."
        case .busy:
            return "FocusVault is already working on that change."
        }
    }
}

private enum PrivilegedHelper {
    static func run(action: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let helperURL = try locateHelper()
                let shellCommand = "\(shellQuote(helperURL.path)) \(shellQuote(action))"
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
        if let bundled = Bundle.main.url(forResource: "focusvault-cli", withExtension: nil) {
            return bundled
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let developmentHelper = currentDirectory
            .appendingPathComponent(".build/release/focusvault")
        if FileManager.default.isExecutableFile(atPath: developmentHelper.path) {
            return developmentHelper
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

final class FocusVaultAppModel: ObservableObject {
    @Published private(set) var isSystemBlocked = false
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
    private var taskClock: FocusTaskClock?
    private var sessionTimer: Timer?

    private static let intentionKey = "FocusVault.intention"

    init() {
        blocker = try! FocusVaultBlocker()
        intention = UserDefaults.standard.string(forKey: Self.intentionKey) ?? ""
        refresh()
    }

    deinit {
        sessionTimer?.invalidate()
    }

    func refresh() {
        do {
            isSystemBlocked = try blocker.isBlocked()
            if lastError == nil {
                statusMessage = isSystemBlocked
                    ? "Full vault engaged."
                    : "Ready when you are."
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "FocusVault could not read its status."
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
        setFullVault(shouldBlock: !isSystemBlocked, completion: nil)
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

        setFullVault(shouldBlock: true) { [weak self] result in
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
        statusMessage = isSystemBlocked ? "Full vault engaged." : "Ready when you are."
    }

    func clearError() {
        lastError = nil
    }

    func revealBrowserCompanion() {
        guard let extensionURL = Bundle.main.url(
            forResource: "BrowserExtension",
            withExtension: nil
        ) else {
            lastError = "The browser companion was not included in this app bundle."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([extensionURL])
    }

    private func setFullVault(
        shouldBlock: Bool,
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
        statusMessage = shouldBlock ? "Engaging the full vault…" : "Opening the full vault…"
        let action = shouldBlock ? "block" : "unblock"

        PrivilegedHelper.run(action: action) { [weak self] result in
            guard let self else { return }
            self.isBusy = false

            switch result {
            case .success:
                self.refresh()
                self.statusMessage = self.isSystemBlocked
                    ? "Full vault engaged."
                    : "Ready when you are."
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
