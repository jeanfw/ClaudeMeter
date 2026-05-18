//
//  NotificationState.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import Foundation

/// Tracks notification state per Claude account. Earlier versions kept these as global flags,
/// which produced spurious notifications in a multi-account setup: account A bumping
/// `lastPercentage` up to 50 would then make account B (still at 0) repeatedly satisfy the
/// "reset detected" check (`lastPercentage > 0 && current == 0`) on every refresh cycle.
struct NotificationState: Codable, Equatable, Sendable {
    /// Has the warning threshold notification been fired since utilization last dropped below
    /// the threshold, keyed by account id.
    var hasWarningBeenNotified: [UUID: Bool] = [:]

    /// Has the critical threshold notification been fired since utilization last dropped below
    /// the threshold, keyed by account id.
    var hasCriticalBeenNotified: [UUID: Bool] = [:]

    /// Last observed session utilization (0-100) per account — used to detect the 5-hour
    /// session reset (transition from > 0 to == 0).
    var lastSessionPercentageByAccount: [UUID: Double] = [:]

    /// Last weekly pacing state we notified the user about, per account.
    var lastPacingNotifiedState: [UUID: PacingState] = [:]

    enum CodingKeys: String, CodingKey {
        case hasWarningBeenNotified = "warning_notified_by_account"
        case hasCriticalBeenNotified = "critical_notified_by_account"
        case lastSessionPercentageByAccount = "last_session_percentage_by_account"
        case lastPacingNotifiedState = "last_pacing_notified_state"
        // Legacy keys decoded for migration; never written back.
        case legacyHasWarningBeenNotified = "warning_notified"
        case legacyHasCriticalBeenNotified = "critical_notified"
        case legacyLastPercentage = "last_percentage"
    }

    init(
        hasWarningBeenNotified: [UUID: Bool] = [:],
        hasCriticalBeenNotified: [UUID: Bool] = [:],
        lastSessionPercentageByAccount: [UUID: Double] = [:],
        lastPacingNotifiedState: [UUID: PacingState] = [:]
    ) {
        self.hasWarningBeenNotified = hasWarningBeenNotified
        self.hasCriticalBeenNotified = hasCriticalBeenNotified
        self.lastSessionPercentageByAccount = lastSessionPercentageByAccount
        self.lastPacingNotifiedState = lastPacingNotifiedState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasWarningBeenNotified = try container.decodeIfPresent([UUID: Bool].self, forKey: .hasWarningBeenNotified) ?? [:]
        hasCriticalBeenNotified = try container.decodeIfPresent([UUID: Bool].self, forKey: .hasCriticalBeenNotified) ?? [:]
        lastSessionPercentageByAccount = try container.decodeIfPresent([UUID: Double].self, forKey: .lastSessionPercentageByAccount) ?? [:]
        lastPacingNotifiedState = try container.decodeIfPresent([UUID: PacingState].self, forKey: .lastPacingNotifiedState) ?? [:]
        // Legacy single-account fields are intentionally dropped — they were the source of the
        // cross-account false-positive reset spam this struct was rewritten to fix. There's no
        // safe migration path (we can't attribute a global percentage to a specific account),
        // so the per-account dictionaries simply start empty on upgrade.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasWarningBeenNotified, forKey: .hasWarningBeenNotified)
        try container.encode(hasCriticalBeenNotified, forKey: .hasCriticalBeenNotified)
        try container.encode(lastSessionPercentageByAccount, forKey: .lastSessionPercentageByAccount)
        try container.encode(lastPacingNotifiedState, forKey: .lastPacingNotifiedState)
    }
}

extension NotificationState {
    /// Check if a warning- or critical-threshold notification should fire for this account.
    func shouldNotify(
        accountId: UUID,
        currentPercentage: Double,
        threshold: Double,
        isWarning: Bool
    ) -> Bool {
        let alreadyNotified = isWarning
            ? (hasWarningBeenNotified[accountId] ?? false)
            : (hasCriticalBeenNotified[accountId] ?? false)
        return !alreadyNotified && currentPercentage >= threshold
    }

    /// Detect the 5-hour session reset for this account, but only when the user was actually
    /// out of credits (utilization hit 100% before the reset). Resets that happen while the
    /// user wasn't capped aren't actionable — they don't unblock anything — so we stay silent.
    func shouldNotifyReset(accountId: UUID, currentPercentage: Double) -> Bool {
        let last = lastSessionPercentageByAccount[accountId] ?? 0
        return last >= 100 && currentPercentage == 0
    }
}
