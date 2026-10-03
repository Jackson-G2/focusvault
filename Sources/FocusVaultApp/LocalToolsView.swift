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

                CaffeinateControl(controller: manager.caffeinate)
                Divider().overlay(Tideglass.line)

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
