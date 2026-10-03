import Darwin
import Foundation
import VaultyCore

@main
private struct VaultyCLI {
    private static var executableName: String {
        let name = URL(fileURLWithPath: CommandLine.arguments.first ?? "vaulty").lastPathComponent
        return name == "focusvault" || name == "focusvault-cli" ? "focusvault" : "vaulty"
    }

    static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "vaulty").lastPathComponent
        if executable.hasSuffix("native-host") {
            Darwin.exit(VaultyNativeMessagingHost.run())
        }

        let rawArguments = Array(CommandLine.arguments.dropFirst())
        do {
            if try CLIInternalCommands.run(rawArguments) {
                return
            }
            let arguments = try CLIArgumentParser.parse(rawArguments)
            try CLICommands.run(arguments, executableName: executableName)
        } catch {
            let message = "error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

}
