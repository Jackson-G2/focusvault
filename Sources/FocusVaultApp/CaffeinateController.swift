import Combine
import Foundation

/// Owns only its own caffeinate instance. Assertions expire when Vaulty exits.
final class CaffeinateController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStopping = false
    @Published private(set) var errorText: String?
    private var process: Process?
    private let defaults: UserDefaults
    private var hasRestored = false
    static let preferenceKey = "Vaulty.stayAwake.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreEnabledState() {
        guard !hasRestored else { return }
        hasRestored = true
        if defaults.bool(forKey: Self.preferenceKey) { start() }
    }

    var processID: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }
    static var arguments: [String] { ["-dims", "-w", String(ProcessInfo.processInfo.processIdentifier)] }

    func setEnabled(_ enabled: Bool) {
        hasRestored = true
        if enabled {
            start()
            if isActive { defaults.set(true, forKey: Self.preferenceKey) }
        } else {
            defaults.set(false, forKey: Self.preferenceKey)
            stop()
        }
        defaults.synchronize()
    }

    private func start() {
        guard !isStopping, process?.isRunning != true else { return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        child.arguments = Self.arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self, self.process === child else { return }
                let expected = self.isStopping
                self.process = nil
                self.isActive = false
                self.isStopping = false
                if !expected {
                    self.errorText = "Stay Awake exited unexpectedly. Try turning it on again."
                }
            }
        }
        do {
            try child.run()
            process = child
            isActive = child.isRunning
            errorText = nil
        } catch {
            process = nil
            isActive = false
            errorText = "Could not start caffeinate: \(error.localizedDescription)"
        }
    }

    private func stop() {
        errorText = nil
        guard let process, process.isRunning else {
            self.process = nil
            isActive = false
            isStopping = false
            return
        }
        isStopping = true
        process.terminate()
        // The termination handler confirms exit before reporting Off.
    }
}
