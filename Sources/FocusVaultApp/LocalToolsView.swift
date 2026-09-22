import AppKit
import SwiftUI

struct LocalToolsWidget: View {
    @EnvironmentObject private var manager: LocalToolsManager

    var body: some View {
        GlassCard(cornerRadius: 24, tint: Tideglass.signal) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOOLS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(Tideglass.signal)
                        Text("Start and own local workspaces")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    Button {
                        manager.isPresentingAddTool = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                    .help("Add local tool")
                    .accessibilityLabel("Add local tool")
                    .accessibilityIdentifier("add-local-tool")

                    Button {
                        manager.isPresentingManager = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .help("Manage local tools")
                    .accessibilityLabel("Manage local tools")
                    .accessibilityIdentifier("manage-local-tools")
                }

                if manager.tools.isEmpty {
                    Text("Add a command, local link, and expected port.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                } else {
                    ForEach(manager.tools) { runtime in
                        LocalToolCompactRow(runtime: runtime)
                        if runtime.id != manager.tools.last?.id {
                            Divider().overlay(Tideglass.line)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $manager.isPresentingManager) {
            LocalToolsManagerView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $manager.isPresentingAddTool) {
            AddLocalToolView()
                .environmentObject(manager)
        }
    }
}

private struct LocalToolCompactRow: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @ObservedObject var runtime: LocalToolRuntime

    private var tint: Color {
        switch runtime.state {
        case .runningOwned: return Tideglass.seafoam
        case .runningExternal: return Tideglass.signal
        case .failed: return Tideglass.coral
        default: return Tideglass.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                GlassIcon(systemName: runtime.definition.iconName, tint: tint, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime.definition.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Text(runtime.errorText ?? runtime.statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(runtime.errorText == nil ? Tideglass.muted : Tideglass.coral)
                        .lineLimit(2)
                }

                Spacer(minLength: 3)

                if runtime.isOwned {
                    Button {
                        manager.stop(runtime)
                    } label: {
                        Label("End", systemImage: "stop.fill")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                    .help("End the process group started by Vaulty")
                    .accessibilityIdentifier("stop-tool-\(runtime.id.uuidString)")
                }

                Button {
                    manager.startOrOpen(runtime)
                } label: {
                    HStack(spacing: 5) {
                        if runtime.state == .checking || runtime.state == .starting {
                            ProgressView().controlSize(.small)
                        }
                        Text(runtime.actionTitle)
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: tint, isProminent: true))
                .disabled(runtime.state == .checking || runtime.state == .starting || runtime.state == .stopping)
                .accessibilityIdentifier("launch-tool-\(runtime.id.uuidString)")
            }

            if let link = runtime.definition.links.first {
                HStack(spacing: 7) {
                    Text(link.urlString)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 3)
                    Button {
                        manager.copy(link, for: runtime)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tideglass.signal)
                    .help("Copy local link")
                    .accessibilityLabel("Copy \(runtime.definition.name) link")
                    .accessibilityIdentifier("copy-tool-link-\(runtime.id.uuidString)")

                    if runtime.definition.updateMode != .none {
                        Button {
                            manager.checkForUpdates(runtime)
                        } label: {
                            if runtime.isCheckingUpdate {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Tideglass.signal)
                        .help("Check for updates")
                        .accessibilityLabel("Check \(runtime.definition.name) for updates")
                    }
                }
            }

            if let updateText = runtime.updateText {
                Text(updateText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .lineLimit(2)
            }
        }
    }
}

private struct LocalToolsManagerView: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @Environment(\.dismiss) private var dismiss
    @State private var removalError: String?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local tools")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text("Vaulty stops only process groups it started. Reused services stay untouched.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.tools) { runtime in
                            toolCard(runtime)
                        }
                    }
                }

                if let removalError {
                    Text(removalError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tideglass.coral)
                }

                Button {
                    manager.isPresentingManager = false
                    DispatchQueue.main.async { manager.isPresentingAddTool = true }
                } label: {
                    Label("Add tool", systemImage: "plus")
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 640, minHeight: 560)
    }

    private func toolCard(_ runtime: LocalToolRuntime) -> some View {
        GlassCard(cornerRadius: 18, tint: runtime.isRunning ? Tideglass.seafoam : Tideglass.muted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(runtime.definition.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(runtime.definition.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    if runtime.isOwned {
                        Button("End process") { manager.stop(runtime) }
                            .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                    }
                    Button(role: .destructive) {
                        do {
                            try manager.remove(runtime)
                            removalError = nil
                        } catch {
                            removalError = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                    .help("Remove tool from Vaulty")
                }

                ForEach(runtime.definition.links) { link in
                    HStack(spacing: 8) {
                        Text(link.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tideglass.ink)
                            .frame(width: 92, alignment: .leading)
                        Text(link.urlString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Tideglass.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button { manager.copy(link, for: runtime) } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        Button { manager.open(link, for: runtime) } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                    }
                }

                HStack {
                    Text("\(runtime.definition.executablePath) \(runtime.definition.arguments.joined(separator: " "))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Tideglass.muted.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if runtime.definition.updateMode != .none {
                        Button(runtime.isCheckingUpdate ? "Checking…" : "Check updates") {
                            manager.checkForUpdates(runtime)
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        .disabled(runtime.isCheckingUpdate)
                    }
                }

                if let updateText = runtime.updateText {
                    Text(updateText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                }
            }
            .padding(16)
        }
    }
}

private struct AddLocalToolView: View {
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
        let ports = portsText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
