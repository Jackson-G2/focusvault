import SwiftUI

struct CaffeinateControl: View {
    @ObservedObject var controller: CaffeinateController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { controller.isActive }, set: { controller.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stay Awake")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tideglass.ink)
                    Text(controller.isStopping ? "Turning off…" : "caffeinate -dims")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Tideglass.muted)
                }
            }
            .toggleStyle(.switch)
            .tint(Tideglass.signal)
            .disabled(controller.isStopping)
            .help("Keeps the display and Mac awake while Vaulty is open, and remembers your choice after relaunch. Does not prevent lid-close sleep; -s requires AC power.")
            .accessibilityIdentifier("toggle-stay-awake")
            if let error = controller.errorText {
                Text(error).font(.system(size: 10)).foregroundStyle(Tideglass.coral)
            }
        }
    }
}
