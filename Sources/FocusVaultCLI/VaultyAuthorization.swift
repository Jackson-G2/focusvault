import Foundation
import Security
import VaultyCore

struct VaultyAuthorizationToken {
    let externalForm: Data

    var base64: String {
        externalForm.base64EncodedString()
    }
}

enum VaultyAuthorization {
    static func validateUnlockToken(_ encoded: String) -> Bool {
        guard let data = Data(base64Encoded: encoded),
              data.count == MemoryLayout<AuthorizationExternalForm>.size else {
            return false
        }

        var externalForm = AuthorizationExternalForm()
        _ = withUnsafeMutableBytes(of: &externalForm) { destination in
            data.copyBytes(to: destination)
        }

        var authorization: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&externalForm, &authorization) == errAuthorizationSuccess,
              let authorization else {
            return false
        }
        defer {
            AuthorizationFree(authorization, [.destroyRights])
        }

        return YouTubeGuardPaths.authorizationRight.withCString { rightName in
            var item = AuthorizationItem(
                name: rightName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                let status = AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.extendRights],
                    nil
                )
                return status == errAuthorizationSuccess
            }
        }
    }
}
