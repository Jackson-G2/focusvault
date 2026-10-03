import Darwin
import Foundation
import VaultyCore

extension VaultyAppInteractionSelfTest {
    @MainActor
    static func testCaffeinateLifecycle() throws {
        let suiteName = "VaultyCaffeinateSelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InteractionTestError.failed("could not create isolated Stay Awake preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = CaffeinateController(defaults: defaults)
        guard CaffeinateController.arguments == ["-dims", "-w", String(ProcessInfo.processInfo.processIdentifier)] else {
            throw InteractionTestError.failed("caffeinate flags are not scoped to Vaulty's lifetime")
        }
        controller.setEnabled(true)
        defer { controller.setEnabled(false) }
        guard controller.isActive, let pid = controller.processID else {
            throw InteractionTestError.failed("Stay Awake did not launch caffeinate")
        }
        guard waitUntil(timeout: 3, condition: { caffeinateAssertionsExist(pid: pid) }) else {
            throw InteractionTestError.failed("caffeinate launched without real macOS display/system assertions")
        }
        try checkApp(defaults.bool(forKey: CaffeinateController.preferenceKey), "Stay Awake On was not persisted")
        controller.setEnabled(true)
        try checkApp(controller.processID == pid, "Stay Awake launched duplicate instances")
        controller.setEnabled(false)
        guard waitUntil(timeout: 3, condition: { !controller.isActive && !controller.isStopping && controller.processID == nil }) else {
            throw InteractionTestError.failed("Stay Awake did not verify its own caffeinate exited")
        }
        try checkApp(!defaults.bool(forKey: CaffeinateController.preferenceKey), "Stay Awake Off was not persisted")
        defaults.set(true, forKey: CaffeinateController.preferenceKey)
        let relaunched = CaffeinateController(defaults: defaults)
        relaunched.restoreEnabledState()
        defer { relaunched.setEnabled(false) }
        guard let newPID = relaunched.processID,
              waitUntil(timeout: 3, condition: { caffeinateAssertionsExist(pid: newPID) }) else {
            throw InteractionTestError.failed("Stay Awake did not restore real assertions after relaunch")
        }
        relaunched.restoreEnabledState()
        try checkApp(relaunched.processID == newPID, "repeated restore duplicated caffeinate")
        relaunched.setEnabled(false)
        _ = waitUntil(timeout: 3, condition: { !relaunched.isActive })
        let disabled = CaffeinateController(defaults: defaults)
        disabled.restoreEnabledState()
        try checkApp(!disabled.isActive, "disabled Stay Awake reactivated on relaunch")
        print("PASS: Stay Awake creates real macOS display/system assertions, remembers On/Off across relaunch, and prevents duplicates")
    }

    static func caffeinateAssertionsExist(pid: Int32) -> Bool {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        command.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        command.standardOutput = pipe
        command.standardError = FileHandle.nullDevice
        do {
            try command.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            command.waitUntilExit()
            let owned = String(decoding: data, as: UTF8.self).split(separator: "\n")
                .filter { $0.contains("pid \(pid)(caffeinate)") }.joined(separator: "\n")
            return owned.contains("PreventUserIdleDisplaySleep") && owned.contains("PreventUserIdleSystemSleep")
        } catch { return false }
    }

}
