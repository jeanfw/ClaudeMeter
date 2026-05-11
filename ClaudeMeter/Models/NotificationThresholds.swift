//
//  NotificationThresholds.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// Notification threshold configuration
struct NotificationThresholds: Codable, Equatable, Sendable {
    /// Percentage for warning notification
    var warningThreshold: Double

    /// Percentage for critical notification
    var criticalThreshold: Double

    /// Whether to notify on session reset
    var isNotifiedOnReset: Bool

    /// Whether to notify when the weekly pacing classifier crosses into over- or
    /// under-consumption.
    var isPacingNotificationEnabled: Bool

    static let `default` = NotificationThresholds(
        warningThreshold: Constants.Thresholds.Notification.warningDefault,
        criticalThreshold: Constants.Thresholds.Notification.criticalDefault,
        isNotifiedOnReset: true,
        isPacingNotificationEnabled: true
    )

    enum CodingKeys: String, CodingKey {
        case warningThreshold = "warning_threshold"
        case criticalThreshold = "critical_threshold"
        case isNotifiedOnReset = "notify_on_reset"
        case isPacingNotificationEnabled = "notify_on_pacing_change"
    }

    init(
        warningThreshold: Double,
        criticalThreshold: Double,
        isNotifiedOnReset: Bool,
        isPacingNotificationEnabled: Bool
    ) {
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.isNotifiedOnReset = isNotifiedOnReset
        self.isPacingNotificationEnabled = isPacingNotificationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotificationThresholds.default
        warningThreshold = try container.decodeIfPresent(Double.self, forKey: .warningThreshold) ?? defaults.warningThreshold
        criticalThreshold = try container.decodeIfPresent(Double.self, forKey: .criticalThreshold) ?? defaults.criticalThreshold
        isNotifiedOnReset = try container.decodeIfPresent(Bool.self, forKey: .isNotifiedOnReset) ?? defaults.isNotifiedOnReset
        // Backwards-compat: this key didn't exist before, default to enabled.
        isPacingNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPacingNotificationEnabled) ?? defaults.isPacingNotificationEnabled
    }
}

extension NotificationThresholds {
    /// Get all enabled thresholds sorted ascending
    var enabledThresholds: [Double] {
        [warningThreshold, criticalThreshold].sorted()
    }
}
