import Foundation

public enum YouTubeGuardPaths {
    public static let helperPath = "/Library/PrivilegedHelperTools/com.jacksongb.vaulty.guard"
    public static let nativeHostPath = "/Library/PrivilegedHelperTools/com.jacksongb.vaulty.native-host"
    public static let launchDaemonPath = "/Library/LaunchDaemons/com.jacksongb.vaulty.guard.plist"
    public static let launchDaemonLabel = "com.jacksongb.vaulty.guard"
    public static let authorizationRight = "com.jacksongb.vaulty.unlock"
    public static let rootAuthorizedRequestMarker = "vaulty.root-admin-request.v1"
    public static let nativeHostName = "com.jacksongb.vaulty"
    public static let supportDirectory = "/Library/Application Support/Vaulty/Guard"
    public static let requestDirectory = supportDirectory + "/Requests"
    public static let responseDirectory = supportDirectory + "/Responses"
    public static let statePath = supportDirectory + "/state.json"

    public static let sessionDuration: TimeInterval = 45 * 60
}

public enum YouTubeGuardCommand: String, Codable, Sendable {
    case lock
    case unlock
}

public struct YouTubeGuardRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let command: YouTubeGuardCommand
    public let authorization: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        command: YouTubeGuardCommand,
        authorization: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.authorization = authorization
        self.createdAt = createdAt
    }

    public func allowsRootOwnedAuthorization(ownerID: UInt32, posixPermissions: Int) -> Bool {
        command == .unlock
            && authorization == YouTubeGuardPaths.rootAuthorizedRequestMarker
            && ownerID == 0
            && (posixPermissions & 0o077) == 0
    }
}

public struct YouTubeGuardResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let succeeded: Bool
    public let message: String
    public let completedAt: Date

    public init(requestID: UUID, succeeded: Bool, message: String, completedAt: Date) {
        self.requestID = requestID
        self.succeeded = succeeded
        self.message = message
        self.completedAt = completedAt
    }
}

public struct YouTubeGuardState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var locked: Bool
    public var unlockedUntil: Date?
    public var restoreShortForm: Bool?
    public var lastRequestID: UUID?
    public var lastError: String?
    public var updatedAt: Date

    public init(
        version: Int = YouTubeGuardState.currentVersion,
        locked: Bool = true,
        unlockedUntil: Date? = nil,
        restoreShortForm: Bool? = nil,
        lastRequestID: UUID? = nil,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.locked = locked
        self.unlockedUntil = unlockedUntil
        self.restoreShortForm = restoreShortForm
        self.lastRequestID = lastRequestID
        self.lastError = lastError
        self.updatedAt = updatedAt
    }

    public func isUnlocked(at date: Date) -> Bool {
        guard !locked, let unlockedUntil else { return false }
        return unlockedUntil > date
    }

    public func remainingSeconds(at date: Date) -> Int {
        guard isUnlocked(at: date), let unlockedUntil else { return 0 }
        return max(0, Int(ceil(unlockedUntil.timeIntervalSince(date))))
    }
}

public enum YouTubeGuardError: Error, LocalizedError, Equatable {
    case invalidAuthorization
    case missingAuthorization
    case requestExpired
    case leaseAlreadyActive
    case requestTooLarge
    case malformedRequest
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAuthorization:
            return "The Mac administrator authorization was not valid. Enter your password again."
        case .missingAuthorization:
            return "Administrator authorization is required before YouTube can be unlocked."
        case .requestExpired:
            return "That unlock attempt expired. Enter your password again."
        case .leaseAlreadyActive:
            return "YouTube already has an active timed session. Lock it before starting another unlock."
        case .requestTooLarge:
            return "The guard request was unexpectedly large."
        case .malformedRequest:
            return "The guard request could not be read."
        case let .unavailable(message):
            return message
        }
    }
}

public struct YouTubeGuardStorage: Sendable {
    public let stateURL: URL
    public let requestDirectoryURL: URL
    public let responseDirectoryURL: URL

    public init(
        stateURL: URL = URL(fileURLWithPath: YouTubeGuardPaths.statePath),
        requestDirectoryURL: URL = URL(fileURLWithPath: YouTubeGuardPaths.requestDirectory, isDirectory: true),
        responseDirectoryURL: URL = URL(fileURLWithPath: YouTubeGuardPaths.responseDirectory, isDirectory: true)
    ) {
        self.stateURL = stateURL
        self.requestDirectoryURL = requestDirectoryURL
        self.responseDirectoryURL = responseDirectoryURL
    }

    public func readState(now: Date = Date()) -> YouTubeGuardState {
        guard let data = try? Data(contentsOf: stateURL),
              var state = try? Self.decoder.decode(YouTubeGuardState.self, from: data) else {
            return YouTubeGuardState(updatedAt: now)
        }

        if !state.isUnlocked(at: now) {
            state.locked = true
            state.unlockedUntil = nil
        }
        return state
    }

    public func writeState(_ state: YouTubeGuardState) throws {
        try write(Self.encoder.encode(state), to: stateURL, mode: 0o644)
    }

    public func writeRequest(_ request: YouTubeGuardRequest) throws -> URL {
        try FileManager.default.createDirectory(
            at: requestDirectoryURL,
            withIntermediateDirectories: true
        )
        let destination = requestDirectoryURL.appendingPathComponent("\(request.id.uuidString).json")
        try write(Self.encoder.encode(request), to: destination, mode: 0o600)
        return destination
    }

    public func readResponse(for requestID: UUID) -> YouTubeGuardResponse? {
        let url = responseDirectoryURL.appendingPathComponent("\(requestID.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(YouTubeGuardResponse.self, from: data)
    }

    public func writeResponse(_ response: YouTubeGuardResponse) throws {
        try FileManager.default.createDirectory(
            at: responseDirectoryURL,
            withIntermediateDirectories: true
        )
        let destination = responseDirectoryURL.appendingPathComponent("\(response.requestID.uuidString).json")
        try write(Self.encoder.encode(response), to: destination, mode: 0o644)
    }

    public func removeResponse(for requestID: UUID) {
        let url = responseDirectoryURL.appendingPathComponent("\(requestID.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    public func pendingRequestURLs() -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: requestDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func readRequest(at url: URL, maximumBytes: Int = 16_384) throws -> YouTubeGuardRequest {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw YouTubeGuardError.malformedRequest }
        guard (values.fileSize ?? maximumBytes + 1) <= maximumBytes else {
            throw YouTubeGuardError.requestTooLarge
        }
        do {
            return try Self.decoder.decode(YouTubeGuardRequest.self, from: Data(contentsOf: url))
        } catch {
            throw YouTubeGuardError.malformedRequest
        }
    }

    private func write(_ data: Data, to destination: URL, mode: mode_t) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        _ = chmod(temporary.path, mode)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

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
                let restoreShortForm = try shortFormBlocker.isBlocked()
                state.locked = false
                state.unlockedUntil = deadline
                state.restoreShortForm = restoreShortForm
                state.lastRequestID = request.id
                state.lastError = nil
                state.updatedAt = date
                do {
                    _ = try blocker.unblock()
                    if restoreShortForm {
                        _ = try leaseShortFormBlocker.block()
                    }
                    try storage.writeState(state)
                } catch {
                    // Never leave YouTube open when the durable lease cannot be
                    // recorded. Roll back to the exact protected scopes.
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
                    _ = try? blocker.block()
                    var rollbackState = state
                    rollbackState.locked = true
                    rollbackState.unlockedUntil = nil
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
