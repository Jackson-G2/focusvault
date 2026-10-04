import Foundation
import VaultyCore

enum TimePolicyTests {
    static let tests: [SelfTestCase] = [
        ("sleep calculator bedtimes", testSleepCalculatorBedtimes),
        ("sleep calculator wake times and filtering", testSleepCalculatorWakeTimesAndFiltering),
        ("task clock exact estimate", testTaskClockAcceptsExactEstimate),
        ("task clock invalid estimate", testTaskClockRejectsInvalidEstimate),
        ("task clock pause remainder", testTaskClockPausePreservesRemainder),
        ("task clock resume, completion, and stop", testTaskClockResumesCompletesAndStops)
    ]
}

private func testSleepCalculatorBedtimes() throws {
    let calendar = testCalendar()
    let wakeTime = testDate(2026, 8, 24, 7, 0)
    let results = SleepCalculator.bedtimes(for: wakeTime, calendar: calendar)

    try checkEqual(results.map(\.cycles), [6, 5, 4], "sleep cycle recommendations changed order")
    try checkEqual(results.map(\.sleepMinutes), [540, 450, 360], "sleep durations are wrong")
    try checkEqual(
        results[0].time,
        testDate(2026, 8, 23, 21, 46),
        "six-cycle bedtime did not include sleep latency"
    )
    try checkEqual(
        results[2].time,
        testDate(2026, 8, 24, 0, 46),
        "four-cycle bedtime did not cross midnight correctly"
    )
}
private func testSleepCalculatorWakeTimesAndFiltering() throws {
    let calendar = testCalendar()
    let bedtime = testDate(2026, 8, 23, 22, 0)
    let results = SleepCalculator.recommendations(
        direction: .bedtime,
        time: bedtime,
        calendar: calendar,
        cycleCounts: [6, 6, 0, 13, 3]
    )

    try checkEqual(results.map(\.cycles), [6, 3], "invalid or duplicate sleep cycles were not filtered")
    try checkEqual(results[0].time, testDate(2026, 8, 24, 7, 14), "six-cycle wake time is wrong")
    try checkEqual(results[1].time, testDate(2026, 8, 24, 2, 44), "three-cycle wake time is wrong")
    try checkEqual(
        SleepCalculator.recommendations(direction: .wakeTime, time: bedtime, calendar: calendar),
        SleepCalculator.bedtimes(for: bedtime, calendar: calendar),
        "direction recommendation did not use bedtime calculation"
    )
}
private func testTaskClockAcceptsExactEstimate() throws {
    let clock = try FocusTaskClock(minutes: 40)
    try checkEqual(clock.durationSeconds, 2_400, "task clock duration is not exact")
    try checkEqual(clock.remainingWholeSeconds, 2_400, "task clock initial remainder is wrong")
    try checkEqual(clock.state, .ready, "new task clock is not ready")
}
private func testTaskClockRejectsInvalidEstimate() throws {
    for minutes in [0, -1, 241] {
        do {
            _ = try FocusTaskClock(minutes: minutes)
            throw SelfTestFailure(message: "invalid task estimate was accepted: \(minutes)")
        } catch let error as FocusTaskClockError {
            try checkEqual(error, .invalidDuration, "wrong task clock error for \(minutes) minutes")
        }
    }
}
private func testTaskClockPausePreservesRemainder() throws {
    let start = Date(timeIntervalSinceReferenceDate: 10_000)
    let pauseDate = start.addingTimeInterval(605)
    var clock = try FocusTaskClock(minutes: 40)

    try check(clock.start(at: start), "task clock did not start")
    clock.update(at: pauseDate)
    try check(clock.pause(at: pauseDate), "task clock did not pause")
    try checkEqual(clock.state, .paused, "task clock is not paused")
    try check(abs(clock.remainingSeconds - 1_795) < 0.0001, "pause remainder is not exact")

    let pausedRemainder = clock.remainingSeconds
    clock.update(at: pauseDate.addingTimeInterval(900))
    try checkEqual(clock.remainingSeconds, pausedRemainder, "paused time reduced the task clock")
}
private func testTaskClockResumesCompletesAndStops() throws {
    let start = Date(timeIntervalSinceReferenceDate: 20_000)
    var clock = try FocusTaskClock(minutes: 1)

    try check(clock.start(at: start), "one-minute task clock did not start")
    let pauseDate = start.addingTimeInterval(12.5)
    try check(clock.pause(at: pauseDate), "one-minute task clock did not pause")
    let pausedRemainder = clock.remainingSeconds
    try check(clock.resume(at: pauseDate.addingTimeInterval(90)), "task clock did not resume")
    clock.update(at: pauseDate.addingTimeInterval(90 + pausedRemainder + 0.1))
    try checkEqual(clock.state, .completed, "task clock did not complete at zero")
    try checkEqual(clock.remainingWholeSeconds, 0, "completed task clock has remaining time")
    try checkEqual(clock.progress, 1, "completed task clock is not at full progress")

    var stoppedClock = try FocusTaskClock(minutes: 10)
    try check(stoppedClock.start(at: start), "stoppable task clock did not start")
    stoppedClock.update(at: start.addingTimeInterval(30))
    try check(stoppedClock.stop(at: start.addingTimeInterval(30)), "task clock did not stop")
    try checkEqual(stoppedClock.state, .ready, "stopped task clock did not reset to ready")
    try checkEqual(stoppedClock.remainingWholeSeconds, 600, "stopped task clock did not reset its estimate")
}
