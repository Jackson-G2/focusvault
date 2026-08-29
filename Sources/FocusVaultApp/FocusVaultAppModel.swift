import AppKit
import Foundation
import SwiftUI
import FocusVaultCore

private enum FocusVaultAppError: LocalizedError {
    case bundledHelperMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "The bundled FocusVault helper was not found. Build the app with scripts/package-app.sh."
        case let .commandFailed(message):
            return message
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

final class FocusVaultAppModel: ObservableObject {
    @Published private(set) var isSystemBlocked = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage = "Your focus vault is open."

    let defaultChannels = YouTubeChannelDefaults.channels

    private let blocker: FocusVaultBlocker

    init() {
        blocker = try! FocusVaultBlocker()
        refresh()
    }

    func refresh() {
        do {
            isSystemBlocked = try blocker.isBlocked()
            if lastError == nil {
                statusMessage = isSystemBlocked
                    ? "Full vault engaged — all YouTube is blocked."
                    : "Your focus vault is open."
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "FocusVault could not read its status."
        }
    }

    func toggleFullVault() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        statusMessage = isSystemBlocked
            ? "Opening the vault…"
            : "Engaging the full vault…"

        let action = isSystemBlocked ? "unblock" : "block"
        PrivilegedHelper.run(action: action) { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success:
                self.refresh()
                self.statusMessage = self.isSystemBlocked
                    ? "Full vault engaged — all YouTube is blocked."
                    : "Your focus vault is open."
            case let .failure(error):
                self.lastError = error.localizedDescription
                self.statusMessage = "No changes were made."
            }
        }
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

    func clearError() {
        lastError = nil
    }
}
