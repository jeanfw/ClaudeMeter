//
//  PacingHistoryRepositoryProtocol.swift
//  ClaudeMeter
//

import Foundation

/// Protocol for per-account pacing history persistence.
///
/// History is bounded: the implementation drops entries on weekly reset (detected via a change
/// in the snapshot's `weeklyResetAt`) and caps the buffer to `Constants.Pacing.maxHistoryEntries`.
protocol PacingHistoryRepositoryProtocol: Actor {
    /// Load all snapshots for the given account in chronological order.
    func load(accountId: UUID) async -> [PacingSnapshot]

    /// Append a snapshot. The implementation prunes on weekly reset and enforces the size cap.
    /// Returns the post-append history.
    @discardableResult
    func append(_ snapshot: PacingSnapshot, accountId: UUID) async -> [PacingSnapshot]

    /// Drop all history for an account (called when the account is removed).
    func purge(accountId: UUID) async
}
