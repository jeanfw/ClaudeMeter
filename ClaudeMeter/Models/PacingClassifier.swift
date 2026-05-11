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

        // Don't produce a verdict in the first day or with very sparse history — too easy to
        // flap between states.
        guard elapsed >= Constants.Pacing.minimumElapsedForVerdict,
              history.count >= Constants.Pacing.minimumHistoryEntriesForVerdict else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        let sorted = history.sorted { $0.timestamp < $1.timestamp }

        // Walk consecutive pairs accumulating "active" time. A gap longer than maxSnapshotGap
        // means the app was offline/asleep — we don't count that as either active or inactive,
        // we just skip the interval.
        var activeSeconds: TimeInterval = 0
        var consumedActive: Double = 0
        var observedElapsed: TimeInterval = 0

        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            let dt = current.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0, dt < Constants.Pacing.maxSnapshotGap else { continue }
            observedElapsed += dt

            let du = max(0, current.weeklyUtilization - previous.weeklyUtilization)
            if du > Constants.Pacing.activityEpsilon {
                activeSeconds += dt
                consumedActive += du
            }
        }

        guard activeSeconds >= Constants.Pacing.minimumActiveTimeForVerdict,
              consumedActive > 0 else {
            return PacingResult(state: .indeterminate, projectedFinal: nil)
        }

        // Activity ratio: how much of the *observed* elapsed time has been "active". Apply that
        // ratio forward to the remaining window to estimate remaining active time. This is the
        // key correction vs the simple window-relative pace.
        let activeRatio = observedElapsed > 0 ? activeSeconds / observedElapsed : 0
        let ratePerActiveSecond = consumedActive / activeSeconds
        let remainingWindow = resetAt.timeIntervalSince(now)
        let projectedRemainingActiveSeconds = remainingWindow * activeRatio
        let projectedRemainingConsumption = projectedRemainingActiveSeconds * ratePerActiveSecond
        let projectedFinal = currentUtilization + projectedRemainingConsumption

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
