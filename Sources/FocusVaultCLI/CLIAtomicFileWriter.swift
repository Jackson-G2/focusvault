import Darwin
import Foundation

/// Publish complete privileged artifacts with checked metadata and one rename.
/// No destination is unlinked first, including when metadata setup fails.
enum CLIAtomicFileWriter {
    static func write(_ data: Data, to destination: URL, mode: mode_t, owner: uid_t, group: gid_t) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var template = Array(destination.deletingLastPathComponent().appendingPathComponent(".vaulty-install-XXXXXX").path.utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard descriptor >= 0 else { throw posixError() }
        let temporary = String(cString: template)
        defer { _ = Darwin.close(descriptor); _ = unlink(temporary) }
        try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).write(contentsOf: data)
        guard fchown(descriptor, owner, group) == 0, fchmod(descriptor, mode) == 0,
              fsync(descriptor) == 0, rename(temporary, destination.path) == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
