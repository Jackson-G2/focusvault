import Foundation

public final class YouTubeGuardEngine {
    public typealias AuthorizationValidator = (String) -> Bool

    private let blocker: FocusVaultBlocker
    private let shortFormBlocker: ShortFormBlocker
    private let leaseShortFormBlocker: ShortFormBlocker
    private let storage: YouTubeGuardStorage
    private let authorizationValidator: AuthorizationValidator
    private let now: () -> Date

    public init(
        hostsFileURL: URL = FocusVaultBlocker.defaultHostsFileURL,
        storage: YouTubeGuardStorage = YouTubeGuardStorage(),
        authorizationValidator: @escaping AuthorizationValidator,
        now: @escaping () -> Date = Date.init
    ) throws {
        blocker = try FocusVaultBlocker(hostsFileURL: hostsFileURL)
        shortFormBlocker = try ShortFormBlocker(hostsFileURL: hostsFileURL)
        leaseShortFormBlocker = try ShortFormBlocker(
            hostsFileURL: hostsFileURL,
            domains: ShortFormPolicy.nonYouTubeHosts
        )
        self.storage = storage
        self.authorizationValidator = authorizationValidator
        self.now = now
    }

    @discardableResult
    public func enforce() throws -> YouTubeGuardState {
        let date = now()
        var state = storage.readState(now: date)
        if state.isUnlocked(at: date) {
            _ = try blocker.unblock()
            if state.restoreShortForm == true {
                _ = try leaseShortFormBlocker.block()
            }
            state.locked = false
        } else {
            _ = try blocker.block()
            if state.restoreShortForm == true {
                _ = try shortFormBlocker.block()
                state.restoreShortForm = nil
            }
            state.locked = true
            state.unlockedUntil = nil
        }
        state.updatedAt = date
        try storage.writeState(state)
        return state
    }

    @discardableResult
    public func process(_ request: YouTubeGuardRequest) throws -> YouTubeGuardResponse {
        let date = now()
        guard abs(date.timeIntervalSince(request.createdAt)) <= 10 * 60 else {
            return try failure(request, error: YouTubeGuardError.requestExpired, at: date)
        }

        do {
            switch request.command {
            case .lock:
                var state = storage.readState(now: date)
                let shouldRestoreShortForm = state.restoreShortForm == true
                state.locked = true
                state.unlockedUntil = nil
                state.lastRequestID = request.id
                state.lastError = nil
                state.updatedAt = date
                // Publish the closed state before touching /etc/hosts so the
                // browser companion fails closed even if the system write fails.
                try storage.writeState(state)
                _ = try blocker.block()
                if shouldRestoreShortForm {
                    _ = try shortFormBlocker.block()
                    state.restoreShortForm = nil
                    try storage.writeState(state)
                }
                return try success(request, message: "YouTube locked.", at: date)

            case .unlock:
                guard let authorization = request.authorization, !authorization.isEmpty else {
                    throw YouTubeGuardError.missingAuthorization
                }
                guard authorizationValidator(authorization) else {
                    throw YouTubeGuardError.invalidAuthorization
                }

                let deadline = date.addingTimeInterval(YouTubeGuardPaths.sessionDuration)
                var state = storage.readState(now: date)
                guard !state.isUnlocked(at: date) else {
                    throw YouTubeGuardError.leaseAlreadyActive
                }
                let restoreShortForm = try (state.restoreShortForm == true || shortFormBlocker.isBlocked())
                state.locked = false
                state.unlockedUntil = deadline
                state.restoreShortForm = restoreShortForm
                state.lastRequestID = request.id
                state.lastError = nil
                state.updatedAt = date
                // Persist restoration intent while still CLOSED, before any
                // hosts mutation. A crash or a failed final commit can then be
                // repaired by enforce() without losing short-form protection.
                var closedState = state
                closedState.locked = true
                closedState.unlockedUntil = nil
                try storage.writeState(closedState)
                do {
                    _ = try blocker.unblock()
                    if restoreShortForm {
                        _ = try leaseShortFormBlocker.block()
                    }
                    try storage.writeState(state)
                } catch {
                    // Never leave YouTube open when the durable lease cannot be
                    // recorded. Roll back to the exact protected scopes.
                    try? storage.writeState(closedState)
                    _ = try? blocker.block()
                    if restoreShortForm {
                        _ = try? shortFormBlocker.block()
                    }
                    throw error
                }
                do {
                    return try success(request, message: "YouTube unlocked for 45 minutes.", at: date)
                } catch {
                    // If the app cannot receive a durable success response,
                    // cancel the lease rather than leaving an invisible unlock.
                    var rollbackState = closedState
                    try? storage.writeState(rollbackState)
                    _ = try? blocker.block()
                    if restoreShortForm, (try? shortFormBlocker.block()) != nil {
                        rollbackState.restoreShortForm = nil
                    }
                    rollbackState.lastError = error.localizedDescription
                    rollbackState.updatedAt = date
                    try? storage.writeState(rollbackState)
                    throw error
                }
            }
        } catch {
            return try failure(request, error: error, at: date)
        }
    }

    private func success(
        _ request: YouTubeGuardRequest,
        message: String,
        at date: Date
    ) throws -> YouTubeGuardResponse {
        let response = YouTubeGuardResponse(
            requestID: request.id,
            succeeded: true,
            message: message,
            completedAt: date
        )
        try storage.writeResponse(response)
        return response
    }

    private func failure(
        _ request: YouTubeGuardRequest,
        error: Error,
        at date: Date
    ) throws -> YouTubeGuardResponse {
        var state = storage.readState(now: date)
        state.lastRequestID = request.id
        state.lastError = error.localizedDescription
        state.updatedAt = date
        try storage.writeState(state)

        let response = YouTubeGuardResponse(
            requestID: request.id,
            succeeded: false,
            message: error.localizedDescription,
            completedAt: date
        )
        try storage.writeResponse(response)
        return response
    }
}
