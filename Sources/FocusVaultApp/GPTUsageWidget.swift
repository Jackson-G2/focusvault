import SwiftUI
import Combine

struct GPTUsageSnapshot: Decodable {
    struct Reset: Decodable, Identifiable {
        let id: String
        let expiresAt: Double?
    }
    let usedPercent: Double?
    let weeklyResetsAt: Double?
    let availableCount: Int?
    let detailsAvailable: Bool
    let resets: [Reset]
}

@MainActor
final class GPTUsageModel: ObservableObject {
    @Published private(set) var snapshot: GPTUsageSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    private var activeTask: CapturedProcessTask?

    deinit { activeTask?.cancel() }

    func refresh() {
        guard !isRefreshing else { return }
        let script = Bundle.main.url(forResource: "gpt_usage", withExtension: "py", subdirectory: "ResearchAgent")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ResearchAgent/gpt_usage.py")
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            error = "The usage helper is missing. Rebuild Vaulty."
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
        var environment = ProcessInfo.processInfo.environment
        let localBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", localBin, environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        let task = CapturedProcessTask(process)
        activeTask = task
        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try task.run() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeTask = nil
                self.isRefreshing = false
                do {
                    let output = try result.get()
                    guard output.exitStatus == 0 else {
                        self.error = output.stderr.isEmpty ? "Could not refresh usage." : output.stderr
                        return
                    }
                    self.snapshot = try JSONDecoder().decode(GPTUsageSnapshot.self, from: Data(output.stdout.utf8))
                    self.updatedAt = Date()
                    self.error = nil
                } catch {
                    self.error = "Could not refresh usage. Try again."
                }
            }
        }
    }
}

@MainActor
struct GPTUsageWidget: View {
    @StateObject private var model = GPTUsageModel()
    var startsServices = true
    private static let brisbane: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: "Australia/Brisbane")
        formatter.dateFormat = "EEE d MMM · h:mm a"
        return formatter
    }()

    var body: some View {
        GlassCard(cornerRadius: 26, tint: Tideglass.seafoam) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("GPT USAGE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Tideglass.seafoam)
                    Spacer()
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRefreshing)
                    .help("Refresh ChatGPT usage")
                    .accessibilityIdentifier("refresh-gpt-usage")
                }
                if let snapshot = model.snapshot {
                    if let usedPercent = snapshot.usedPercent {
                        let percent = max(0, min(100, 100 - usedPercent))
                        HStack {
                            Text("Weekly allowance")
                            Spacer()
                            Text("\(Int(percent.rounded()))% left")
                                .monospacedDigit()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        ProgressView(value: percent, total: 100)
                            .tint(Tideglass.seafoam)
                            .accessibilityLabel("Weekly GPT allowance")
                            .accessibilityValue("\(Int(percent.rounded())) percent remaining")
                        if let time = snapshot.weeklyResetsAt {
                            Text("Refreshes \(Self.format(time))")
                                .font(.system(size: 11))
                                .foregroundStyle(Tideglass.muted)
                        }
                    } else {
                        Text("Weekly usage is unavailable for this account.")
                            .font(.system(size: 12))
                    }
                    Divider().overlay(Tideglass.line)
                    Text("SAVED RESETS\(snapshot.availableCount.map { " · \($0)" } ?? "")")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Tideglass.seafoam)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(snapshot.resets) { reset in
                                    HStack(alignment: .firstTextBaseline) {
                                        Image(systemName: "arrow.counterclockwise.circle")
                                        if let expiry = reset.expiresAt {
                                            Text(expiry <= context.date.timeIntervalSince1970
                                                ? "Expired · \(Self.format(expiry))"
                                                : "Expires \(Self.format(expiry))")
                                        } else {
                                            Text("Expiry unavailable")
                                        }
                                    }
                                }
                                if !snapshot.detailsAvailable {
                                    Text("Exact expiry times are unavailable.")
                                } else if snapshot.resets.isEmpty {
                                    Text("No saved resets available.")
                                }
                                if let count = snapshot.availableCount, count > snapshot.resets.count, snapshot.detailsAvailable {
                                    Text("Expiry details shown for \(snapshot.resets.count) of \(count) resets.")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12))
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Text(model.isRefreshing ? "Loading your usage…" : "Connect through your signed-in Codex account.")
                        .font(.system(size: 13))
                    Spacer()
                }
                if let error = model.error {
                    Text(error + (model.snapshot == nil ? "" : " Showing the last successful refresh."))
                        .font(.system(size: 11))
                        .foregroundStyle(Tideglass.muted)
                }
                Text("Brisbane · AEST\(model.updatedAt.map { " · Updated " + $0.formatted(date: .omitted, time: .shortened) } ?? "")")
                    .font(.system(size: 10))
                    .foregroundStyle(Tideglass.muted)
            }
            .foregroundStyle(Tideglass.ink)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            guard startsServices else { return }
            while !Task.isCancelled {
                model.refresh()
                do { try await Task.sleep(nanoseconds: 300_000_000_000) }
                catch { return }
            }
        }
    }

    private static func format(_ timestamp: Double) -> String {
        brisbane.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
