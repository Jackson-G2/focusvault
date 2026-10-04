import Foundation

extension LocalToolsManager {
    func checkForUpdates(_ runtime: LocalToolRuntime) {
        guard !runtime.isCheckingUpdate else { return }
        runtime.isCheckingUpdate = true
        runtime.updateText = "Checking…"
        let definition = runtime.definition

        DispatchQueue.global(qos: .utility).async {
            let result: Result<String, Error>
            switch definition.updateMode {
            case .none:
                result = .success("No update source configured")
            case .npmPackage:
                result = LocalToolUpdateChecker.checkNPMUpdate(package: definition.updateIdentifier)
            case .gitRemote:
                result = LocalToolUpdateChecker.checkGitUpdate(directory: definition.workingDirectory)
            }
            DispatchQueue.main.async {
                runtime.isCheckingUpdate = false
                switch result {
                case let .success(message): runtime.updateText = message
                case let .failure(error): runtime.updateText = error.localizedDescription
                }
            }
        }
    }
}

enum LocalToolUpdateChecker {
    static func checkNPMUpdate(package: String) -> Result<String, Error> {
        switch LocalToolCommandRunner.runForUpdate(executable: "/usr/bin/env", arguments: ["npm", "view", package, "version", "--json"]) {
        case let .success(output):
            let version = output.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n "))
            return .success(version.isEmpty ? "No npm version returned" : "Latest: \(version)")
        case let .failure(error):
            return .failure(error)
        }
    }

    static func checkGitUpdate(directory: String) -> Result<String, Error> {
        let local = LocalToolCommandRunner.runForUpdate(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "rev-parse", "HEAD"]
        )
        let branch = LocalToolCommandRunner.runForUpdate(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "branch", "--show-current"]
        )
        guard case let .success(localSHA) = local,
              case let .success(branchName) = branch,
              !branchName.isEmpty else {
            return .failure(LocalToolError.updateFailed("No Git branch or repository found."))
        }
        let remote = LocalToolCommandRunner.runForUpdate(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "ls-remote", "origin", "refs/heads/\(branchName)"]
        )
        guard case let .success(remoteOutput) = remote,
              let remoteSHA = remoteOutput.split(whereSeparator: \.isWhitespace).first.map(String.init),
              !remoteSHA.isEmpty else {
            return .failure(LocalToolError.updateFailed("No matching origin branch was found."))
        }
        return .success(remoteSHA == localSHA ? "Up to date" : "Update available")
    }
}
