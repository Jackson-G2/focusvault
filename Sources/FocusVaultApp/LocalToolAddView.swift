import AppKit
import SwiftUI

struct AddLocalToolView: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var detail = ""
    @State private var workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var executablePath = "/usr/bin/env"
    @State private var argumentsText = ""
    @State private var urlText = "http://localhost:"
    @State private var portsText = ""
    @State private var allowsPartialReuse = false
    @State private var updateMode: LocalToolUpdateMode = .none
    @State private var updateIdentifier = ""
    @State private var errorText: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text("Add local tool")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    }

                    field("Name", text: $name, placeholder: "My local dashboard")
                    field("Description", text: $detail, placeholder: "What this tool opens")

                    pathField(
                        "Working directory",
                        text: $workingDirectory,
                        chooseDirectory: true
                    )
                    pathField(
                        "Executable",
                        text: $executablePath,
                        chooseDirectory: false
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Arguments · one per line")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tideglass.muted)
                        TextEditor(text: $argumentsText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 82)
                            .padding(8)
                            .background(Tideglass.elevated.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                    }

                    field("Primary local link", text: $urlText, placeholder: "http://localhost:3000")
                    field("Expected ports", text: $portsText, placeholder: "3000, 3001")
                    Toggle("Launcher can safely reuse partially running ports", isOn: $allowsPartialReuse)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tideglass.ink)

                    Picker("Update check", selection: $updateMode) {
                        ForEach(LocalToolUpdateMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    if updateMode == .npmPackage {
                        field("npm package", text: $updateIdentifier, placeholder: "package-name")
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.coral)
                    }

                    Button {
                        save()
                    } label: {
                        Text("Add tool")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                    .accessibilityIdentifier("save-local-tool")
                }
                .padding(28)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 620, minHeight: 680)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tideglass.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Tideglass.elevated.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Tideglass.ink)
        }
    }

    private func pathField(
        _ title: String,
        text: Binding<String>,
        chooseDirectory: Bool
    ) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            field(title, text: text, placeholder: chooseDirectory ? "/path/to/project" : "/usr/bin/env")
            Button("Choose") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = chooseDirectory
                panel.canChooseFiles = !chooseDirectory
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    text.wrappedValue = url.path
                }
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
        }
    }

    private func save() {
        let ports: [Int]
        do {
            ports = try LocalToolDefinition.parsePorts(portsText)
        } catch {
            errorText = error.localizedDescription
            return
        }
        let arguments = argumentsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let definition = LocalToolDefinition(
            name: name,
            detail: detail,
            workingDirectory: workingDirectory,
            executablePath: executablePath,
            arguments: arguments,
            links: [LocalToolLink(name: name.isEmpty ? "Local tool" : name, urlString: urlText)],
            expectedPorts: ports,
            primaryPort: ports.first,
            allowsPartialReuse: allowsPartialReuse,
            updateMode: updateMode,
            updateIdentifier: updateIdentifier
        )

        do {
            try manager.add(definition)
            errorText = nil
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
