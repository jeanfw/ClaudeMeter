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

    func test_largeGaps_arentCountedAsActive() {
        // 4 days elapsed but only 2h of dense activity in there (rest = gap > 30 min).
        // Active time too low → indeterminate.
        let now = makeNow()
        let elapsed: TimeInterval = 4 * 24 * 3600
        let resetAt = now.addingTimeInterval(weekly - elapsed)

        // Two snapshots close together (5 min apart) at the start, then a giant gap to now.
        let history = [
            PacingSnapshot(
                timestamp: now.addingTimeInterval(-elapsed),
                weeklyUtilization: 0,
                weeklyResetAt: resetAt
            ),
            PacingSnapshot(
                timestamp: now.addingTimeInterval(-elapsed + 5 * 60),
                weeklyUtilization: 5,
                weeklyResetAt: resetAt
            ),
            // Big gap (3.5 days, far > 30 min) — should NOT be counted toward active time.
            PacingSnapshot(
                timestamp: now,
                weeklyUtilization: 20,
                weeklyResetAt: resetAt
            )
        ]

        let result = PacingClassifier.classifyWeekly(
            currentUtilization: 20,
            resetAt: resetAt,
            windowDuration: weekly,
            history: history,
            now: now
        )

        // Only 5 min of "active" time accumulated → below the 1h floor → indeterminate.
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
}
