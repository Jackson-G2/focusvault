import Foundation

extension LocalToolsManager {
    func refreshStatus(_ runtime: LocalToolRuntime) {
        refreshStatuses(only: runtime.id, recoveringReadyService: true)
    }

    func refreshStatuses(only id: UUID? = nil, recoveringReadyService: Bool = false) {
        for runtime in tools where (id == nil || runtime.id == id)
            && !runtime.canCancel && runtime.state != .stopping && runtime.pendingStatusProbe == nil {
            let generation = runtime.generation
            let statusGeneration = UUID()
            runtime.statusGeneration = statusGeneration
            runtime.pendingStatusProbe = statusGeneration
            probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
                guard let self, let runtime,
                      runtime.generation == generation, runtime.statusGeneration == statusGeneration else { return }
                runtime.pendingStatusProbe = nil
                guard self.contains(runtime), !runtime.canCancel, runtime.state != .stopping else { return }
                guard runtime.definition.expectedPorts.allSatisfy({ states[$0] != nil }) else { return }
                let primaryOpen = runtime.definition.primaryPort.map { states[$0] == true }
                    ?? states.values.contains(true)
                if runtime.supervisorPID != nil {
                    if self.ownedGroupsExited(runtime) {
                        guard self.ownedPortsClosed(runtime, states: states) else {
                            runtime.state = .failed
                            runtime.statusText = "Owned ports still open · Stop or Restart"
                            return // Retain ownership even after a stop timeout.
                        }
                        self.clearOwnership(runtime)
                    } else {
                        guard runtime.state != .failed || (recoveringReadyService && primaryOpen) else { return }
                        guard self.isVerifiedSupervisor(runtime) else {
                            runtime.state = .failed
                            runtime.statusText = "Ownership retained · process identity not verified"
                            runtime.errorText = LocalToolError.stopRefused.localizedDescription
                            return
                        }
                        runtime.state = primaryOpen ? .runningOwned : .failed
                        runtime.statusText = primaryOpen ? "Running · started by Vaulty" : "Owned service not ready · Stop or Restart"
                        if primaryOpen { runtime.errorText = nil }
                        return
                    }
                }
                if primaryOpen {
                    runtime.state = .runningExternal
                    runtime.statusText = BBExternalLifecycle.matches(runtime.definition)
                    ? "External bb · restart available"
                    : "External · use its original launcher"
                } else if runtime.state != .failed {
                    runtime.state = .stopped
                    runtime.statusText = "Stopped"
                }
            }
        }
    }
}
