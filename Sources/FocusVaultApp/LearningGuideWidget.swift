import SwiftUI
import VaultyCore

@MainActor
struct LearningGuideWidget: View {
    @EnvironmentObject private var learningGuide: VideoResearchModel
    @Binding var showingLearningGuide: Bool

    var body: some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.signal) {
            HStack(spacing: 12) {
                GlassIcon(systemName: "sparkles", tint: Tideglass.signal, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("Learn next")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        if learningGuide.isResearching {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Tideglass.signal)
                        }
                    }
                    Text(learningGuideSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if !learningGuide.isResearching {
                    Button {
                        if learningGuide.result != nil {
                            showingLearningGuide = true
                        } else {
                            learningGuide.research()
                        }
                    } label: {
                        Text(learningGuideActionTitle)
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                    .help(learningGuideActionTitle)
                    .accessibilityLabel(learningGuideActionTitle)
                    .accessibilityIdentifier("learning-guide-action")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var learningGuideSubtitle: String {
        if learningGuide.isResearching {
            return learningGuide.statusText
        }
        if let error = learningGuide.researchError {
            return error
        }
        if let result = learningGuide.result, !result.recommendations.isEmpty {
            return "\(result.recommendations.count) transcript-backed lesson\(result.recommendations.count == 1 ? "" : "s") ready"
        }
        if let diagnostic = learningGuide.result?.diagnostics.first {
            return diagnostic
        }
        return "Local agent history → useful video lessons"
    }

    private var learningGuideActionTitle: String {
        if let result = learningGuide.result {
            return result.recommendations.isEmpty ? "View" : "Open"
        }
        return learningGuide.researchError == nil ? "Research" : "Retry"
    }

}
