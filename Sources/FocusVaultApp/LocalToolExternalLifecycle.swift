import Foundation

// The explicit, confirmed exception for the unchanged default external bb.
extension LocalToolsManager {
    func stopExternalBB(_ runtime: LocalToolRuntime, restarting: Bool) {
        guard runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) else { return }
        let generation = beginOperation(runtime)
        runtime.restartPending = restarting
        runtime.reusedPorts = []
        runtime.state = .stopping
        runtime.statusText = restarting ? "Restarting bb…" : "Stopping bb…"
        runtime.errorText = nil
        let definition = runtime.definition
        let stopCommand = externalBBStop
        DispatchQueue.global(qos: .utility).async { [weak self, weak runtime] in
            let result = Result { try stopCommand(definition) }
            DispatchQueue.main.async {
                guard let self, let runtime, runtime.generation == generation, runtime.state == .stopping else { return }
                switch result {
                case .success:
                    self.verifyExternalBBStopped(runtime, generation: generation, attempt: 0)
                case let .failure(error):
                    runtime.restartPending = false
                    // Retain external recovery controls instead of pretending to own bb.
                    runtime.state = .runningExternal
                    runtime.statusText = "External bb · stop failed"
                    runtime.errorText = error.localizedDescription
                }
            }
        }
    }

    private func verifyExternalBBStopped(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, runtime.state == .stopping else { return }
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .stopping else { return }
            if runtime.definition.expectedPorts.allSatisfy({ states[$0] == false }) {
                let restart = runtime.restartPending
                runtime.restartPending = false
                runtime.state = .stopped
                runtime.statusText = "bb stopped"
                if restart { self.startOrOpen(runtime) }
                return
            }
            guard attempt < 40 else {
                runtime.restartPending = false
                runtime.state = .runningExternal
                runtime.statusText = "External bb · port still open"
                runtime.errorText = "bb's port did not close after its stop command. No new instance was launched. Retry Stop or check its original launcher."
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.verifyExternalBBStopped(runtime, generation: generation, attempt: attempt + 1)
            }
        }
    }
}
