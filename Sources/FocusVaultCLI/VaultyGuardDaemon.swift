import Darwin
import Foundation
import VaultyCore

private enum VaultyGuardDaemonError: Error, LocalizedError {
    case rootRequired

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            return "The Vaulty guard daemon must run as root."
        }
    }
}

enum VaultyGuardDaemon {
    static func run() throws -> Never {
        guard geteuid() == 0 else {
            throw VaultyGuardDaemonError.rootRequired
        }

        let storage = YouTubeGuardStorage()
        let engine = try YouTubeGuardEngine(
            storage: storage,
            authorizationValidator: VaultyAuthorization.validateUnlockToken
        )
        let rootAuthorizedEngine = try YouTubeGuardEngine(
            storage: storage,
            authorizationValidator: { token in
                token == YouTubeGuardPaths.rootAuthorizedRequestMarker
            }
        )

        try prepareDirectories()
        // A helper crash, update, or reboot must never preserve an open lease
        // without its in-memory monotonic deadline. Fail closed on every start.
        let startupLock = YouTubeGuardRequest(command: .lock)
        _ = try engine.process(startupLock)
        storage.removeResponse(for: startupLock.id)

        let continuousClock = ContinuousClock()
        var leaseDeadline: ContinuousClock.Instant?
        var lastEnforcement = Date.distantPast
        while true {
            autoreleasepool {
                processPendingRequests(
                    storage: storage,
                    engine: engine,
                    rootAuthorizedEngine: rootAuthorizedEngine,
                    continuousClock: continuousClock,
                    leaseDeadline: &leaseDeadline
                )
                if let deadline = leaseDeadline, continuousClock.now >= deadline {
                    let expiryLock = YouTubeGuardRequest(command: .lock)
                    _ = try? engine.process(expiryLock)
                    storage.removeResponse(for: expiryLock.id)
                    leaseDeadline = nil
                }
                let now = Date()
                if now.timeIntervalSince(lastEnforcement) >= 1 {
                    do {
                        _ = try engine.enforce()
                    } catch {
                        writeDaemonError(error, storage: storage, now: now)
                    }
                    lastEnforcement = now
                }
            }
            Thread.sleep(forTimeInterval: 0.20)
        }
    }

    private static func processPendingRequests(
        storage: YouTubeGuardStorage,
        engine: YouTubeGuardEngine,
        rootAuthorizedEngine: YouTubeGuardEngine,
        continuousClock: ContinuousClock,
        leaseDeadline: inout ContinuousClock.Instant?
    ) {
        for requestURL in storage.pendingRequestURLs() {
            defer { try? FileManager.default.removeItem(at: requestURL) }
            do {
                let request = try storage.readRequest(at: requestURL)
                let attributes = try FileManager.default.attributesOfItem(atPath: requestURL.path)
                let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value ?? UInt32.max
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
                let requestEngine = request.allowsRootOwnedAuthorization(
                    ownerID: ownerID,
                    posixPermissions: permissions
                ) ? rootAuthorizedEngine : engine
                let response = try requestEngine.process(request)
                guard response.succeeded else { continue }
                switch request.command {
                case .lock:
                    leaseDeadline = nil
                case .unlock:
                    leaseDeadline = continuousClock.now.advanced(
                        by: .seconds(YouTubeGuardPaths.sessionDuration)
                    )
                }
            } catch {
                // Malformed requests have no trustworthy request identifier.
                // Remove them and keep the existing lock/lease state unchanged.
                writeDaemonError(error, storage: storage, now: Date())
            }
        }
    }

    private static func prepareDirectories() throws {
        let fileManager = FileManager.default
        let support = URL(fileURLWithPath: YouTubeGuardPaths.supportDirectory, isDirectory: true)
        let requests = URL(fileURLWithPath: YouTubeGuardPaths.requestDirectory, isDirectory: true)
        let responses = URL(fileURLWithPath: YouTubeGuardPaths.responseDirectory, isDirectory: true)
        for directory in [support, requests, responses] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        _ = chmod(support.path, 0o755)
        _ = chmod(requests.path, 0o1733)
        _ = chmod(responses.path, 0o755)
    }

    private static func writeDaemonError(
        _ error: Error,
        storage: YouTubeGuardStorage,
        now: Date
    ) {
        var state = storage.readState(now: now)
        state.lastError = error.localizedDescription
        state.updatedAt = now
        try? storage.writeState(state)
    }
}
