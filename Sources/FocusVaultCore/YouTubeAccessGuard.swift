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
