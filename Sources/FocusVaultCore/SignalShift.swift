import Foundation

public struct SignalGridPoint: Codable, Equatable, Hashable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public enum SignalTransform: String, Codable, CaseIterable, Sendable {
    case unchanged
    case rotateClockwise
    case rotateCounterClockwise
    case mirrorHorizontally

    public var instruction: String {
        switch self {
        case .unchanged:
            return "Replay the path exactly as shown"
        case .rotateClockwise:
            return "Rotate the path 90° clockwise"
        case .rotateCounterClockwise:
            return "Rotate the path 90° counter-clockwise"
        case .mirrorHorizontally:
            return "Mirror the path left-to-right"
        }
    }

    public func apply(to point: SignalGridPoint, gridSize: Int) -> SignalGridPoint {
        let edge = gridSize - 1
        switch self {
        case .unchanged:
            return point
        case .rotateClockwise:
            return SignalGridPoint(row: point.column, column: edge - point.row)
        case .rotateCounterClockwise:
            return SignalGridPoint(row: edge - point.column, column: point.row)
        case .mirrorHorizontally:
            return SignalGridPoint(row: point.row, column: edge - point.column)
        }
    }
}

public struct SignalShiftPuzzle: Equatable, Sendable {
    public static let gridSize = 4

    public let level: Int
    public let sequence: [SignalGridPoint]
    public let transform: SignalTransform
    public let reverseOrder: Bool

    public init(
        level: Int,
        sequence: [SignalGridPoint],
        transform: SignalTransform,
        reverseOrder: Bool
    ) {
        self.level = level
        self.sequence = sequence
        self.transform = transform
        self.reverseOrder = reverseOrder
    }

    public var expectedSequence: [SignalGridPoint] {
        let transformed = sequence.map {
            transform.apply(to: $0, gridSize: Self.gridSize)
        }
        return reverseOrder ? transformed.reversed() : transformed
    }

    public var instruction: String {
        if transform == .unchanged {
            return "\(transform.instruction)."
        }
        let order = reverseOrder ? "then replay it backwards" : "then replay it in the same order"
        return "\(transform.instruction), \(order)."
    }
}

public enum SignalShiftSubmission: Equatable, Sendable {
    case advanced(nextLevel: Int)
    case retry(livesRemaining: Int)
    case completed
    case lockedOut
}

/// A short visuospatial working-memory challenge used as deliberate unlock
/// friction. It makes no claim to improve general intelligence; it combines
/// recall, mental rotation, and rule switching in a testable local puzzle.
public struct SignalShiftRun: Equatable, Sendable {
    public private(set) var level: Int
    public private(set) var livesRemaining: Int
    public private(set) var puzzle: SignalShiftPuzzle

    private var generator: SignalShiftGenerator

    public init(seed: UInt64, lives: Int = 3) {
        var generator = SignalShiftGenerator(seed: seed)
        level = 1
        livesRemaining = max(1, lives)
        puzzle = generator.makePuzzle(level: 1)
        self.generator = generator
    }

    public mutating func submit(_ answer: [SignalGridPoint]) -> SignalShiftSubmission {
        guard answer == puzzle.expectedSequence else {
            // Room one is a practice room: retry freely until the rule is clear.
            if level == 1 {
                puzzle = generator.makePuzzle(level: level)
                return .retry(livesRemaining: livesRemaining)
            }
            livesRemaining -= 1
            if livesRemaining <= 0 {
                livesRemaining = 0
                return .lockedOut
            }
            puzzle = generator.makePuzzle(level: level)
            return .retry(livesRemaining: livesRemaining)
        }

        guard level < 3 else {
            return .completed
        }

        level += 1
        puzzle = generator.makePuzzle(level: level)
        return .advanced(nextLevel: level)
    }
}

public struct SignalShiftGenerator: Equatable, Sendable {
    private var random: SignalShiftRandom

    public init(seed: UInt64) {
        random = SignalShiftRandom(seed: seed)
    }

    public mutating func makePuzzle(level rawLevel: Int) -> SignalShiftPuzzle {
        let level = min(max(rawLevel, 1), 3)
        let sequenceLength = level == 1 ? 3 : 4
        let cellCount = SignalShiftPuzzle.gridSize * SignalShiftPuzzle.gridSize
        let start = Int(random.next() % UInt64(cellCount))
        var sequenceFlats = [start]

        while sequenceFlats.count < sequenceLength {
            let current = sequenceFlats.last ?? start
            let row = current / SignalShiftPuzzle.gridSize
            let column = current % SignalShiftPuzzle.gridSize
            let adjacent = [
                (row - 1, column),
                (row + 1, column),
                (row, column - 1),
                (row, column + 1)
            ]
            .filter { candidate in
                (0..<SignalShiftPuzzle.gridSize).contains(candidate.0)
                    && (0..<SignalShiftPuzzle.gridSize).contains(candidate.1)
            }
            .map { $0.0 * SignalShiftPuzzle.gridSize + $0.1 }
            .filter { !sequenceFlats.contains($0) }

            if !adjacent.isEmpty {
                sequenceFlats.append(adjacent[Int(random.next() % UInt64(adjacent.count))])
            } else {
                let remaining = (0..<cellCount).filter { !sequenceFlats.contains($0) }
                guard !remaining.isEmpty else { break }
                sequenceFlats.append(remaining[Int(random.next() % UInt64(remaining.count))])
            }
        }

        let sequence = sequenceFlats.map { flat in
            SignalGridPoint(
                row: flat / SignalShiftPuzzle.gridSize,
                column: flat % SignalShiftPuzzle.gridSize
            )
        }

        let transform: SignalTransform
        let reverseOrder = false
        switch level {
        case 1:
            transform = .unchanged
        case 2:
            transform = .mirrorHorizontally
        default:
            transform = .rotateClockwise
        }

        return SignalShiftPuzzle(
            level: level,
            sequence: sequence,
            transform: transform,
            reverseOrder: reverseOrder
        )
    }
}

private struct SignalShiftRandom: Equatable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
