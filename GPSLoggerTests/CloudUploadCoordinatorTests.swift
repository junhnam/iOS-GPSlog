import XCTest
import SwiftData
@testable import GPSLogger

/// S5-005 のユニットテスト: CloudUploadCoordinator が自動同期 ON/OFF / プロバイダ選択 /
/// 階層パス組み立て / リトライキュー連携を正しくハンドルすることを検証する。
@MainActor
final class CloudUploadCoordinatorTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CloudUploadCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        await MainActor.run {
            retainedContainers.removeAll()
        }
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    private func makeSettings(autoSync: Bool, kind: CloudProviderKind?) -> AppSettings {
        let s = AppSettings(defaults: defaults)
        s.cloudAutoSyncEnabled = autoSync
        s.cloudProviderKind = kind
        return s
    }

    private func makeTrip(date: Date = Date(timeIntervalSince1970: 1_762_300_800)) -> TripRecord {
        // 2025-11-05 0:00 (UTC) 相当の固定日付
        return TripRecord(date: date, startedAt: date)
    }

    // MARK: - (1) 自動同期 OFF で no-op

    func test_uploadIfEnabled_skipsWhenAutoSyncOff() async {
        let settings = makeSettings(autoSync: false, kind: .googleDrive)
        let provider = StubCloudProvider()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: StubCSVExporter()
        )
        let outcome = await sut.uploadIfEnabled(for: makeTrip())
        if case .skipped(let reason) = outcome {
            XCTAssertTrue(reason.contains("cloudAutoSyncEnabled"))
        } else {
            XCTFail("OFF なら .skipped 期待")
        }
        XCTAssertEqual(provider.uploadedPaths, [])
    }

    // MARK: - (2) プロバイダ未選択で no-op

    func test_uploadIfEnabled_skipsWhenProviderKindNil() async {
        let settings = makeSettings(autoSync: true, kind: nil)
        let provider = StubCloudProvider()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: StubCSVExporter()
        )
        let outcome = await sut.uploadIfEnabled(for: makeTrip())
        if case .skipped(let reason) = outcome {
            XCTAssertTrue(reason.contains("cloudProviderKind"))
        } else {
            XCTFail("プロバイダ未選択なら .skipped")
        }
    }

    // MARK: - (3) ON + Google Drive でアップロード成功

    func test_uploadIfEnabled_uploadsCSV_whenAutoSyncOnAndProviderResolved() async throws {
        let settings = makeSettings(autoSync: true, kind: .googleDrive)
        let provider = StubCloudProvider()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: StubCSVExporter(payload: "csv-data".data(using: .utf8)!)
        )
        let trip = makeTrip()
        let outcome = await sut.uploadIfEnabled(for: trip)
        if case .uploaded(let result) = outcome {
            XCTAssertTrue(result.path.hasPrefix("GPSログ/"))
            XCTAssertTrue(result.path.hasSuffix("/data.csv"))
        } else {
            XCTFail("成功で .uploaded 期待: \(outcome)")
        }
        XCTAssertEqual(provider.uploadedPaths.count, 1)
        XCTAssertEqual(provider.uploadedPaths.first?.hasPrefix("GPSログ/"), true)
        XCTAssertEqual(provider.uploadedDataPayloads.first, "csv-data".data(using: .utf8))
    }

    // MARK: - (4) パス組み立て

    func test_pathFor_returnsExpectedHierarchy() throws {
        let settings = makeSettings(autoSync: true, kind: .googleDrive)
        let sut = CloudUploadCoordinator(
            providers: [:],
            appSettings: settings,
            csvExporter: StubCSVExporter()
        )

        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 6
        components.timeZone = TimeZone.current
        let date = Calendar.current.date(from: components)!
        let trip = TripRecord(date: date, startedAt: date)

        let path = sut.pathFor(trip: trip)
        XCTAssertEqual(path, "GPSログ/2026-05-06/data.csv",
                       "S5-005: GPSログ/{YYYY-MM-DD}/data.csv 階層")
    }

    // MARK: - (5) アップロード失敗 → リトライキューに enqueue

    func test_uploadIfEnabled_enqueuesIntoRetryQueue_whenNetworkFailure() async {
        let settings = makeSettings(autoSync: true, kind: .googleDrive)
        let provider = StubCloudProvider()
        provider.errorOnUpload = .networkFailure(message: "offline")
        let queue = StubRetryQueue()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: StubCSVExporter(),
            retryQueue: queue
        )
        let outcome = await sut.uploadIfEnabled(for: makeTrip())
        if case .failed(let err, let enqueued) = outcome {
            XCTAssertEqual(err, .networkFailure(message: "offline"))
            XCTAssertTrue(enqueued, "ネットワーク失敗は enqueue される")
        } else {
            XCTFail("失敗で .failed 期待: \(outcome)")
        }
        let enqueuedCount = await queue.enqueueCount
        XCTAssertEqual(enqueuedCount, 1)
    }

    // MARK: - (6) 認証エラーは enqueue しない

    func test_uploadIfEnabled_doesNotEnqueue_whenAuthExpired() async {
        let settings = makeSettings(autoSync: true, kind: .googleDrive)
        let provider = StubCloudProvider()
        provider.errorOnUpload = .authenticationExpired
        let queue = StubRetryQueue()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: StubCSVExporter(),
            retryQueue: queue
        )
        let outcome = await sut.uploadIfEnabled(for: makeTrip())
        if case .failed(let err, let enqueued) = outcome {
            XCTAssertEqual(err, .authenticationExpired)
            XCTAssertFalse(enqueued, "認証期限切れは enqueue しない（再認証が必要）")
        } else {
            XCTFail("失敗で .failed 期待")
        }
        let enqueuedCount = await queue.enqueueCount
        XCTAssertEqual(enqueuedCount, 0)
    }

    // MARK: - (7) 同じパスへの上書き想定

    func test_uploadIfEnabled_uploadsToSamePath_whenCalledTwiceForSameDate() async {
        let settings = makeSettings(autoSync: true, kind: .googleDrive)
        let provider = StubCloudProvider()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: StubCSVExporter()
        )
        let trip = makeTrip()
        _ = await sut.uploadIfEnabled(for: trip)
        _ = await sut.uploadIfEnabled(for: trip)
        XCTAssertEqual(provider.uploadedPaths.count, 2)
        XCTAssertEqual(provider.uploadedPaths[0], provider.uploadedPaths[1],
                       "同じ日付なら同じパスに 2 回アップロードされる（プロバイダ側で上書き）")
    }
}

// MARK: - Test doubles

private final class StubCloudProvider: CloudStorageProvider, @unchecked Sendable {
    var kind: CloudProviderKind { .googleDrive }
    private(set) var uploadedPaths: [String] = []
    private(set) var uploadedDataPayloads: [Data] = []
    var errorOnUpload: CloudStorageError?

    @MainActor
    func isAuthenticated() async -> Bool { true }

    @MainActor
    func authenticate() async throws {}

    @MainActor
    func signOut() {}

    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult {
        if let error = errorOnUpload {
            throw error
        }
        uploadedPaths.append(path)
        uploadedDataPayloads.append(data)
        return CloudUploadResult(fileID: "stub-\(uploadedPaths.count)", path: path, webViewLink: nil)
    }
}

private struct StubCSVExporter: CSVExporting {
    var payload: Data = Data("stub".utf8)
    func csvData(for trip: TripRecord) throws -> Data {
        return payload
    }
}

private actor StubRetryQueue: CloudUploadRetryEnqueuing {
    private(set) var enqueueCount: Int = 0

    func enqueue(tripDate: Date, providerKind: CloudProviderKind, lastError: CloudStorageError) async throws {
        enqueueCount += 1
    }
}
