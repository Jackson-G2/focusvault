import Darwin
import Foundation

struct LocalToolRunRecord: Codable {
    let toolID: UUID
    let supervisorPID: pid_t
    let supervisorExecutablePath: String
    let configurationPath: String
    let startedAt: Date
    var reusedPorts: [Int]? = nil
    var startSeconds: UInt64? = nil
    var startMicroseconds: UInt64? = nil
}

extension LocalToolsManager {
    func ownedGroupsExited(_ runtime: LocalToolRuntime) -> Bool {
        guard let pid = runtime.supervisorPID else { return true }
        guard pid > 1 else { return false }
        func absent(_ target: pid_t) -> Bool {
            kill(target, 0) == -1 && errno == ESRCH
        }
        guard absent(pid), absent(-pid), runtime.supervisorProcess?.isRunning != true else { return false }
        let path = runDirectory.appendingPathComponent("\(runtime.id.uuidString).json.child-pgid").path
        if FileManager.default.fileExists(atPath: path) {
            // Existing but unreadable/malformed metadata is unknown, not proof
            // of exit. Preserve ownership rather than lose a detached child.
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                  let childGroup = Int32(text), childGroup > 1 else { return false }
            return absent(-childGroup)
        }
        return true
    }

    func clearOwnership(_ runtime: LocalToolRuntime) {
        removeRunRecord(for: runtime.id)
        runtime.supervisorProcess = nil
        runtime.supervisorPID = nil
        runtime.unsavedRunRecord = nil
    }

    func ownedPortsClosed(_ runtime: LocalToolRuntime, states: [Int: Bool]) -> Bool {
        runtime.definition.expectedPorts.allSatisfy {
            runtime.reusedPorts.contains($0) || states[$0] == false
        }
    }
    func restoreOwnedRuns() {
        for runtime in tools {
            guard let record = readRunRecord(for: runtime.id) else { continue }
            guard record.toolID == runtime.id,
                  record.configurationPath == runDirectory.appendingPathComponent("\(runtime.id.uuidString).json").path else {
                continue // Invalid records are preserved for manual recovery, never signalled.
            }
            runtime.supervisorPID = record.supervisorPID
            runtime.reusedPorts = Set(record.reusedPorts ?? [])
            if ownedGroupsExited(runtime) {
                // The initial status probe must also observe closure of every
                // owned port before deleting even an exited restored record.
                runtime.state = .stopped
                runtime.statusText = "Verifying owned port closure…"
            } else if isVerifiedSupervisor(runtime) {
                runtime.state = .starting
                runtime.statusText = "Reconnecting to Vaulty-owned process…"
                waitForReadiness(runtime, generation: runtime.generation, attempt: 0)
            } else {
                runtime.state = .failed
                runtime.statusText = "Ownership retained · process exit not verified"
                runtime.errorText = "Vaulty will not signal an unverified process. Check its original launcher or log."
            }
        }
    }

    func runRecordURL(for id: UUID) -> URL {
        runDirectory.appendingPathComponent("\(id.uuidString).state.json")
    }

    func writeRunRecord(_ record: LocalToolRunRecord) throws {
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: runRecordURL(for: record.toolID), options: .atomic)
    }

    func readRunRecord(for id: UUID) -> LocalToolRunRecord? {
        guard let data = try? Data(contentsOf: runRecordURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(LocalToolRunRecord.self, from: data)
    }

    func removeRunRecord(for id: UUID) {
        try? FileManager.default.removeItem(at: runRecordURL(for: id))
    }

    func isVerifiedSupervisor(_ runtime: LocalToolRuntime) -> Bool {
        guard let pid = runtime.supervisorPID, pid > 1, getpgid(pid) == pid else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }

        // Read only this tool's record, not every catalog entry on every poll.
        // A persistence failure can use the exact record built for our live child.
        guard let record = runtime.unsavedRunRecord ?? readRunRecord(for: runtime.id),
              record.toolID == runtime.id, record.supervisorPID == pid,
              record.configurationPath == runDirectory.appendingPathComponent("\(runtime.id.uuidString).json").path else { return false }
        if let seconds = record.startSeconds, let micros = record.startMicroseconds {
            guard let identity = LocalToolProcessIdentity.info(pid), identity.pbi_start_tvsec == seconds,
                  identity.pbi_start_tvusec == micros else { return false }
        }
        // An executable match alone could identify another Vaulty window or a
        // recycled PID. Verify this exact tool-supervisor invocation as well.
        guard LocalToolProcessIdentity.arguments(pid).suffix(2) == ["--tool-supervisor", record.configurationPath] else { return false }
        let expectedPath = URL(fileURLWithPath: record.supervisorExecutablePath)
            .standardizedFileURL.resolvingSymlinksInPath().path

        var buffer = [CChar](repeating: 0, count: 4_096)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return false }
        let actualPath = URL(fileURLWithPath: String(cString: buffer))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return expectedPath == actualPath
    }
}

enum LocalToolProcessIdentity {
    static func info(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    static func arguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return [] }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }
        var offset = MemoryLayout<Int32>.size
        while offset < size && bytes[offset] != 0 { offset += 1 } // executable path
        while offset < size && bytes[offset] == 0 { offset += 1 } // padding
        var arguments: [String] = []
        for _ in 0..<argc {
            let start = offset
            while offset < size && bytes[offset] != 0 { offset += 1 }
            guard offset < size else { return [] }
            arguments.append(String(decoding: bytes[start..<offset], as: UTF8.self))
            offset += 1
        }
        return arguments
    }
}
