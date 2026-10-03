import Foundation
import VaultyCore

enum UnlockGameTests {
    static let tests: [SelfTestCase] = [
        ("Signal Shift coordinate transforms", testSignalShiftTransformsCoordinates),
        ("Signal Shift difficulty progression", testSignalShiftDifficultyProgression),
        ("Signal Shift three-round completion", testSignalShiftRequiresThreeCompletedRounds),
        ("Signal Shift practice room", testSignalShiftPracticeRoomCostsNoLives),
        ("Signal Shift three-life lockout", testSignalShiftThreeLivesLockOut),
        ("Grid Shot scoring and relocation", testGridShotScoringAndTargetRelocation),
        ("Grid Shot hard target", testGridShotHardTargetIsThirty),
        ("Typing Sprint Monkeytype completion", testTypingSprintMonkeytypeCompletion),
        ("required unlock challenge rotation", testUnlockChallengeKindsRemainComplete)
    ]
}

private func testSignalShiftTransformsCoordinates() throws {
    let point = SignalGridPoint(row: 0, column: 1)
    try checkEqual(
        SignalTransform.unchanged.apply(to: point, gridSize: 4),
        point,
        "practice-room identity transform changed the path"
    )
    try checkEqual(
        SignalTransform.rotateClockwise.apply(to: point, gridSize: 4),
        SignalGridPoint(row: 1, column: 3),
        "clockwise mental rotation is wrong"
    )
    try checkEqual(
        SignalTransform.rotateCounterClockwise.apply(to: point, gridSize: 4),
        SignalGridPoint(row: 2, column: 0),
        "counter-clockwise mental rotation is wrong"
    )
    try checkEqual(
        SignalTransform.mirrorHorizontally.apply(to: point, gridSize: 4),
        SignalGridPoint(row: 0, column: 2),
        "horizontal mirror is wrong"
    )
}
private func testSignalShiftDifficultyProgression() throws {
    var generator = SignalShiftGenerator(seed: 42)
    let first = generator.makePuzzle(level: 1)
    let second = generator.makePuzzle(level: 2)
    let third = generator.makePuzzle(level: 3)

    try checkEqual(first.sequence.count, 3, "practice room should contain three signals")
    try checkEqual(first.transform, .unchanged, "practice room should not transform the path")
    try check(!first.reverseOrder, "practice room should preserve order")
    try checkEqual(second.sequence.count, 4, "level two should contain four signals")
    try checkEqual(second.transform, .mirrorHorizontally, "level two transform changed")
    try check(!second.reverseOrder, "level two should preserve order")
    try checkEqual(third.sequence.count, 4, "level three should contain four signals")
    try checkEqual(third.transform, .rotateClockwise, "level three transform changed")
    try check(!third.reverseOrder, "level three should preserve order")
    try checkEqual(Set(first.sequence).count, first.sequence.count, "a puzzle repeated a signal cell")
    try check(zip(first.sequence, first.sequence.dropFirst()).allSatisfy { pair in
        let (left, right) = pair
        return abs(left.row - right.row) + abs(left.column - right.column) == 1
    }, "practice-room signals should form a connected path")
}
private func testSignalShiftRequiresThreeCompletedRounds() throws {
    var run = SignalShiftRun(seed: 7)
    try checkEqual(run.submit(run.puzzle.expectedSequence), .advanced(nextLevel: 2), "first solved round did not advance")
    try checkEqual(run.submit(run.puzzle.expectedSequence), .advanced(nextLevel: 3), "second solved round did not advance")
    try checkEqual(run.submit(run.puzzle.expectedSequence), .completed, "third solved round did not complete")
    try checkEqual(run.livesRemaining, 3, "correct rounds consumed lives")
}
private func testSignalShiftPracticeRoomCostsNoLives() throws {
    var run = SignalShiftRun(seed: 99)
    let wrong = [SignalGridPoint(row: -1, column: -1)]

    try checkEqual(run.submit(wrong), .retry(livesRemaining: 3), "practice mistake consumed a life")
    try checkEqual(run.livesRemaining, 3, "practice room reduced lives")
    try checkEqual(run.level, 1, "practice retry advanced the room")
}
private func testSignalShiftThreeLivesLockOut() throws {
    var run = SignalShiftRun(seed: 99)
    let wrong = [SignalGridPoint(row: -1, column: -1)]
    try checkEqual(run.submit(run.puzzle.expectedSequence), .advanced(nextLevel: 2), "could not leave practice room")

    try checkEqual(run.submit(wrong), .retry(livesRemaining: 2), "first scored mistake did not consume one life")
    try checkEqual(run.submit(wrong), .retry(livesRemaining: 1), "second mistake did not consume one life")
    try checkEqual(run.submit(wrong), .lockedOut, "third mistake did not require a fresh password attempt")
    try checkEqual(run.livesRemaining, 0, "lockout retained a life")
}
private func testGridShotScoringAndTargetRelocation() throws {
    var run = GridShotRun(seed: 123)
    try checkEqual(run.targets.count, 3, "Grid Shot did not start with three targets")
    guard let firstTarget = run.targets.first else {
        throw SelfTestFailure(message: "Grid Shot started without a target")
    }
    try checkEqual(
        run.tap(at: firstTarget.point),
        .hit(targetID: firstTarget.id),
        "Grid Shot target click was not a hit"
    )
    try checkEqual(run.score, 1, "Grid Shot hit did not add one point")
    try checkEqual(run.targets.count, 3, "Grid Shot did not keep three targets")
    try check(
        run.targets.first(where: { $0.id == firstTarget.id })?.point != firstTarget.point,
        "Grid Shot hit target did not relocate"
    )

    try checkEqual(
        run.tap(at: GridShotPoint(x: 0, y: 0)),
        .miss,
        "Grid Shot empty arena click was treated as a hit"
    )
    try checkEqual(run.score, 0, "Grid Shot miss did not remove one point")
}
private func testGridShotHardTargetIsThirty() throws {
    var run = GridShotRun(seed: 456)
    for _ in 0..<GridShotRun.targetScore {
        guard let target = run.targets.first else {
            throw SelfTestFailure(message: "Grid Shot lost every target")
        }
        try checkEqual(
            run.tap(at: target.point),
            .hit(targetID: target.id),
            "Grid Shot target click was not a hit"
        )
    }
    try checkEqual(GridShotRun.durationSeconds, 10, "Grid Shot duration changed")
    try checkEqual(GridShotRun.targetCount, 3, "Grid Shot target count changed")
    try checkEqual(GridShotRun.targetRadius, 50, "Grid Shot aim radius changed")
    try checkEqual(run.score, 30, "Grid Shot hard target was not 30")
    try check(run.hasReachedTarget, "Grid Shot did not pass at score 30")
}
private func testTypingSprintMonkeytypeCompletion() throws {
    let prompt = TypingSprint.prompt(seed: 42)
    try checkEqual(prompt, TypingSprint.prompt(seed: 42), "typing prompt generation is not deterministic")
    try checkEqual(prompt.split(separator: " ").count, TypingSprint.wordCount, "typing prompt word count changed")

    let success = TypingSprint.evaluate(typed: prompt, target: prompt, elapsedSeconds: 120)
    try check(success.succeeded, "exact Monkeytype-style completion did not pass immediately")
    try checkEqual(success.accuracy, 1, "exact typing sprint accuracy is not 100 percent")

    var incorrect = prompt
    incorrect.removeLast()
    incorrect.append("x")
    let mistake = TypingSprint.evaluate(typed: incorrect, target: prompt, elapsedSeconds: 12)
    try check(!mistake.succeeded, "typing sprint passed incorrect text")
}
private func testUnlockChallengeKindsRemainComplete() throws {
    try checkEqual(
        UnlockChallengeKind.allCases,
        [.signalShift, .gridShot, .typingSprint],
        "known challenge kinds changed unexpectedly"
    )
    try checkEqual(
        UnlockChallengeKind.requiredRotation,
        [.gridShot, .typingSprint],
        "required unlock rotation should contain only Grid Shot and Typing Sprint"
    )
    try checkEqual(
        UnlockChallengeKind.taskHubChoices,
        [.gridShot, .typingSprint, .signalShift],
        "task hub choices should include the restored optional Signal Shift"
    )
}
