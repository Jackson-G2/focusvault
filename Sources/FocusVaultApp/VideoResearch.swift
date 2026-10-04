import AppKit
import Foundation
import Combine

final class VideoResearchModel: ObservableObject {
    @Published private(set) var state: VideoResearchState = .idle
    @Published private(set) var result: VideoResearchResult?
    @Published private(set) var answer: String?
    @Published private(set) var answerVideoID: String?
    @Published private(set) var answerError: String?
    @Published private(set) var isAsking = false

    private var activeTask: CapturedProcessTask?
    private let resultURL: URL

    init(resultURL: URL = VideoResearchStore.defaultResultURL) {
        self.resultURL = resultURL
        result = VideoResearchStore.loadResult(from: resultURL)
        if result != nil {
            state = .ready
        }
    }

    deinit {
        activeTask?.cancel()
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
        guard activeTask == nil else { return }

        answer = nil
        answerError = nil
        state = .researching
        answerVideoID = nil
        runHelper(arguments: ["--mode", "recommend"]) { [weak self] output in
            guard let self else { return }
            switch output {
            case let .success(output):
                do {
                    let decoded = try VideoResearchStore.decode(VideoResearchResult.self, from: output)
                    self.result = decoded
                    try VideoResearchStore.save(decoded, to: self.resultURL)
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
        guard activeTask == nil else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        answer = nil
        answerError = nil
        answerVideoID = recommendation.videoId
        guard !trimmed.isEmpty else {
            answerError = "Ask a question about the selected video."
            return
        }

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
                    let payload = try VideoResearchStore.decode(VideoAnswerPayload.self, from: output)
                    if payload.status == "ok" {
                        guard payload.videoId == recommendation.videoId else {
                            throw VideoResearchError.invalidResult
                        }
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
        guard let url = recommendation.watchURL else { return }
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
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script.path] + arguments

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["NO_COLOR"] = "1"
            environment["PATH"] = Self.augmentedPath(environment["PATH"])
            process.environment = environment
            let task = CapturedProcessTask(process)
            activeTask = task

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let captured = try task.run()

                    DispatchQueue.main.async {
                        self?.activeTask = nil
                        if captured.exitStatus == 0, !captured.stdout.isEmpty {
                            completion(.success(captured.stdout))
                        } else if !captured.stderr.isEmpty {
                            completion(.failure(VideoResearchError.processFailed(captured.stderr)))
                        } else if captured.exitStatus != 0 {
                            completion(.failure(VideoResearchError.processFailed("The learning researcher exited with status \(captured.exitStatus).")))
                        } else {
                            completion(.failure(VideoResearchError.emptyOutput))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.activeTask = nil
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

    private static func augmentedPath(_ existing: String?) -> String {
        let homeBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin").path
        let extras = [
            "/opt/homebrew/bin", "/usr/local/bin", homeBin,
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        return (extras + (existing.map { [$0] } ?? [])).joined(separator: ":")
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

}
