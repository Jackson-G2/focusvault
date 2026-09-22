import AppKit
import SwiftUI
import VaultyCore

@MainActor
enum VaultyVisualSnapshot {
    static func renderSignalShift(to outputPath: String) -> Int32 {
        render(
            SignalShiftChallengeView(
                onComplete: {},
                onLockedOut: {},
                onCancel: {},
                onChooseAnother: {},
                isUnlocking: false,
                unlockError: nil
            ),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderSignalShiftSuccess(to outputPath: String) -> Int32 {
        render(
            SignalShiftChallengeView(
                onComplete: {},
                onLockedOut: {},
                onCancel: {},
                onChooseAnother: {},
                isUnlocking: false,
                unlockError: nil,
                initialPhase: .completed,
                seed: 0x5106_0001
            ),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderUnlockHub(to outputPath: String) -> Int32 {
        render(
            UnlockTaskHubView(onSelect: { _ in }, onCancel: {}),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderGridShotSuccess(to outputPath: String) -> Int32 {
        render(
            GridShotChallengeView(
                onComplete: {},
                onFailure: {},
                onCancel: {},
                onChooseAnother: {},
                isUnlocking: false,
                unlockError: nil,
                initialPhase: .success
            ),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderTypingSprintSuccess(to outputPath: String) -> Int32 {
        render(
            TypingSprintChallengeView(
                onComplete: {},
                onFailure: {},
                onCancel: {},
                onChooseAnother: {},
                isUnlocking: false,
                unlockError: nil,
                initialPhase: .success
            ),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderGridShot(to outputPath: String) -> Int32 {
        render(
            GridShotChallengeView(
                onComplete: {},
                onFailure: {},
                onCancel: {},
                onChooseAnother: {},
                isUnlocking: false,
                unlockError: nil
            ),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderTypingSprint(to outputPath: String) -> Int32 {
        render(
            TypingSprintChallengeView(
                onComplete: {},
                onFailure: {},
                onCancel: {},
                onChooseAnother: {},
                isUnlocking: false,
                unlockError: nil
            ),
            width: UnlockChallengeLayout.width,
            height: UnlockChallengeLayout.height,
            to: outputPath
        )
    }

    static func renderDashboard(to outputPath: String) -> Int32 {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaulty-dashboard-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let hosts = directory.appendingPathComponent("hosts")
            try "# preview\n127.0.0.1 localhost\n".write(to: hosts, atomically: true, encoding: .utf8)
            _ = try FocusVaultBlocker(hostsFileURL: hosts).block()
            let guardStorage = YouTubeGuardStorage(
                stateURL: directory.appendingPathComponent("guard-state.json"),
                requestDirectoryURL: directory.appendingPathComponent("requests", isDirectory: true),
                responseDirectoryURL: directory.appendingPathComponent("responses", isDirectory: true)
            )
            let model = FocusVaultAppModel(
                hostsFileURL: hosts,
                privilegedAction: { _, completion in completion(.success("")) },
                guardRequest: { request, completion in
                    completion(.success(YouTubeGuardResponse(
                        requestID: request.id,
                        succeeded: true,
                        message: "preview",
                        completedAt: Date()
                    )))
                },
                guardInstalled: { true },
                adminUnlock: { completion in completion(.success(())) },
                guardStorage: guardStorage
            )
            let tracker = ProductivityTracker(storeURL: directory.appendingPathComponent("productivity.json"))
            let learningGuide = VideoResearchModel()
            let layoutSuite = "VaultyDashboardPreview.\(UUID().uuidString)"
            guard let layoutDefaults = UserDefaults(suiteName: layoutSuite) else {
                throw LocalToolError.launchFailed("Could not create isolated dashboard preview defaults.")
            }
            defer { layoutDefaults.removePersistentDomain(forName: layoutSuite) }
            let dashboardLayout = DashboardLayoutModel(
                defaults: layoutDefaults,
                key: "preview-canvas",
                legacyKey: "preview-legacy"
            )
            dashboardLayout.isEditing = true
            dashboardLayout.resize(.intention, width: 3, height: 1)
            dashboardLayout.resize(.taskClock, width: 3, height: 2)
            dashboardLayout.resize(.learningGuide, width: 3, height: 1)
            dashboardLayout.move(.learningGuide, toColumn: 0, row: 6)
            dashboardLayout.resize(.localTools, width: 4, height: 3)
            dashboardLayout.move(.localTools, toColumn: 0, row: 7)
            let tools = LocalToolsManager(
                catalog: LocalToolCatalog(fileURL: directory.appendingPathComponent("tools.json")),
                defaults: LocalToolDefinition.defaults(),
                supervisorExecutableURL: Bundle.main.executableURL,
                runDirectory: directory.appendingPathComponent("runs", isDirectory: true),
                logDirectory: directory.appendingPathComponent("logs", isDirectory: true),
                startsStatusTimer: false,
                opensWhenReady: false,
                openURL: { _ in true }
            )
            let root = FocusVaultDashboard(dashboardLayout: dashboardLayout)
                .environmentObject(model)
                .environmentObject(tracker)
                .environmentObject(learningGuide)
                .environmentObject(tools)
            return render(root, width: 1020, height: 1900, to: outputPath)
        } catch {
            fputs("Dashboard preview failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    static func renderTools(to outputPath: String) -> Int32 {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaulty-tools-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let manager = LocalToolsManager(
                catalog: LocalToolCatalog(fileURL: directory.appendingPathComponent("tools.json")),
                defaults: LocalToolDefinition.defaults(),
                supervisorExecutableURL: Bundle.main.executableURL,
                runDirectory: directory.appendingPathComponent("runs", isDirectory: true),
                logDirectory: directory.appendingPathComponent("logs", isDirectory: true),
                startsStatusTimer: false,
                opensWhenReady: false,
                openURL: { _ in true }
            )
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))

            let root = ZStack {
                AppBackground()
                LocalToolsWidget()
                    .environmentObject(manager)
                    .frame(width: 286)
                    .padding(28)
            }
            .preferredColorScheme(.dark)
            .frame(width: 342, height: 700)

            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: 342, height: 700)
            hosting.layoutSubtreeIfNeeded()
            guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw LocalToolError.launchFailed("Could not allocate the tools preview bitmap.")
            }
            hosting.cacheDisplay(in: hosting.bounds, to: representation)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                throw LocalToolError.launchFailed("Could not encode the tools preview PNG.")
            }
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            print("Created tools preview: \(outputPath)")
            return 0
        } catch {
            fputs("Tools preview failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func render<Content: View>(
        _ content: Content,
        width: CGFloat,
        height: CGFloat,
        to outputPath: String
    ) -> Int32 {
        let root = content
            .preferredColorScheme(.dark)
            .frame(width: width, height: height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("Preview bitmap allocation failed.\n", stderr)
            return 1
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            fputs("Preview PNG encoding failed.\n", stderr)
            return 1
        }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            print("Created preview: \(outputPath)")
            return 0
        } catch {
            fputs("Preview write failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
