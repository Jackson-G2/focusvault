import Foundation

public struct TypingSprintResult: Equatable, Sendable {
    public let accuracy: Double
    public let wordsPerMinute: Double
    public let isExact: Bool
    public let succeeded: Bool
}

public enum TypingSprint {
    public static let wordCount = 18
    public static let words = [
        "focus", "choose", "clear", "calm", "work", "build", "small", "next",
        "useful", "steady", "attention", "finish", "move", "create", "learn", "plan",
        "quiet", "progress", "today", "begin", "simple", "strong", "time", "purpose",
        "think", "make", "care", "change", "forward", "practice", "return", "decide"
    ]

    public static func prompt(seed: UInt64) -> String {
        var random = UnlockGameRandom(seed: seed)
        return (0..<wordCount)
            .map { _ in words[Int(random.next() % UInt64(words.count))] }
            .joined(separator: " ")
    }

    public static func evaluate(
        typed: String,
        target: String,
        elapsedSeconds: TimeInterval
    ) -> TypingSprintResult {
        let typedCharacters = Array(typed)
        let targetCharacters = Array(target)
        let comparedCount = max(typedCharacters.count, targetCharacters.count)
        let matchingCount = (0..<min(typedCharacters.count, targetCharacters.count)).reduce(0) { count, index in
            count + (typedCharacters[index] == targetCharacters[index] ? 1 : 0)
        }
        let accuracy = comparedCount == 0 ? 0 : Double(matchingCount) / Double(comparedCount)
        let minutes = max(elapsedSeconds, 0.25) / 60
        let wordsPerMinute = (Double(typedCharacters.count) / 5) / minutes
        let exact = typed == target
        return TypingSprintResult(
            accuracy: accuracy,
            wordsPerMinute: wordsPerMinute,
            isExact: exact,
            succeeded: exact
        )
    }
}
