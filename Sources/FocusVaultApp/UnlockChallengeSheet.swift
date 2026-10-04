import SwiftUI
import VaultyCore

@MainActor
struct UnlockChallengeSheet: View {
    @ObservedObject var model: FocusVaultAppModel

    var body: some View {
            ZStack {
                if let kind = model.selectedUnlockChallengeKind {
                    switch kind {
                    case .gridShot:
                        GridShotChallengeView(
                            onComplete: model.completeUnlockChallenge,
                            onFailure: model.failUnlockChallenge,
                            onCancel: model.cancelUnlockChallenge,
                            onChooseAnother: model.returnToUnlockTaskHub,
                            isUnlocking: model.isBusy,
                            unlockError: model.unlockSubmissionError
                        )
                    case .typingSprint:
                        TypingSprintChallengeView(
                            onComplete: model.completeUnlockChallenge,
                            onFailure: model.failUnlockChallenge,
                            onCancel: model.cancelUnlockChallenge,
                            onChooseAnother: model.returnToUnlockTaskHub,
                            isUnlocking: model.isBusy,
                            unlockError: model.unlockSubmissionError
                        )
                    case .signalShift:
                        SignalShiftChallengeView(
                            onComplete: model.completeUnlockChallenge,
                            onLockedOut: model.failUnlockChallenge,
                            onCancel: model.cancelUnlockChallenge,
                            onChooseAnother: model.returnToUnlockTaskHub,
                            isUnlocking: model.isBusy,
                            unlockError: model.unlockSubmissionError
                        )
                    }
                } else {
                    UnlockTaskHubView(
                        onSelect: model.chooseUnlockChallenge,
                        onCancel: model.cancelUnlockChallenge
                    )
                }
            }
            .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
            .clipped()
            .transaction { transaction in
                transaction.animation = nil
            }
            .interactiveDismissDisabled(model.isBusy)
    }
}
