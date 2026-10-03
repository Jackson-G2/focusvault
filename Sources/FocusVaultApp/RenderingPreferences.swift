import SwiftUI

private struct MaterialSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Hardware-backed native glass cannot be captured through an unattached
    /// NSHostingView bitmap. Diagnostic snapshots use the existing material
    /// fallback; normal app windows keep native glass on supported SDK/runtime.
    var vaultyMaterialSnapshot: Bool {
        get { self[MaterialSnapshotKey.self] }
        set { self[MaterialSnapshotKey.self] = newValue }
    }
}
