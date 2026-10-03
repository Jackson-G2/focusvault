import Foundation

enum FocusVaultAppError: LocalizedError {
    case bundledHelperMissing
    case commandFailed(String)
    case sessionAlreadyActive
    case invalidSessionDuration
    case busy
    case unlockNotApplied
    case lockNotApplied
    case guardNotInstalled
    case shortFormNotApplied

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "The bundled Vaulty helper was not found. Build the app with scripts/package-app.sh."
        case let .commandFailed(message):
            return message
        case .sessionAlreadyActive:
            return "A task clock is already running."
        case .invalidSessionDuration:
            return "Choose a task estimate between 1 and 240 minutes."
        case .busy:
            return "Vaulty is already working on that change."
        case .unlockNotApplied:
            return "The guard answered, but YouTube is still locked. Close this window and try the unlock again."
        case .lockNotApplied:
            return "The guard answered, but the YouTube lock could not be verified. Try again."
        case .guardNotInstalled:
            return "Vaulty could not verify its guard installation. Try the one-time setup again."
        case .shortFormNotApplied:
            return "The short-form change could not be verified. Refresh its status and try again."
        }
    }
}
