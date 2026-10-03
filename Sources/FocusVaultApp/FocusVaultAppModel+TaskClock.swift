import Foundation
import VaultyCore

// Internal mutation is confined to model extensions in this executable target.
extension FocusVaultAppModel {
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
        guard taskClock.pause(at: now()) else { return }

        self.taskClock = taskClock
        sessionTimer?.invalidate()
        sessionTimer = nil
        publish(taskClock)
        sessionPhase = .paused
        statusMessage = "Task clock paused."
    }

    func resumeFocusSession() {
        guard sessionPhase == .paused, var taskClock else { return }
        guard taskClock.resume(at: now()) else { return }

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
            _ = taskClock.stop(at: now())
        }
        sessionTimer?.invalidate()
        sessionTimer = nil
        taskClock = nil
        remainingSessionSeconds = 0
        sessionProgress = 0
        sessionPhase = .ready
        statusMessage = vaultStatusMessage
    }

    func beginFocusSession(minutes: Int) {
        sessionTimer?.invalidate()
        guard var taskClock = try? FocusTaskClock(minutes: minutes), taskClock.start(at: now()) else {
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

    func tickSession() {
        guard var taskClock else { return }
        taskClock.update(at: now())
        self.taskClock = taskClock
        publish(taskClock)

        if taskClock.state == .completed {
            sessionTimer?.invalidate()
            sessionTimer = nil
            sessionPhase = .completed
            statusMessage = "You kept the room."
        }
    }

    func publish(_ taskClock: FocusTaskClock) {
        if sessionDuration != taskClock.durationSeconds { sessionDuration = taskClock.durationSeconds }
        if remainingSessionSeconds != taskClock.remainingWholeSeconds { remainingSessionSeconds = taskClock.remainingWholeSeconds }
        if sessionProgress != taskClock.progress { sessionProgress = taskClock.progress }
    }
}
