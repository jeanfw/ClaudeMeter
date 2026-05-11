//
//  PacingHistoryRepositoryFake.swift
//  ClaudeMeterTests
//

import Foundation
@testable import ClaudeMeter

actor PacingHistoryRepositoryFake: PacingHistoryRepositoryProtocol {
    private(set) var historyByAccount: [UUID: [PacingSnapshot]] = [:]

    func load(accountId: UUID) async -> [PacingSnapshot] {
        historyByAccount[accountId] ?? []
    }

    @discardableResult
    func append(_ snapshot: PacingSnapshot, accountId: UUID) async -> [PacingSnapshot] {
        var history = historyByAccount[accountId] ?? []
        if let last = history.last,
           snapshot.weeklyResetAt.timeIntervalSince(last.weeklyResetAt) > 60 {
            history.removeAll()
        }
        history.append(snapshot)
        historyByAccount[accountId] = history
        return history
    }

    func purge(accountId: UUID) async {
        historyByAccount[accountId] = nil
    }

    /// Test convenience: seed the history without going through `append`.
    func seed(_ history: [PacingSnapshot], accountId: UUID) async {
        historyByAccount[accountId] = history
    }
}
