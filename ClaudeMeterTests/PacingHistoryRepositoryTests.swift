//
//  PacingHistoryRepositoryTests.swift
//  ClaudeMeterTests
//

import XCTest
@testable import ClaudeMeter

final class PacingHistoryRepositoryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PacingHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func test_appendAndLoad_roundtrip() async {
        let repo = await makeRepo()
        let id = UUID()
        let resetAt = Date().addingTimeInterval(3 * 24 * 3600)
        let s1 = PacingSnapshot(timestamp: Date(), weeklyUtilization: 10, weeklyResetAt: resetAt)
        let s2 = PacingSnapshot(timestamp: Date().addingTimeInterval(60), weeklyUtilization: 11, weeklyResetAt: resetAt)

        _ = await repo.append(s1, accountId: id)
        let after = await repo.append(s2, accountId: id)
        XCTAssertEqual(after.count, 2)

        // Fresh repo instance reading the same backing dir should see persisted data.
        let repo2 = await makeRepo()
        let loaded = await repo2.load(accountId: id)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.weeklyUtilization, 10)
        XCTAssertEqual(loaded.last?.weeklyUtilization, 11)
    }

    func test_weeklyReset_dropsPriorHistory() async {
        let repo = await makeRepo()
        let id = UUID()
        let oldResetAt = Date().addingTimeInterval(3 * 24 * 3600)
        let newResetAt = oldResetAt.addingTimeInterval(7 * 24 * 3600)
        _ = await repo.append(PacingSnapshot(timestamp: Date(), weeklyUtilization: 50, weeklyResetAt: oldResetAt), accountId: id)
        _ = await repo.append(PacingSnapshot(timestamp: Date().addingTimeInterval(60), weeklyUtilization: 55, weeklyResetAt: oldResetAt), accountId: id)

        // New reset_at jumps forward → prior history must be cleared.
        let after = await repo.append(
            PacingSnapshot(timestamp: Date().addingTimeInterval(120), weeklyUtilization: 2, weeklyResetAt: newResetAt),
            accountId: id
        )
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.weeklyResetAt, newResetAt)
    }

    func test_purge_clearsHistory() async {
        let repo = await makeRepo()
        let id = UUID()
        _ = await repo.append(
            PacingSnapshot(timestamp: Date(), weeklyUtilization: 5, weeklyResetAt: Date().addingTimeInterval(86400)),
            accountId: id
        )

        await repo.purge(accountId: id)
        let loaded = await repo.load(accountId: id)
        XCTAssertTrue(loaded.isEmpty)
    }

    private func makeRepo() async -> PacingHistoryRepository {
        // Inject a dedicated test directory via a custom FileManager subclass.
        let fm = TestFileManager(applicationSupportDirectory: tempDir)
        return PacingHistoryRepository(fileManager: fm)
    }
}

/// Returns a custom Application Support directory so test runs don't pollute the real one.
private final class TestFileManager: FileManager, @unchecked Sendable {
    private let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        if directory == .applicationSupportDirectory {
            return [applicationSupportDirectory]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
