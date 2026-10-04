import Foundation

public enum UnlockChallengeKind: String, Codable, CaseIterable, Equatable, Sendable {
    case signalShift
    case gridShot
    case typingSprint

    /// Challenges used for real unlocks. Signal Shift remains available in the
    /// codebase for reference, but is intentionally not a required gate.
    public static let requiredRotation: [UnlockChallengeKind] = [
        .gridShot,
        .typingSprint
    ]

    /// Tasks shown in the user-selectable unlock hub. Signal Shift is optional;
    /// it is never selected automatically or required for access.
    public static let taskHubChoices: [UnlockChallengeKind] = [
        .gridShot,
        .typingSprint,
        .signalShift
    ]

    public var displayName: String {
        switch self {
        case .signalShift: return "Signal Shift"
        case .gridShot: return "Grid Shot"
        case .typingSprint: return "Typing Sprint"
        }
    }
}
