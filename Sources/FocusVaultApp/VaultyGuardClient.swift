import Foundation
import VaultyCore

private enum VaultyGuardClientError: Error, LocalizedError {
    case notInstalled
    case timedOut
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Vaulty’s one-time guard setup is not installed."
        case .timedOut:
            return "Vaulty’s guard did not answer. YouTube stayed locked."
        case let .rejected(message):
            return message
        }
    }
}

typealias VaultyGuardRequestRunner = (
    YouTubeGuardRequest,
    @escaping (Result<YouTubeGuardResponse, Error>) -> Void
) -> Void

enum VaultyGuardClient {
    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: YouTubeGuardPaths.helperPath)
            && FileManager.default.fileExists(atPath: YouTubeGuardPaths.launchDaemonPath)
    }

    static func submit(
        _ request: YouTubeGuardRequest,
        completion: @escaping (Result<YouTubeGuardResponse, Error>) -> Void
    ) {
        guard isInstalled else {
            completion(.failure(VaultyGuardClientError.notInstalled))
            return
        }

        let storage = YouTubeGuardStorage()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                storage.removeResponse(for: request.id)
                _ = try storage.writeRequest(request)
                let deadline = Date().addingTimeInterval(10)

                while Date() < deadline {
                    if let response = storage.readResponse(for: request.id) {
                        storage.removeResponse(for: request.id)
                        DispatchQueue.main.async {
                            if response.succeeded {
                                completion(.success(response))
                            } else {
                                completion(.failure(VaultyGuardClientError.rejected(response.message)))
                            }
                        }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.08)
                }

                throw VaultyGuardClientError.timedOut
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
