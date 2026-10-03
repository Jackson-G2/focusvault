import Foundation

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
