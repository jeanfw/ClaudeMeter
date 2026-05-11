//
//  PacingSnapshot.swift
//  ClaudeMeter
//

import Foundation

/// A point-in-time observation of weekly usage, used to reconstruct active-time burn rate.
///
/// The Claude API gives us only the current snapshot — there's no rate or history field — so
/// we persist a rolling buffer of these client-side and infer pacing from consecutive deltas.
struct PacingSnapshot: Codable, Equatable, Sendable {
    let timestamp: Date
    /// Weekly utilization (0-100) at `timestamp`.
    let weeklyUtilization: Double
    /// Reset time the API reported alongside this utilization. Used to detect window resets
    /// (when the value jumps forward by ~7 days the prior history is discarded).
    let weeklyResetAt: Date

    enum CodingKeys: String, CodingKey {
        case timestamp
        case weeklyUtilization = "weekly_utilization"
        case weeklyResetAt = "weekly_reset_at"
    }
}
