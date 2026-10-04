import Foundation

enum VideoResearchStore {
    static var defaultResultURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("FocusVault", isDirectory: true)
            .appendingPathComponent("video-recommendations.json")
    }

    static func loadResult(from url: URL) -> VideoResearchResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VideoResearchResult.self, from: data)
    }

    static func save(_ value: VideoResearchResult, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    static func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
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
