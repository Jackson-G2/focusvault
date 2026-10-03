import Darwin
import Foundation

/// Cooperating writers lock the current regular inode, then validate that it is
/// still the pathname's inode. Atomic replacement changes the inode, so a waiter
/// holding an old descriptor must reopen/retry before reading its snapshot.
/// No persistent sidecar file or privileged directory is needed.
extension HostsFileStore {
    func withExclusiveAccess<T>(_ operation: (HostsFileStore) throws -> T) throws -> T {
        for _ in 0..<64 {
            let destination = url.resolvingSymlinksInPath()
            let descriptor = open(destination.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if descriptor < 0 {
                let code = errno
                if code == ENOENT {
                    var original = stat()
                    if lstat(url.path, &original) == 0, original.st_mode & S_IFMT == S_IFLNK {
                        throw FocusVaultError.unableToRead(path: url.path, reason: "The hosts symlink has no regular target.")
                    }
                    let created = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
                    if created >= 0 { _ = Darwin.close(created); continue }
                    if errno == EEXIST { continue }
                }
                throw FocusVaultError.unableToWrite(path: url.path,
                    reason: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription)
            }
            defer { _ = Darwin.close(descriptor) }
            var locked = stat()
            guard fstat(descriptor, &locked) == 0, locked.st_mode & S_IFMT == S_IFREG else {
                throw FocusVaultError.unableToRead(path: url.path, reason: "The hosts path is not a regular file.")
            }
            while flock(descriptor, LOCK_EX) != 0 {
                guard errno == EINTR else {
                    throw FocusVaultError.unableToWrite(path: url.path,
                        reason: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription)
                }
            }
            defer { _ = flock(descriptor, LOCK_UN) }
            var current = stat()
            guard lstat(destination.path, &current) == 0,
                  current.st_dev == locked.st_dev, current.st_ino == locked.st_ino else { continue }
            return try operation(HostsFileStore(url: destination))
        }
        throw FocusVaultError.unableToWrite(path: url.path, reason: "The hosts file changed repeatedly. Try again.")
    }
}
