import AppKit
import Foundation
import SwiftUI

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

private struct VideoAnswerPayload: Decodable {
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

private enum VideoResearchError: LocalizedError {
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

final class VideoResearchModel: ObservableObject {
    @Published private(set) var state: VideoResearchState = .idle
    @Published private(set) var result: VideoResearchResult?
    @Published private(set) var answer: String?
    @Published private(set) var answerError: String?
    @Published private(set) var isAsking = false

    private var activeProcess: Process?
    private let resultURL: URL

    init() {
        resultURL = Self.defaultResultURL()
        result = Self.loadResult(from: resultURL)
        if result != nil {
            state = .ready
        }
    }

    deinit {
        activeProcess?.terminate()
    }

    var isResearching: Bool {
        state == .researching
    }

    var researchError: String? {
        guard case let .failed(message) = state else { return nil }
        return message
    }

    var statusText: String {
        switch state {
        case .idle:
            return ""
        case .researching:
            return "Auditing your agent history and researching lessons…"
        case .ready:
            return ""
        case .failed:
            return ""
        }
    }

    func research() {
        guard activeProcess == nil else { return }

        answer = nil
        answerError = nil
        state = .researching
        runHelper(arguments: ["--mode", "recommend"]) { [weak self] output in
            guard let self else { return }
            switch output {
            case let .success(output):
                do {
                    let decoded = try Self.decode(VideoResearchResult.self, from: output)
                    self.result = decoded
                    try Self.save(decoded, to: self.resultURL)
                    if decoded.status == "error" {
                        self.state = .failed(decoded.diagnostics.first ?? "The learning researcher could not complete.")
                    } else {
                        self.state = .ready
                    }
                } catch {
                    self.state = .failed(error.localizedDescription)
                }
            case let .failure(error):
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func ask(question: String, about recommendation: VideoRecommendation) {
        guard activeProcess == nil else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            answerError = "Ask a question about the selected video."
            return
        }

        answer = nil
        answerError = nil
        isAsking = true
        runHelper(
            arguments: [
                "--mode", "ask",
                "--result-file", resultURL.path,
                "--video-id", recommendation.videoId,
                "--question", trimmed
            ]
        ) { [weak self] output in
            guard let self else { return }
            self.isAsking = false
            switch output {
            case let .success(output):
                do {
                    let payload = try Self.decode(VideoAnswerPayload.self, from: output)
                    if payload.status == "ok" {
                        self.answer = payload.answer
                    } else {
                        self.answerError = payload.answer
                    }
                } catch {
                    self.answerError = error.localizedDescription
                }
            case let .failure(error):
                self.answerError = error.localizedDescription
            }
        }
    }

    func openVideo(_ recommendation: VideoRecommendation) {
        guard let url = URL(string: recommendation.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func runHelper(
        arguments: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        do {
            let script = try locateScript()
            let python = try locatePython()
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script.path] + arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["NO_COLOR"] = "1"
            process.environment = environment
            activeProcess = process

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdout = String(
                        data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let stderr = String(
                        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    DispatchQueue.main.async {
                        self?.activeProcess = nil
                        if !stdout.isEmpty {
                            completion(.success(stdout))
                        } else if !stderr.isEmpty {
                            completion(.failure(VideoResearchError.processFailed(stderr)))
                        } else {
                            completion(.failure(VideoResearchError.emptyOutput))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.activeProcess = nil
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    private func locateScript() throws -> URL {
        if let bundled = Bundle.main.url(
            forResource: "recommend",
            withExtension: "py",
            subdirectory: "ResearchAgent"
        ) {
            return bundled
        }

        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ResearchAgent/recommend.py")
        guard FileManager.default.isReadableFile(atPath: development.path) else {
            throw VideoResearchError.helperMissing
        }
        return development
    }

    private func locatePython() throws -> String {
        let configured = ProcessInfo.processInfo.environment["FOCUSVAULT_PYTHON_PATH"]
        let candidates = [
            configured,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ].compactMap { $0 }
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }
        throw VideoResearchError.pythonMissing
    }

    private static func defaultResultURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("FocusVault", isDirectory: true)
            .appendingPathComponent("video-recommendations.json")
    }

    private static func loadResult(from url: URL) -> VideoResearchResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VideoResearchResult.self, from: data)
    }

    private static func save(_ value: VideoResearchResult, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw VideoResearchError.invalidResult
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw VideoResearchError.invalidResult
        }
    }
}
