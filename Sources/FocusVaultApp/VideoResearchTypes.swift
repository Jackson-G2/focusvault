import Foundation

struct LearningTopic: Codable, Identifiable, Equatable {
    let topic: String
    let goal: String
    let reason: String
    let searchQueries: [String]

    var id: String { topic }
}

struct VideoResearchAudit: Codable, Equatable {
    let databasesScanned: Int
    let profilesSeen: Int
    let sessionsIncluded: Int
    let sourceCounts: [String: Int]
    let redaction: String
    let skippedDatabaseCount: Int
}

struct VideoRecommendation: Codable, Identifiable, Equatable {
    let videoId: String
    let topic: String
    let whyHelpful: String
    let whatYouWillLearn: String
    let notes: [String]
    let evidence: [String]
    let cautions: [String]
    let confidence: Double
    let title: String
    let channel: String
    let url: String
    let length: String
    let published: String
    let transcript: String

    var id: String { videoId }

    var matchPercent: Int {
        guard confidence.isFinite else { return 0 }
        return Int((min(1, max(0, confidence)) * 100).rounded())
    }

    /// Cached/model-authored URLs may open only the declared YouTube video,
    /// never local files, custom protocol handlers or unrelated websites.
    var watchURL: URL? {
        guard videoId.utf8.count == 11, videoId.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                || byte == 45 || byte == 95
        }) else { return nil }
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased() else { return nil }
        if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host),
           components.path == "/watch",
           components.queryItems?.filter({ $0.name == "v" }).count == 1,
           components.queryItems?.first(where: { $0.name == "v" })?.value == videoId {
            return components.url
        }
        if host == "youtu.be", components.path == "/" + videoId { return components.url }
        return nil
    }
}

struct VideoResearchResult: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let model: String
    let status: String
    let sessionAudit: VideoResearchAudit?
    let topics: [LearningTopic]
    let recommendations: [VideoRecommendation]
    let diagnostics: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "error"
        sessionAudit = try container.decodeIfPresent(VideoResearchAudit.self, forKey: .sessionAudit)
        topics = try container.decodeIfPresent([LearningTopic].self, forKey: .topics) ?? []
        recommendations = try container.decodeIfPresent([VideoRecommendation].self, forKey: .recommendations) ?? []
        diagnostics = try container.decodeIfPresent([String].self, forKey: .diagnostics) ?? []
    }
}

struct VideoAnswerPayload: Decodable {
    let status: String
    let videoId: String?
    let answer: String
    let model: String?
}

enum VideoResearchState: Equatable {
    case idle
    case researching
    case ready
    case failed(String)
}

enum VideoResearchError: LocalizedError {
    case helperMissing
    case pythonMissing
    case emptyOutput
    case invalidResult
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "The bundled learning researcher was not found. Rebuild Vaulty with scripts/package-app.sh."
        case .pythonMissing:
            return "Python 3 was not found. Install Python 3 to run the learning researcher."
        case .emptyOutput:
            return "The learning researcher returned no result."
        case .invalidResult:
            return "The learning researcher returned an unreadable result."
        case let .processFailed(message):
            return message
        }
    }
}
