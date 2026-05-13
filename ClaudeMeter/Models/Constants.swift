//
//  Constants.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-17.
//

import Foundation

/// Application-wide constants
enum Constants {
    /// Cache configuration
    enum Cache {
        /// Memory cache time-to-live (slightly less than minimum refresh interval)
        static let ttl: TimeInterval = 55

        /// Maximum number of cached icons
        static let maxIconCacheSize = 100
    }

    /// Network configuration
    enum Network {
        /// Maximum number of retry attempts for failed requests
        static let maxRetries = 3

        /// Base delay multiplier for exponential backoff (network errors)
        static let backoffBase: Double = 2.0

        /// Base delay multiplier for rate limit backoff (more aggressive)
        static let rateLimitBackoffBase: Double = 3.0
    }

    /// Refresh intervals (in seconds)
    enum Refresh {
        /// Minimum refresh interval
        static let minimum: TimeInterval = 60

        /// Maximum refresh interval
        static let maximum: TimeInterval = 600

        /// Staleness threshold (2x max refresh interval to account for retries/delays)
        static let stalenessThreshold: TimeInterval = 1200
    }

    /// Pacing/risk calculation configuration
    enum Pacing {
        /// 5-hour session window duration
        static let sessionWindow: TimeInterval = 5 * 60 * 60

        /// 7-day weekly window duration
        static let weeklyWindow: TimeInterval = 7 * 24 * 60 * 60

        /// Ratio threshold for "at risk" status (using faster than sustainable). Used by the
        /// session-window `isAtRisk` check.
        static let riskThreshold: Double = 1.2

        // MARK: - Weekly classifier (active-hours based)

        /// Don't produce a verdict in the first day of the weekly window — too easy to flap.
        static let minimumElapsedForVerdict: TimeInterval = 24 * 60 * 60

        /// Need at least this many snapshots before producing a verdict.
        static let minimumHistoryEntriesForVerdict: Int = 5

        /// Need at least this much elapsed time between the first and last snapshot before
        /// trusting an extrapolated rate (avoids huge swings from a small initial sample).
        static let minimumHistoryDurationForVerdict: TimeInterval = 6 * 60 * 60

        /// Projected final utilization at or above this → `overConsumption`.
        static let overConsumptionThreshold: Double = 100

        /// Projected final utilization below this → `underConsumption`.
        static let underConsumptionThreshold: Double = 70

        /// Cap on persisted history entries per account (defensive — pruning by reset is the
        /// primary mechanism). ~10 days at 60s polling.
        static let maxHistoryEntries: Int = 1000
    }

    /// Usage threshold configuration
    enum Thresholds {
        /// Visual status boundaries (fixed, for icon colors)
        /// These determine when the icon color changes from green → orange → red
        enum Status {
            /// Percentage where warning status begins (orange) - safe is 0..<warningStart
            static let warningStart: Double = 50
            /// Percentage where critical status begins (red) - warning is warningStart..<criticalStart
            static let criticalStart: Double = 80
        }

        /// Notification threshold configuration (user-configurable)
        enum Notification {
            /// Default warning notification threshold
            static let warningDefault: Double = 75
            /// Default critical notification threshold
            static let criticalDefault: Double = 90

            /// Slider bounds for warning threshold setting
            static let warningMin: Double = 50
            static let warningMax: Double = 90

            /// Slider bounds for critical threshold setting
            static let criticalMin: Double = 75
            static let criticalMax: Double = 100

            /// Slider step increment
            static let step: Double = 5
        }
    }
}
