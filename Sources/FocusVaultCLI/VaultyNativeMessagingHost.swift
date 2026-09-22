import Foundation
import VaultyCore

private struct NativeHostReply: Codable {
    let id: String?
    let ok: Bool
    let installed: Bool
    let locked: Bool
    let unlockUntil: Int64?
    let remainingSeconds: Int
    let error: String?
}

private struct NativeHostRequest: Codable {
    let id: String?
    let command: String?
}

enum VaultyNativeMessagingHost {
    static func run() -> Int32 {
        while true {
            var currentRequestID: String?
            do {
                guard let payload = try readMessage() else { return 0 }
                let request = (try? JSONDecoder().decode(NativeHostRequest.self, from: payload))
                currentRequestID = request?.id
                if request?.command == "lock" {
                    let storage = YouTubeGuardStorage()
                    let guardRequest = YouTubeGuardRequest(command: .lock)
                    storage.removeResponse(for: guardRequest.id)
                    _ = try storage.writeRequest(guardRequest)
                    let deadline = Date().addingTimeInterval(1.8)
                    while Date() < deadline, storage.readResponse(for: guardRequest.id) == nil {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    guard let response = storage.readResponse(for: guardRequest.id) else {
                        throw YouTubeGuardError.unavailable("Vaulty’s lock guard did not answer.")
                    }
                    storage.removeResponse(for: guardRequest.id)
                    if !response.succeeded {
                        try writeMessage(JSONEncoder().encode(
                            NativeHostReply(
                                id: request?.id,
                                ok: false,
                                installed: true,
                                locked: true,
                                unlockUntil: nil,
                                remainingSeconds: 0,
                                error: response.message
                            )
                        ))
                        continue
                    }
                }

                let state = YouTubeGuardStorage().readState()
                let now = Date()
                let reply = NativeHostReply(
                    id: request?.id,
                    ok: true,
                    installed: FileManager.default.isExecutableFile(atPath: YouTubeGuardPaths.helperPath),
                    locked: !state.isUnlocked(at: now),
                    unlockUntil: state.unlockedUntil.map { Int64($0.timeIntervalSince1970 * 1_000) },
                    remainingSeconds: state.remainingSeconds(at: now),
                    error: state.lastError
                )
                try writeMessage(JSONEncoder().encode(reply))
            } catch {
                let reply = NativeHostReply(
                    id: currentRequestID,
                    ok: false,
                    installed: false,
                    locked: true,
                    unlockUntil: nil,
                    remainingSeconds: 0,
                    error: error.localizedDescription
                )
                try? writeMessage(JSONEncoder().encode(reply))
                return 1
            }
        }
    }

    private static func readMessage() throws -> Data? {
        guard let lengthData = try readExactly(4) else { return nil }
        let length = lengthData.withUnsafeBytes { bytes -> UInt32 in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        guard length <= 1_048_576 else {
            throw YouTubeGuardError.requestTooLarge
        }
        return try readExactly(Int(length))
    }

    private static func readExactly(_ count: Int) throws -> Data? {
        var result = Data()
        while result.count < count {
            guard let chunk = try FileHandle.standardInput.read(upToCount: count - result.count),
                  !chunk.isEmpty else {
                if result.isEmpty {
                    return nil
                }
                throw YouTubeGuardError.malformedRequest
            }
            result.append(chunk)
        }
        return result
    }

    private static func writeMessage(_ payload: Data) throws {
        var length = UInt32(payload.count).littleEndian
        let lengthData = withUnsafeBytes(of: &length) { Data($0) }
        FileHandle.standardOutput.write(lengthData)
        FileHandle.standardOutput.write(payload)
    }
}
