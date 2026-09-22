import Foundation

public enum UnlockChallengeKind: String, Codable, CaseIterable, Equatable, Sendable {
    case signalShift
    case gridShot
    case typingSprint

    /// Challenges used for real unlocks. Signal Shift remains available in the
    /// codebase for reference, but is intentionally not a required gate.
    public static let requiredRotation: [UnlockChallengeKind] = [
        .gridShot,
        .typingSprint
    ]

    /// Tasks shown in the user-selectable unlock hub. Signal Shift is optional;
    /// it is never selected automatically or required for access.
    public static let taskHubChoices: [UnlockChallengeKind] = [
        .gridShot,
        .typingSprint,
        .signalShift
    ]

    public var displayName: String {
        switch self {
        case .signalShift: return "Signal Shift"
        case .gridShot: return "Grid Shot"
        case .typingSprint: return "Typing Sprint"
        }
    }
}

public struct GridShotPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GridShotTarget: Equatable, Identifiable, Sendable {
    public let id: Int
    public let point: GridShotPoint

    public init(id: Int, point: GridShotPoint) {
        self.id = id
        self.point = point
    }
}

public enum GridShotTapOutcome: Equatable, Sendable {
    case hit(targetID: Int)
    case miss
}

public struct GridShotRun: Equatable, Sendable {
    public static let arenaWidth = 800.0
    public static let arenaHeight = 600.0
    public static let targetRadius = 50.0
    public static let targetCount = 3
    public static let targetScore = 30
    public static let durationSeconds = 10

    public private(set) var score: Int
    public private(set) var targets: [GridShotTarget]
    private var random: UnlockGameRandom

    public init(seed: UInt64, initialScore: Int = 0) {
        score = initialScore
        random = UnlockGameRandom(seed: seed)
        targets = [
            GridShotTarget(id: 0, point: GridShotPoint(x: 400, y: 300)),
            GridShotTarget(id: 1, point: GridShotPoint(x: 200, y: 250)),
            GridShotTarget(id: 2, point: GridShotPoint(x: 600, y: 200))
        ]
    }

    @discardableResult
    public mutating func tap(at point: GridShotPoint) -> GridShotTapOutcome {
        if let index = targets.firstIndex(where: { distance(from: $0.point, to: point) <= Self.targetRadius }) {
            let targetID = targets[index].id
            targets[index] = GridShotTarget(id: targetID, point: nextPoint(excluding: index))
            score += 1
            return .hit(targetID: targetID)
        }

        score -= 1
        return .miss
    }

    public var hasReachedTarget: Bool {
        score >= Self.targetScore
    }

    private func distance(from lhs: GridShotPoint, to rhs: GridShotPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private mutating func nextPoint(excluding index: Int) -> GridShotPoint {
        let minimumX = Self.targetRadius
        let maximumX = Self.arenaWidth - Self.targetRadius
        let minimumY = Self.targetRadius
        let maximumY = Self.arenaHeight - Self.targetRadius
        let minimumDistance = Self.targetRadius * 2.1

        for _ in 0..<40 {
            let candidate = GridShotPoint(
                x: minimumX + random.unit() * (maximumX - minimumX),
                y: minimumY + random.unit() * (maximumY - minimumY)
            )
            let clear = targets.enumerated().allSatisfy { otherIndex, target in
                otherIndex == index || distance(from: candidate, to: target.point) >= minimumDistance
            }
            if clear { return candidate }
        }

        return GridShotPoint(
            x: minimumX + random.unit() * (maximumX - minimumX),
            y: minimumY + random.unit() * (maximumY - minimumY)
        )
    }
}

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

private struct UnlockGameRandom: Equatable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xD1B5_4A32_D192_ED03 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Double {
        Double(next() % 1_000_000) / 999_999.0
    }
}
