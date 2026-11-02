//
//  PacingClassifierTests.swift
//  ClaudeMeterTests
//

import XCTest
@testable import ClaudeMeter

final class PacingClassifierTests: XCTestCase {
    private let weekly: TimeInterval = Constants.Pacing.weeklyWindow

    private func makeNow() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func test_emptyHistory_isIndeterminate() {
        let now = makeNow()
        let resetAt = now.addingTimeInterval(2 * 24 * 3600)  // 2 days from now → 5 days elapsed

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 50,
            resetAt: resetAt,
            windowDuration: weekly,
            history: [],
            now: now
        )

        XCTAssertEqual(result.state, .indeterminate)
        XCTAssertNil(result.projectedFinal)
    }

    func test_earlyInWindow_isIndeterminate() {
        let now = makeNow()
        // 6 hours into the week → too early for a verdict (need >= 24h).
        let resetAt = now.addingTimeInterval(weekly - 6 * 3600)

        let history = denseHistory(
            startingAt: now.addingTimeInterval(-6 * 3600),
            endingAt: now,
            startUtilization: 0,
            endUtilization: 20,
            resetAt: resetAt
        )

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 20,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        XCTAssertEqual(result.state, .indeterminate)
    }

    func test_uniformActiveUsage_isOnTrack() {
        // 4 days into the week, 50% used uniformly over those 4 days while active.
        // Expected projection: ~85-95% by end of week → on track.
        let now = makeNow()
        let elapsed: TimeInterval = 4 * 24 * 3600
        let resetAt = now.addingTimeInterval(weekly - elapsed)
        let history = denseHistory(
            startingAt: now.addingTimeInterval(-elapsed),
            endingAt: now,
            startUtilization: 0,
            endUtilization: 50,
            resetAt: resetAt,
            sampleInterval: 5 * 60   // every 5 min
        )

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 50,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        XCTAssertEqual(result.state, .onTrack)
        if let projected = result.projectedFinal {
            // Projection should be close to 87.5% (uniform extrapolation).
            XCTAssertGreaterThan(projected, 70)
            XCTAssertLessThan(projected, 100)
        } else {
            XCTFail("Expected a projected final value")
        }
    }

    func test_rapidBurnRate_isOverConsumption() {
        // 2 days in, already at 60% — projecting will hit >100%.
        let now = makeNow()
        let elapsed: TimeInterval = 2 * 24 * 3600
        let resetAt = now.addingTimeInterval(weekly - elapsed)
        let history = denseHistory(
            startingAt: now.addingTimeInterval(-elapsed),
            endingAt: now,
            startUtilization: 0,
            endUtilization: 60,
            resetAt: resetAt,
            sampleInterval: 5 * 60
        )

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 60,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        XCTAssertEqual(result.state, .overConsumption)
        XCTAssertGreaterThanOrEqual(result.projectedFinal ?? 0, 100)
    }

    func test_slowActivity_isUnderConsumption() {
        // 6 days in, only 15% used despite consistent active sampling.
        // Projection: ~17.5% by reset → under-consumption.
        let now = makeNow()
        let elapsed: TimeInterval = 6 * 24 * 3600
        let resetAt = now.addingTimeInterval(weekly - elapsed)
        let history = denseHistory(
            startingAt: now.addingTimeInterval(-elapsed),
            endingAt: now,
            startUtilization: 0,
            endUtilization: 15,
            resetAt: resetAt,
            sampleInterval: 5 * 60
        )

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 15,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        XCTAssertEqual(result.state, .underConsumption)
        if let projected = result.projectedFinal {
            XCTAssertLessThan(projected, 70)
        }
    }

    func test_integerPercentJumps_stillProduceVerdict() {
        // Realistic Claude API behaviour: utilization is an *integer* percent. Over 2 days of
        // 1-min snapshots we'd see ~4 percent jumps, the rest being identical values. The
        // linear-extrapolation algorithm should still produce a sensible verdict because it
        // only looks at first vs last across the history.
        let now = makeNow()
        let elapsed: TimeInterval = 2 * 24 * 3600
        let resetAt = now.addingTimeInterval(weekly - elapsed)

        // Build snapshots every 60s holding integer-percent values 5→6→7→8→9.
        var history: [PacingSnapshot] = []
        var t = now.addingTimeInterval(-elapsed)
        var util = 5.0
        let total = Int(elapsed / 60)
        for i in 0..<total {
            // Jump 1% every ~quarter of the data set.
            if i == total / 4 || i == total / 2 || i == 3 * total / 4 {
                util += 1
            }
            history.append(PacingSnapshot(timestamp: t, weeklyUtilization: util, weeklyResetAt: resetAt))
            t = t.addingTimeInterval(60)
        }

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: util,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        XCTAssertNotEqual(result.state, .indeterminate)
        XCTAssertNotNil(result.projectedFinal)
    }

    func test_tooLittleHistoryDuration_isIndeterminate() {
        // Have plenty of snapshots and elapsed >24h, but the history span is only a couple of
        // hours — extrapolating from such a small window would amplify noise. Bail out.
        let now = makeNow()
        let elapsed: TimeInterval = 2 * 24 * 3600
        let resetAt = now.addingTimeInterval(weekly - elapsed)

        let history = denseHistory(
            startingAt: now.addingTimeInterval(-2 * 3600),  // 2 hours of data
            endingAt: now,
            startUtilization: 10,
            endUtilization: 11,
            resetAt: resetAt,
            sampleInterval: 60
        )

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 11,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        XCTAssertEqual(result.state, .indeterminate)
    }

    // MARK: - Helpers

    private func denseHistory(
        startingAt start: Date,
        endingAt end: Date,
        startUtilization: Double,
        endUtilization: Double,
        resetAt: Date,
        sampleInterval: TimeInterval = 60
    ) -> [PacingSnapshot] {
        var snapshots: [PacingSnapshot] = []
        let totalDuration = end.timeIntervalSince(start)
        var t = start
        while t <= end {
            let progress = totalDuration > 0 ? t.timeIntervalSince(start) / totalDuration : 0
            let util = startUtilization + (endUtilization - startUtilization) * progress
            snapshots.append(PacingSnapshot(
                timestamp: t,
                weeklyUtilization: util,
                weeklyResetAt: resetAt
            ))
            t = t.addingTimeInterval(sampleInterval)
        }
        return snapshots
    }

    // MARK: - Session classifier (time-proportional)

    private let session: TimeInterval = Constants.Pacing.sessionWindow

    func test_session_earlyInWindow_isIndeterminate() {
        let now = makeNow()
        // 10 minutes into the 5h window → below the 30-minute cold-start guard.
        let resetAt = now.addingTimeInterval(session - 10 * 60)

        let result = PacingClassifier.classifySession(
            currentUtilization: 50,
            resetAt: resetAt,
            windowDuration: session,
            now: now
        )

        XCTAssertEqual(result.state, .indeterminate)
        XCTAssertNil(result.projectedFinal)
    }

    func test_session_resetInPast_isIndeterminate() {
        let now = makeNow()
        let resetAt = now.addingTimeInterval(-60)

        let result = PacingClassifier.classifySession(
            currentUtilization: 50,
            resetAt: resetAt,
            windowDuration: session,
            now: now
        )

        XCTAssertEqual(result.state, .indeterminate)
    }

    func test_session_proportionalUsage_isOnTrack() {
        let now = makeNow()
        // Halfway through the window, 45% used → projected ~90% → on track.
        let resetAt = now.addingTimeInterval(session / 2)

        let result = PacingClassifier.classifySession(
            currentUtilization: 45,
            resetAt: resetAt,
            windowDuration: session,
            now: now
        )

        XCTAssertEqual(result.state, .onTrack)
        XCTAssertEqual(result.projectedFinal ?? 0, 90, accuracy: 0.001)
    }

    func test_session_fastBurn_isOverConsumption() {
        let now = makeNow()
        // Halfway through, 70% used → projected 140% → burning fast.
        let resetAt = now.addingTimeInterval(session / 2)

        let result = PacingClassifier.classifySession(
            currentUtilization: 70,
            resetAt: resetAt,
            windowDuration: session,
            now: now
        )

        XCTAssertEqual(result.state, .overConsumption)
        XCTAssertEqual(result.projectedFinal ?? 0, 140, accuracy: 0.001)
    }

    func test_session_slowBurn_isUnderConsumption() {
        let now = makeNow()
        // Halfway through, 20% used → projected 40% → slow pace.
        let resetAt = now.addingTimeInterval(session / 2)

        let result = PacingClassifier.classifySession(
            currentUtilization: 20,
            resetAt: resetAt,
            windowDuration: session,
            now: now
        )

        XCTAssertEqual(result.state, .underConsumption)
        XCTAssertEqual(result.projectedFinal ?? 0, 40, accuracy: 0.001)
    }
}
