import SwiftUI

@MainActor
struct FilesFoldersWidget: View {
    var body: some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.muted) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Files & Folders")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)

                MemoFilesButton()
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
