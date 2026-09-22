import Foundation
import Security
import VaultyCore

private enum VaultyUnlockAuthorizationError: Error, LocalizedError {
    case unableToCreate(OSStatus)
    case denied(OSStatus)
    case unableToExternalize(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unableToCreate(status):
            return "Vaulty could not start Mac authentication (\(status))."
        case let .denied(status):
            if status == errAuthorizationCanceled {
                return "Unlock cancelled. YouTube stayed locked."
            }
            return "Mac authentication failed (\(status)). YouTube stayed locked."
        case let .unableToExternalize(status):
            return "Vaulty could not pass the one-time authorization to its guard (\(status))."
        }
    }
}

final class VaultyUnlockCredential {
    private var reference: AuthorizationRef?
    let externalFormBase64: String

    init(reference: AuthorizationRef? = nil, externalFormBase64: String) {
        self.reference = reference
        self.externalFormBase64 = externalFormBase64
    }

    func destroy() {
        guard let reference else { return }
        AuthorizationFree(reference, [.destroyRights])
        self.reference = nil
    }

    deinit {
        destroy()
    }
}

typealias VaultyUnlockAuthorizationProvider = (
    @escaping (Result<VaultyUnlockCredential, Error>) -> Void
) -> Void

enum VaultyUnlockAuthorization {
    static func request(
        completion: @escaping (Result<VaultyUnlockCredential, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let session = try createSession()
                DispatchQueue.main.async { completion(.success(session)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func createSession() throws -> VaultyUnlockCredential {
        var reference: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &reference)
        guard createStatus == errAuthorizationSuccess, let reference else {
            throw VaultyUnlockAuthorizationError.unableToCreate(createStatus)
        }

        do {
            let status = YouTubeGuardPaths.authorizationRight.withCString { rightName in
                var item = AuthorizationItem(
                    name: rightName,
                    valueLength: 0,
                    value: nil,
                    flags: 0
                )
                return withUnsafeMutablePointer(to: &item) { itemPointer in
                    var rights = AuthorizationRights(count: 1, items: itemPointer)
                    return AuthorizationCopyRights(
                        reference,
                        &rights,
                        nil,
                        [.interactionAllowed, .extendRights, .preAuthorize],
                        nil
                    )
                }
            }
            guard status == errAuthorizationSuccess else {
                throw VaultyUnlockAuthorizationError.denied(status)
            }

            var externalForm = AuthorizationExternalForm()
            let externalStatus = AuthorizationMakeExternalForm(reference, &externalForm)
            guard externalStatus == errAuthorizationSuccess else {
                throw VaultyUnlockAuthorizationError.unableToExternalize(externalStatus)
            }
            let data = withUnsafeBytes(of: &externalForm) { Data($0) }
            return VaultyUnlockCredential(
                reference: reference,
                externalFormBase64: data.base64EncodedString()
            )
        } catch {
            AuthorizationFree(reference, [.destroyRights])
            throw error
        }
    }
}
