import Foundation

private struct LocalToolCatalogFile: Codable {
    let version: Int
    var tools: [LocalToolDefinition]
}

struct LocalToolCatalog {
    let fileURL: URL

    init(fileURL: URL = LocalToolCatalog.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vaulty", isDirectory: true)
            .appendingPathComponent("tools.json")
    }

    func load(defaults: [LocalToolDefinition]) -> [LocalToolDefinition] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try? save(defaults)
            return defaults
        }
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(LocalToolCatalogFile.self, from: data),
              file.version == 1, Set(file.tools.map(\.id)).count == file.tools.count else {
            // Preserve a malformed catalog for manual recovery instead of
            // silently overwriting the user's configured tools.
            return defaults
        }
        return file.tools
    }

    func save(_ tools: [LocalToolDefinition]) throws {
        guard Set(tools.map(\.id)).count == tools.count else {
            throw LocalToolError.invalidDefinition("Tool identifiers must be unique.")
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LocalToolCatalogFile(version: 1, tools: tools))
        try data.write(to: fileURL, options: .atomic)
    }
}
