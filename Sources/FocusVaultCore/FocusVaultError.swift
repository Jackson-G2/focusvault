import Foundation

/// Stable errors retained under both the original and current product names.
public enum FocusVaultError: Error, LocalizedError, Equatable {
    case emptyDomain
    case invalidDomain(String)
    case malformedManagedBlock(path: String)
    case unableToRead(path: String, reason: String)
    case unableToWrite(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .emptyDomain:
            return "At least one non-empty hostname is required."
        case let .invalidDomain(domain):
            return "Invalid hostname: \(domain). Use a hostname such as youtube.com, not a wildcard or IP address."
        case let .malformedManagedBlock(path):
            return "The managed Vaulty section in \(path) is malformed or duplicated; refusing to edit the file."
        case let .unableToRead(path, reason):
            return "Could not read \(path): \(reason)"
        case let .unableToWrite(path, reason):
            return "Could not write \(path): \(reason) If this is /etc/hosts, rerun the command with sudo."
        }
    }
}

public typealias VaultyError = FocusVaultError
