import Darwin
import Foundation

// Lifecycle mutations and callbacks are delivered on the main queue.
extension LocalToolsManager {
    func startOrOpen(_ runtime: LocalToolRuntime) {
        guard contains(runtime), runtime.state != .checking,
              runtime.state != .starting,
              runtime.state != .stopping else { return }
        if runtime.isRunning {
            openPrimaryLink(runtime)
            return
        }

        guard runtime.supervisorPID == nil else {
            runtime.errorText = "Stop or Restart the owned service before retrying."
            return
        }
        let generation = beginOperation(runtime)
        runtime.state = .checking
        runtime.statusText = "Checking local ports…"
        runtime.errorText = nil
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .checking else { return }
            guard runtime.definition.expectedPorts.allSatisfy({ states[$0] != nil }) else {
                self.fail(runtime, LocalToolError.launchFailed("Could not determine every expected local port's status. No process was launched."))
                return
            }
            let openPorts = states.filter(\.value).map(\.key).sorted()
            if let primary = runtime.definition.primaryPort, states[primary] == true {
                runtime.state = .runningExternal
                runtime.statusText = BBExternalLifecycle.matches(runtime.definition)
                    ? "External bb · restart available"
                    : "External · use its original launcher"
                self.openPrimaryLink(runtime)
                return
            }
            if !openPorts.isEmpty, !runtime.definition.allowsPartialReuse {
                self.fail(runtime, LocalToolError.partiallyRunning(openPorts))
                return
            }
            runtime.reusedPorts = Set(openPorts)
            do {
                try self.launch(runtime)
            } catch {
                self.fail(runtime, error)
            }
        }
    }

    @discardableResult
    func beginOperation(_ runtime: LocalToolRuntime) -> UUID {
        runtime.generation = UUID()
        runtime.statusGeneration = UUID()
        runtime.pendingStatusProbe = nil
        runtime.readinessWorkItem?.cancel()
        runtime.readinessWorkItem = nil
        return runtime.generation
    }

    func cancel(_ runtime: LocalToolRuntime) {
        guard contains(runtime), runtime.canCancel else { return }
        if runtime.supervisorPID != nil {
            stop(runtime)
        } else {
            beginOperation(runtime)
            runtime.state = .stopped
            runtime.statusText = "Cancelled"
            runtime.errorText = nil
        }
    }

    func restart(_ runtime: LocalToolRuntime) {
        guard contains(runtime) else { return }
        if runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) {
            stopExternalBB(runtime, restarting: true)
            return
        }
        guard runtime.canControlOwned else {
            runtime.errorText = "External services must be restarted in their original launcher."
            return
        }
        stop(runtime, restarting: true)
    }

    /// UI callers must confirm interruption before invoking this external path.
    func stop(_ runtime: LocalToolRuntime) {
        guard contains(runtime) else { return }
        if runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) {
            stopExternalBB(runtime, restarting: false)
            return
        }
        stop(runtime, restarting: false)
    }

    private func stop(_ runtime: LocalToolRuntime, restarting: Bool) {
        guard runtime.supervisorPID != nil, runtime.state != .stopping else {
            runtime.errorText = "Vaulty can stop only verified process groups it started."
            return
        }
        let generation = beginOperation(runtime)
        runtime.restartPending = restarting
        runtime.state = .stopping
        runtime.statusText = restarting ? "Restarting · waiting for exit and closed ports…" : "Stopping owned process…"
        runtime.errorText = nil
        requestStop(runtime, generation: generation, attempt: 0)
    }

    private func requestStop(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, let pid = runtime.supervisorPID else { return }
        if isVerifiedSupervisor(runtime) {
            guard kill(-pid, SIGTERM) == 0 else {
                fail(runtime, LocalToolError.stopRefused)
                return
            }
            scheduleStopVerification(runtime, generation: generation, attempt: 0)
        } else if ownedGroupsExited(runtime) {
            scheduleStopVerification(runtime, generation: generation, attempt: 0)
        } else if attempt < 20 {
            // Process.run returns before the supervisor establishes its group.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.requestStop(runtime, generation: generation, attempt: attempt + 1)
            }
        } else {
            fail(runtime, LocalToolError.stopRefused)
        }
    }
    func waitForReadiness(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, runtime.state == .starting else { return }
        let ports = runtime.definition.expectedPorts
        probePorts(ports) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .starting else { return }
            let ready = runtime.definition.primaryPort.map { states[$0] == true }
                ?? states.values.contains(true)
            if ready, self.isVerifiedSupervisor(runtime) {
                runtime.state = .runningOwned
                runtime.statusText = "Running · started by Vaulty"
                if self.opensWhenReady {
                    self.openPrimaryLink(runtime)
                }
                return
            }
            guard runtime.supervisorPID != nil,
                  self.isVerifiedSupervisor(runtime) || runtime.supervisorProcess?.isRunning == true else {
                self.fail(runtime, LocalToolError.launchFailed("The tool exited before its local link became ready."))
                return
            }
            guard attempt < 80 else {
                self.fail(runtime, LocalToolError.launchFailed("The tool did not become ready within 40 seconds. Check its Vaulty log."))
                return
            }
            let work = DispatchWorkItem { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.waitForReadiness(runtime, generation: generation, attempt: attempt + 1)
            }
            runtime.readinessWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
    private func scheduleStopVerification(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, runtime.state == .stopping else { return }
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .stopping else { return }
            let portsClosed = self.ownedPortsClosed(runtime, states: states)
            if self.ownedGroupsExited(runtime), portsClosed {
                self.clearOwnership(runtime)
                runtime.state = .stopped
                runtime.statusText = "Stopped by Vaulty"
                let restart = runtime.restartPending
                runtime.restartPending = false
                if restart { self.startOrOpen(runtime) }
                return
            }
            // Retry a graceful signal: the first Cancel may precede signal-source
            // installation. Never escalate or signal an unverified supervisor.
            if let pid = runtime.supervisorPID, self.isVerifiedSupervisor(runtime) {
                _ = kill(-pid, SIGTERM)
            }
            guard attempt < 40 else {
                self.fail(runtime, LocalToolError.launchFailed("Exit or port closure could not be verified. Ownership retained; no force-kill or relaunch. Try Stop or Restart."))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.scheduleStopVerification(runtime, generation: generation, attempt: attempt + 1)
            }
        }
    }

    func fail(_ runtime: LocalToolRuntime, _ error: Error) {
        beginOperation(runtime)
        runtime.restartPending = false
        runtime.state = .failed
        runtime.statusText = "Needs attention"
        runtime.errorText = error.localizedDescription
    }
}
