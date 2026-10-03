import Darwin
import Foundation

/// Stage complete bytes and metadata before one same-directory rename. A failed
/// write never unlinks the destination, and no permissive intermediate file is
/// published. Parent creation is the caller's explicit policy decision.
enum AtomicFileWriter {
    static func write(_ data: Data, to destination: URL, mode: mode_t, owner: uid_t? = nil, group: gid_t? = nil, preservingMetadataOf source: URL? = nil) throws {
        var template = Array(destination.deletingLastPathComponent()
            .appendingPathComponent(".vaulty-XXXXXX").path.utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard descriptor >= 0 else { throw posixError() }
        let temporary = String(cString: template)
        defer {
            _ = Darwin.close(descriptor)
            _ = unlink(temporary)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        if let source {
            let sourceDescriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard sourceDescriptor >= 0 else { throw posixError() }
            defer { _ = Darwin.close(sourceDescriptor) }
            guard fcopyfile(sourceDescriptor, descriptor, nil, copyfile_flags_t(COPYFILE_ACL | COPYFILE_XATTR)) == 0 else {
                throw posixError()
            }
        }
        if let owner, let group {
            guard fchown(descriptor, owner, group) == 0 else { throw posixError() }
        }
        // Writing/chown can clear special mode bits; apply the final mode last.
        guard fchmod(descriptor, mode) == 0 else { throw posixError() }
        guard fsync(descriptor) == 0 else { throw posixError() }
        guard rename(temporary, destination.path) == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
