import AppKit
import SwiftUI

/// Opens Apple's existing recording storage without creating or changing files.
struct MemoFilesButton: View {
    @State private var openingError: String?

    private var recordingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
    }

    var body: some View {
        Button {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: recordingsURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                openingError = "The Voice Memos recordings folder is unavailable. Open Voice Memos and make sure your recordings have synced to this Mac."
                return
            }
            guard NSWorkspace.shared.open(recordingsURL) else {
                openingError = "Finder could not open the Voice Memos recordings folder."
                return
            }
        } label: {
            Label("Memo Files", systemImage: "folder")
        }
        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
        .help("Open the Voice Memos recordings folder in Finder")
        .accessibilityIdentifier("open-memo-files")
        .alert("Couldn’t open memo files", isPresented: Binding(
            get: { openingError != nil },
            set: { if !$0 { openingError = nil } }
        )) {
            Button("OK", role: .cancel) { openingError = nil }
        } message: {
            Text(openingError ?? "")
        }
    }
}
