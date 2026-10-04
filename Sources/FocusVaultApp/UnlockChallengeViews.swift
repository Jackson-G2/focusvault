import SwiftUI
import VaultyCore

enum UnlockChallengeLayout {
    static let width: CGFloat = 760
    static let height: CGFloat = 760
}

enum UnlockGamePhase: Equatable {
    case ready
    case running
    case success
    case failed
}
