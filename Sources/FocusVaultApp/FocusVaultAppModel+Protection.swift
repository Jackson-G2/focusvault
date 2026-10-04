import Darwin
import Foundation
import VaultyCore

extension FocusVaultAppModel {
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
                          state.remainingSeconds(at: self.now()) > 0,
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
        guard !isBusy else { return }
        selectedUnlockChallengeKind = nil
        unlockSubmissionError = nil
        unlockChallengeRequest = nil
        statusMessage = "Task ended. Choose an unlock task again to retry."
    }

    func cancelUnlockChallenge() {
        guard !isBusy else { return }
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

    func beginYouTubeUnlock() {
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

    func lockYouTube(completion: ((Result<Void, Error>) -> Void)?) {
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
                        do {
                            try self.refreshBlockerOnly()
                            guard self.isSystemBlocked else { throw FocusVaultAppError.lockNotApplied }
                            self.refresh()
                            self.statusMessage = "YouTube locked. No password needed."
                            completion?(.success(()))
                        } catch {
                            self.lastError = error.localizedDescription
                            self.statusMessage = "YouTube could not be locked."
                            completion?(.failure(error))
                        }
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

    func ensureGuardInstalled(
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
                guard self.isGuardInstalled else {
                    completion(.failure(FocusVaultAppError.guardNotInstalled))
                    return
                }
                self.refresh()
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func setShortFormVault(
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

    func setVault(
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
                do {
                    guard try self.shortFormBlocker.isBlocked() == shouldBlock else {
                        throw FocusVaultAppError.shortFormNotApplied
                    }
                    self.refresh()
                    completion?(.success(()))
                } catch {
                    self.lastError = error.localizedDescription
                    self.statusMessage = "The change could not be verified."
                    completion?(.failure(error))
                }
            case let .failure(error):
                self.lastError = error.localizedDescription
                self.statusMessage = "No changes were made."
                completion?(.failure(error))
            }
        }
    }

}
