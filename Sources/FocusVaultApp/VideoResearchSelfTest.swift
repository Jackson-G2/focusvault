import Foundation

enum VideoResearchSelfTest {
    static func run(in directory: URL) throws {
        func recommendation(url: String, confidence: Double = 0.85) -> VideoRecommendation {
            VideoRecommendation(videoId: "fixture1234", topic: "Testing", whyHelpful: "fixture",
                                whatYouWillLearn: "fixture", notes: [], evidence: [], cautions: [],
                                confidence: confidence, title: "Fixture", channel: "Fixture",
                                url: url, length: "", published: "", transcript: "fixture")
        }
        let valid = recommendation(url: "https://www.youtube.com/watch?v=fixture1234")
        guard valid.watchURL != nil, valid.matchPercent == 85 else { throw Failure.invalid("valid video") }
        for raw in ["file:///tmp/fixture1234", "https://example.com/watch?v=fixture1234",
                    "https://www.youtube.com/watch?v=fixture1234&v=wrong",
                    "https://www.youtube.com/watch?v=wrong", "https://youtube.com.evil.test/watch?v=fixture1234",
                    "https://user:password@youtube.com/watch?v=fixture1234", "vaulty://unlock-youtube"] {
            guard recommendation(url: raw).watchURL == nil else { throw Failure.invalid("unsafe URL accepted: \(raw)") }
        }
        guard recommendation(url: valid.url, confidence: Double.greatestFiniteMagnitude).matchPercent == 100,
              recommendation(url: valid.url, confidence: -.infinity).matchPercent == 0,
              recommendation(url: valid.url, confidence: -1).matchPercent == 0 else {
            throw Failure.invalid("confidence was not safely clamped")
        }
        let fixture = directory.appendingPathComponent("video-result.json")
        let result = try VideoResearchStore.decode(VideoResearchResult.self, from: """
            {"schemaVersion":1,"status":"ok","topics":[],"recommendations":[],"diagnostics":[]}
            """)
        try VideoResearchStore.save(result, to: fixture)
        guard VideoResearchStore.loadResult(from: fixture) == result else { throw Failure.invalid("store round trip") }
        let model = VideoResearchModel(resultURL: fixture)
        model.ask(question: "  ", about: valid)
        guard model.answerVideoID == valid.id, model.answer == nil, model.answerError != nil, !model.isAsking else {
            throw Failure.invalid("empty Q&A must be scoped and must not run a researcher")
        }
        print("PASS: video URL allowlist, extreme confidence safety, local cache round trip and scoped empty Q&A")
    }

    private enum Failure: Error { case invalid(String) }
}
