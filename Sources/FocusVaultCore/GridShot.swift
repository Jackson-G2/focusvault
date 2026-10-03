import Foundation

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
