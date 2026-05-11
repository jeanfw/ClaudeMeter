//
//  PacingHistoryRepository.swift
//  ClaudeMeter
//

import Foundation

/// Actor-isolated, per-account pacing history persistence (one JSON file per account).
actor PacingHistoryRepository: PacingHistoryRepositoryProtocol {
    private let cacheDir: URL
    private let fileManager: FileManager
    /// In-memory mirror so we don't re-read the file every refresh.
    private var inMemory: [UUID: [PacingSnapshot]] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("com.claudemeter", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.cacheDir = cacheDir
    }

    func load(accountId: UUID) async -> [PacingSnapshot] {
        if let cached = inMemory[accountId] { return cached }
        let loaded = loadFromDisk(accountId: accountId)
        inMemory[accountId] = loaded
        return loaded
    }

    @discardableResult
    func append(_ snapshot: PacingSnapshot, accountId: UUID) async -> [PacingSnapshot] {
        var history = await load(accountId: accountId)

        // Drop entries from a previous weekly window. We detect a window reset by the
        // weeklyResetAt drifting forward by more than 60 seconds. (Cache TTL is 55s so within a
        // single window the value is stable.)
        if let last = history.last,
           snapshot.weeklyResetAt.timeIntervalSince(last.weeklyResetAt) > 60 {
            history.removeAll()
        }

        history.append(snapshot)

        // Cap buffer size to avoid unbounded growth. The reset-detection branch above is the
        // primary pruning mechanism — the size cap is just a defensive backstop.
        if history.count > Constants.Pacing.maxHistoryEntries {
            history.removeFirst(history.count - Constants.Pacing.maxHistoryEntries)
        }

        inMemory[accountId] = history
        saveToDisk(history, accountId: accountId)
        return history
    }

    func purge(accountId: UUID) async {
        inMemory[accountId] = nil
        try? fileManager.removeItem(at: diskURL(for: accountId))
    }

    // MARK: - Private

    private func diskURL(for accountId: UUID) -> URL {
        cacheDir.appendingPathComponent("history_\(accountId.uuidString).json")
    }

    private func loadFromDisk(accountId: UUID) -> [PacingSnapshot] {
        guard let data = try? Data(contentsOf: diskURL(for: accountId)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PacingSnapshot].self, from: data)) ?? []
    }

    private func saveToDisk(_ history: [PacingSnapshot], accountId: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return }
        try? data.write(to: diskURL(for: accountId), options: .atomic)
    }
}
