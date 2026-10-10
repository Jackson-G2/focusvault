import SwiftUI
import VaultyCore

@MainActor
struct FocusVaultDashboard: View {
    @EnvironmentObject private var model: FocusVaultAppModel
    @EnvironmentObject private var tracker: ProductivityTracker
    @EnvironmentObject private var learningGuide: VideoResearchModel
    @EnvironmentObject private var toolsManager: LocalToolsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var showingLearningGuide = false
    @State private var showingSleepCalculator = false
    @StateObject private var dashboardLayout: DashboardLayoutModel
    private let startsServices: Bool

    init() {
        startsServices = true
        _dashboardLayout = StateObject(wrappedValue: DashboardLayoutModel())
    }

    init(dashboardLayout: DashboardLayoutModel, startsServices: Bool = true) {
        self.startsServices = startsServices
        _dashboardLayout = StateObject(wrappedValue: dashboardLayout)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                        .padding(.bottom, 24)

                    DashboardWidgetCanvas(
                        model: dashboardLayout,
                        reduceMotion: reduceMotion
                    ) { kind in
                        dashboardWidget(kind)
                    }

                    if let error = model.lastError {
                        DashboardErrorBanner(error: error, onDismiss: model.clearError)
                            .padding(.top, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 28)
                .frame(maxWidth: 1020)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if startsServices {
                model.refresh()
                tracker.start()
                toolsManager.caffeinate.restoreEnabledState()
            }
            hasAppeared = true
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: model.lastError)
        .sheet(isPresented: $showingLearningGuide) {
            VideoRecommendationsView()
                .environmentObject(learningGuide)
        }
        .sheet(isPresented: $showingSleepCalculator) {
            SleepCalculatorView()
        }
        .sheet(
            item: Binding(
                get: { model.unlockChallengeRequest },
                set: { request in
                    if request == nil, model.unlockChallengeRequest != nil {
                        model.cancelUnlockChallenge()
                    }
                }
            )
        ) { _ in
            UnlockChallengeSheet(model: model)
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            Spacer()

            if dashboardLayout.isEditing {
                Button("Reset") {
                    withAnimation { dashboardLayout.reset() }
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                .help("Restore the default widget positions and sizes")
                .accessibilityIdentifier("reset-dashboard-widgets")
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    dashboardLayout.isEditing.toggle()
                }
            } label: {
                Label(
                    dashboardLayout.isEditing ? "Done" : "Arrange",
                    systemImage: dashboardLayout.isEditing ? "checkmark" : "square.grid.2x2"
                )
            }
            .buttonStyle(GlassButtonStyle(
                tint: dashboardLayout.isEditing ? Tideglass.signal : Tideglass.muted,
                isProminent: dashboardLayout.isEditing
            ))
            .help(dashboardLayout.isEditing ? "Finish arranging and resizing widgets" : "Move and resize dashboard widgets")
            .accessibilityIdentifier("arrange-dashboard-widgets")

            GlassPill(
                title: model.isBusy ? "Working" : (model.isAnyVaultBlocked ? "Vaulted" : "Open"),
                lockState: model.isAnyVaultBlocked ? .locked : .open,
                tint: model.isBusy ? Tideglass.signal : (model.isAnyVaultBlocked ? Tideglass.seafoam : Tideglass.muted)
            )
        }
        .opacity(hasAppeared || reduceMotion || !startsServices ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion || !startsServices ? 0 : -6)
    }

    @ViewBuilder
    private func dashboardWidget(_ kind: DashboardWidgetKind) -> some View {
        switch kind {
        case .intention:
            IntentionWidget()
        case .taskClock:
            TaskClockWidget()
        case .youtubeProtection:
            YouTubeProtectionWidget()
        case .shortFormProtection:
            ShortFormProtectionWidget()
        case .localTools:
            LocalToolsWidget()
        case .sleepCalculator:
            SleepCalculatorWidget(showingSleepCalculator: $showingSleepCalculator)
        case .learningGuide:
            LearningGuideWidget(showingLearningGuide: $showingLearningGuide)
        case .gptUsage:
            GPTUsageWidget(startsServices: startsServices)
        case .filesFolders:
            FilesFoldersWidget()
        case .rhythm:
            EmptyView() // Retired; old saved placements are removed on load.
        }
    }

}
