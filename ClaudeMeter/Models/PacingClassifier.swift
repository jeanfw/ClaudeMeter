//
//  PacingClassifier.swift
//  ClaudeMeter
//

import Foundation

/// Pacing verdict for a usage window.
enum PacingState: String, Codable, Equatable, Sendable {
    /// Projected to hit (or exceed) the cap before the window resets.
    case overConsumption
    /// Projected to land in a healthy range.
    case onTrack
    /// Projected to leave significant quota unused at reset.
    case underConsumption
    /// Not enough activity yet to produce a verdict (cold start, fresh reset, app just opened).
    case indeterminate
}

/// Output of the pacing classifier — the verdict plus the projected final utilization (0-100)
/// when a verdict can be produced.
struct PacingResult: Equatable, Sendable {
    let state: PacingState
    /// Projected final utilization at the window's reset, or nil when `state == .indeterminate`.
    let projectedFinal: Double?
}

/// Classifies the current pacing for a usage window using a buffer of historical snapshots.
///
/// The window-relative approach (in `UsageLimit.isAtRisk`) assumes the user consumes 24/7. This
/// classifier instead measures *active time* — intervals where utilization actually grew — and
/// extrapolates by projecting the same active-to-elapsed ratio forward to the reset time.
enum PacingClassifier {
    /// Classify pacing for the weekly window.
    /// - Parameters:
    ///   - currentUtilization: Most recent weekly utilization (0-100).
    ///   - resetAt: Reset time reported by the API for the current weekly window.
    ///   - windowDuration: Length of the weekly window (typically `Constants.Pacing.weeklyWindow`).
    ///   - history: Snapshots already filtered to the current window (the repository handles
    ///     pruning across resets).
    ///   - now: Injectable clock for testing.
    static func classifyWeekly(
        currentUtilization: Double,
        resetAt: Date,
        windowDuration: TimeInterval,
        history: [PacingSnapshot],
        now: Date = Date()
    ) -> PacingResult {
        guard resetAt > now else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }
        let windowStart = resetAt.addingTimeInterval(-windowDuration)
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > 0 else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        // Cold-start guards: don't produce a verdict in the first day or with very sparse history
        // — too easy to flap between states.
        guard elapsed >= Constants.Pacing.minimumElapsedForVerdict,
              history.count >= Constants.Pacing.minimumHistoryEntriesForVerdict else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        let sorted = history.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        // The Claude API returns weekly utilization as an *integer* percent (e.g. 5, 9), so
        // measuring "active hours" via per-snapshot deltas is impractical — most refresh
        // intervals show 0 change, and a true active hour leaves only a single 1% jump in the
        // data. Instead we extrapolate linearly from the rate observed across the entire
        // recorded history. This implicitly averages over the user's natural usage pattern
        // (work hours, sleep) — a steady "8 hours a day" user has their average rate baked in.
        let historyDuration = last.timestamp.timeIntervalSince(first.timestamp)
        guard historyDuration >= Constants.Pacing.minimumHistoryDurationForVerdict else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        let historyDelta = last.weeklyUtilization - first.weeklyUtilization
        // If utilization actually went down (window reset slipped past the repository's filter)
        // we can't trust the projection — bail out.
        guard historyDelta >= 0 else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        let observedRatePerSecond = historyDelta / historyDuration
        let remainingWindow = resetAt.timeIntervalSince(now)
        let projectedFinal = currentUtilization + observedRatePerSecond * remainingWindow

        let state: PacingState
        if projectedFinal >= Constants.Pacing.overConsumptionThreshold {
            state = .overConsumption
        } else if projectedFinal < Constants.Pacing.underConsumptionThreshold {
            state = .underConsumption
        } else {
            state = .onTrack
        }

        return PacingResult(state: state, projectedFinal: projectedFinal)
    }

    /// Classify pacing for the 5-hour session window.
    ///
    /// Unlike the weekly classifier, the session window is short enough that a snapshot history
    /// adds little — the API reports session utilization at integer-percent granularity and the
    /// window is over in a few hours. Instead we project linearly from the elapsed fraction of the
    /// window: if 40% has been consumed after half the window, the projected final is ~80%.
    /// - Parameters:
    ///   - currentUtilization: Most recent session utilization (0-100).
    ///   - resetAt: Reset time reported by the API for the current session window.
    ///   - windowDuration: Length of the session window (typically `Constants.Pacing.sessionWindow`).
    ///   - now: Injectable clock for testing.
    static func classifySession(
        currentUtilization: Double,
        resetAt: Date,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> PacingResult {
        guard resetAt > now else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }
        let windowStart = resetAt.addingTimeInterval(-windowDuration)
        let elapsed = now.timeIntervalSince(windowStart)

        // Cold-start guard: the projection is unstable when very little time has elapsed.
        guard elapsed >= Constants.Pacing.sessionMinimumElapsedForVerdict else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        let elapsedFraction = elapsed / windowDuration
        guard elapsedFraction > 0 else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        let projectedFinal = currentUtilization / elapsedFraction

        let state: PacingState
        if projectedFinal >= Constants.Pacing.overConsumptionThreshold {
            state = .overConsumption
        } else if projectedFinal < Constants.Pacing.underConsumptionThreshold {
            state = .underConsumption
        } else {
            state = .onTrack
        }

        return PacingResult(state: state, projectedFinal: projectedFinal)
    }
}
