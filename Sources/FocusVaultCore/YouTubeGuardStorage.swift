import Darwin
import Foundation

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
        try readRequestWithMetadata(at: url, maximumBytes: maximumBytes).request
    }

    /// Read bytes and authorization-relevant metadata from the SAME inode. Never
    /// follow queue symlinks or re-stat a pathname after decoding its contents.
    public func readRequestWithMetadata(at url: URL, maximumBytes: Int = 16_384) throws
        -> (request: YouTubeGuardRequest, ownerID: UInt32, posixPermissions: Int) {
        guard maximumBytes >= 0, maximumBytes < Int.max else { throw YouTubeGuardError.requestTooLarge }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw YouTubeGuardError.malformedRequest }
        defer { _ = Darwin.close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG else { throw YouTubeGuardError.malformedRequest }
        guard information.st_size >= 0, information.st_size <= maximumBytes else {
            throw YouTubeGuardError.requestTooLarge
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        do {
            while let chunk = try handle.read(upToCount: min(4096, maximumBytes + 1 - data.count)), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= maximumBytes else { throw YouTubeGuardError.requestTooLarge }
            }
            let request = try Self.decoder.decode(YouTubeGuardRequest.self, from: data)
            return (request, UInt32(information.st_uid), Int(information.st_mode & 0o7777))
        } catch let error as YouTubeGuardError {
            throw error
        } catch {
            throw YouTubeGuardError.malformedRequest
        }
    }

    private func write(_ data: Data, to destination: URL, mode: mode_t) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFileWriter.write(data, to: destination, mode: mode)
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
