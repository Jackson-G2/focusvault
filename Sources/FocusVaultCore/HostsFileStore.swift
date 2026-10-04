import Darwin
import Foundation

/// Hosts-file mechanism kept separate from hostname and document policy.
struct HostsFileStore {
    let url: URL

    func read() throws -> String {
        var information = stat()
        if lstat(url.path, &information) != 0 {
            if errno == ENOENT { return "" }
            throw FocusVaultError.unableToRead(path: url.path, reason: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FocusVaultError.unableToRead(path: url.path, reason: error.localizedDescription)
        }
    }

    func write(_ contents: String) throws {
        // Preserve an intentional hosts-file symlink rather than replacing the
        // link itself. The system /etc alias also resolves through /private/etc.
        let destination = url.resolvingSymlinksInPath()
        do {
            var mode: mode_t = 0o644
            var owner: uid_t?
            var group: gid_t?
            if FileManager.default.fileExists(atPath: destination.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
                }
                mode = mode_t((attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644)
                owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
                group = (attributes[.groupOwnerAccountID] as? NSNumber)?.uint32Value
            }
            try AtomicFileWriter.write(Data(contents.utf8), to: destination, mode: mode, owner: owner, group: group,
                preservingMetadataOf: owner == nil ? nil : destination)
        } catch {
            throw FocusVaultError.unableToWrite(path: url.path, reason: error.localizedDescription)
        }
    }
}
