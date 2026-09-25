import SwiftUI

struct VideoRecommendationsView: View {
    @EnvironmentObject private var research: VideoResearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideoID: String?
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 22)

            if let result = research.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        topicSummary(result.topics)

                        if result.recommendations.isEmpty {
                            emptyRecommendations(result)
                        } else {
                            ForEach(result.recommendations) { recommendation in
                                VideoRecommendationCard(
                                    recommendation: recommendation,
                                    isSelected: selectedVideoID == recommendation.id,
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedVideoID = recommendation.id
                                        }
                                    },
                                    onOpen: {
                                        research.openVideo(recommendation)
                                    }
                                )
                            }

                            if let selectedVideo {
                                VideoQuestionPanel(
                                    recommendation: selectedVideo,
                                    question: $question
                                )
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            } else if let error = research.researchError {
                errorState(error)
            } else {
                ProgressView("Preparing your learning guide…")
                    .tint(Tideglass.signal)
                    .foregroundStyle(Tideglass.muted)
            }
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 620)
        .background(Tideglass.canvas)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Learn next")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                if let result = research.result {
                    Text("Based on \(result.sessionAudit?.sessionsIncluded ?? 0) local agent sessions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                }
            }
            Spacer()
            Button(research.isResearching ? "Refreshing…" : "Refresh") {
                research.research()
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
            .disabled(research.isResearching)
            .help("Run the researcher again")

            Button("Close") {
                dismiss()
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
        }
    }

    private func topicSummary(_ topics: [LearningTopic]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your current threads")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Tideglass.seafoam)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.topic)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(topic.goal)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Tideglass.seafoam)
                            .lineLimit(2)
                        Text(topic.reason)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Tideglass.elevated.opacity(0.46))
                    }
                }
            }
        }
    }

    private func emptyRecommendations(_ result: VideoResearchResult) -> some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.signal) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No lesson videos yet.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                Text(result.diagnostics.first ?? "The researcher needs a reachable transcript before it can recommend a video.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)

                let queries = result.topics.flatMap { $0.searchQueries }
                if !queries.isEmpty {
                    Text("Suggested searches")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Tideglass.seafoam)
                    ForEach(Array(queries.enumerated()), id: \.offset) { item in
                        Text("\u{2022} \(item.element)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
    }

    private func errorState(_ error: String) -> some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.coral) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Tideglass.coral)
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tideglass.ink)
            }
            .padding(20)
        }
    }

    private var selectedVideo: VideoRecommendation? {
        guard let selectedVideoID else { return nil }
        return research.result?.recommendations.first(where: { $0.id == selectedVideoID })
    }
}

private struct VideoRecommendationCard: View {
    let recommendation: VideoRecommendation
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 22, tint: isSelected ? Tideglass.signal : Tideglass.seafoam) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recommendation.title)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                            .lineLimit(3)
                        Text([recommendation.channel, recommendation.length, recommendation.published].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(recommendation.topic)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.seafoam)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                        Text("\(Int((recommendation.confidence * 100).rounded()))% match")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.muted)
                            .monospacedDigit()
                    }
                }

                Text(recommendation.whyHelpful)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tideglass.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("You’ll learn")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Tideglass.seafoam)
                    Text(recommendation.whatYouWillLearn)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !recommendation.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Notes")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.seafoam)
                        ForEach(Array(recommendation.notes.enumerated()), id: \.offset) { item in
                            Text("\u{2022} \(item.element)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Tideglass.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !recommendation.cautions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keep in mind")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.coral)
                        ForEach(Array(recommendation.cautions.enumerated()), id: \.offset) { item in
                            Text("\u{2022} \(item.element)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Tideglass.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let evidence = recommendation.evidence.first {
                    Text("Transcript evidence: \(evidence)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 9) {
                    Button(isSelected ? "Ask below" : "Ask about it") {
                        onSelect()
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: isSelected))

                    Button("Watch") {
                        onOpen()
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                }
            }
            .padding(22)
        }
    }
}

private struct VideoQuestionPanel: View {
    @EnvironmentObject private var research: VideoResearchModel
    let recommendation: VideoRecommendation
    @Binding var question: String

    var body: some View {
        GlassCard(cornerRadius: 22, tint: Tideglass.signal) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ask about this lesson")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text("Answers stay grounded in this video’s transcript.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    Text(recommendation.channel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    TextField("What should I understand better?", text: $question)
                        .font(.system(size: 13, weight: .medium))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Tideglass.canvas.opacity(0.55))
                        }

                    Button {
                        research.ask(question: question, about: recommendation)
                    } label: {
                        if research.isAsking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Ask")
                        }
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                    .disabled(research.isAsking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let answer = research.answer {
                    Text(answer)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tideglass.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = research.answerError {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.coral)
                }
            }
            .padding(20)
        }
    }
}
