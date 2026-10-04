import Foundation

typealias VaultyPrivilegedActionRunner = (
    [String],
    @escaping (Result<String, Error>) -> Void
) -> Void

typealias VaultyAdminUnlockRunner = (
    @escaping (Result<Void, Error>) -> Void
) -> Void

enum PrivilegedHelper {
    static func run(arguments: [String], completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let helperURL = try locateHelper()
                let commandParts = [helperURL.path] + arguments
                let shellCommand = commandParts.map(shellQuote).joined(separator: " ")
                let appleScript = "do shell script \"\(appleScriptQuote(shellCommand))\" with administrator privileges"

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                let captured = try ProcessOutputCapture.run(process)
                guard captured.exitStatus == 0 else {
                    throw FocusVaultAppError.commandFailed(
                        captured.stderr.isEmpty ? "The administrator action was cancelled or failed." : captured.stderr
                    )
                }

                DispatchQueue.main.async {
                    completion(.success(captured.stdout))
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
