import XCTest
import SwiftData
@testable import GPSLogger

/// S5-006 のユニットテスト: CloudUploadRetryQueue の永続化・指数バックオフ・5 回失敗通知・
/// ネットワーク回復時の自動実行を検証する。
@MainActor
final class CloudUploadRetryQueueTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CloudUploadRetryQueueTests-\(UUID().uuidString)"
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

    private func makeQueue(provider: any CloudStorageProvider = StubProvider(),
                           notifier: StubNotifier = StubNotifier(),
                           networkObserver: StubNetworkObserver = StubNetworkObserver())
        throws -> (CloudUploadRetryQueue, ModelContainer, TripRepository, StubNotifier, StubNetworkObserver, StubProvider)
    {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        let context = container.mainContext
        let repo = TripRepository(modelContext: context)
        let settings = AppSettings(defaults: defaults)
        let stubProvider = (provider as? StubProvider) ?? StubProvider()
        let queue = CloudUploadRetryQueue(
            modelContext: context,
            tripRepository: repo,
            providers: [.googleDrive: stubProvider],
            csvExporter: StubCSVExporter(),
            appSettings: settings,
            notifier: notifier,
            networkObserver: networkObserver
        )
        return (queue, container, repo, notifier, networkObserver, stubProvider)
    }

    // MARK: - (1) enqueue → 永続化 → 成功 → 削除

    func test_enqueue_persistsAndProcessNow_removesEntryOnSuccess_S5_006() async throws {
        let (queue, _, repo, _, _, provider) = try makeQueue()

        // TripRecord を作っておく
        let trip = try repo.todayTrip()
        try await queue.enqueue(tripDate: trip.date,
                                providerKind: .googleDrive,
                                lastError: .networkFailure(message: "offline"))

        // 永続化されている
        let pendingCountBefore = try queue.pendingCount()
        XCTAssertEqual(pendingCountBefore, 1)

        // processNow で成功
        provider.uploadResult = .success
        let succeeded = try await queue.processNow()
        XCTAssertEqual(succeeded, 1)
        let pendingCountAfter = try queue.pendingCount()
        XCTAssertEqual(pendingCountAfter, 0, "成功したエントリは削除される")
    }

    // MARK: - (2) 5 回失敗で通知発火（重複なし）

    func test_processNow_firesNotificationOnFifthFailure_S5_006() async throws {
        let stubProvider = StubProvider()
        stubProvider.uploadResult = .failure(.networkFailure(message: "offline"))
        let notifier = StubNotifier()
        let (queue, _, repo, _, _, _) = try makeQueue(provider: stubProvider, notifier: notifier)

        let trip = try repo.todayTrip()

        // 初回 enqueue（CloudUploadCoordinator からの 1 回目失敗）
        try await queue.enqueue(tripDate: trip.date,
                                providerKind: .googleDrive,
                                lastError: .networkFailure(message: "offline"))

        // processNow を 4 回呼ぶ → 1 回の enqueue + 4 回の processNow = 5 回失敗
        for _ in 0..<4 {
            _ = try await queue.processNow()
        }

        let count = await notifier.notifyCount
        XCTAssertEqual(count, 1, "5 回失敗で 1 回だけ通知発火")

        // さらに processNow を呼んでも 2 回目以降の通知は来ない
        _ = try await queue.processNow()
        let count2 = await notifier.notifyCount
        XCTAssertEqual(count2, 1, "通知は重複しない")
    }

    // MARK: - (3) ネットワーク回復で processQueue が自動実行される

    func test_startObservingNetwork_processesQueueOnPathSatisfied_S5_006() async throws {
        let stubProvider = StubProvider()
        stubProvider.uploadResult = .success
        let observer = StubNetworkObserver()
        let (queue, _, repo, _, _, _) = try makeQueue(provider: stubProvider, networkObserver: observer)
        let trip = try repo.todayTrip()
        try await queue.enqueue(tripDate: trip.date,
                                providerKind: .googleDrive,
                                lastError: .networkFailure(message: "offline"))

        queue.startObservingNetwork()
        // 復旧イベント
        await observer.simulatePathChange(satisfied: true)

        // 非同期処理の完了を待つ
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let pendingCount = try queue.pendingCount()
        XCTAssertEqual(pendingCount, 0, "ネットワーク回復で処理されエントリが削除される")
    }

    // MARK: - (4) バッジ表示用件数取得

    func test_pendingCount_reflectsEnqueueAndDelete_S5_006() async throws {
        let (queue, _, repo, _, _, _) = try makeQueue()
        XCTAssertEqual(try queue.pendingCount(), 0)

        let trip = try repo.todayTrip()
        try await queue.enqueue(tripDate: trip.date,
                                providerKind: .googleDrive,
                                lastError: .networkFailure(message: "offline"))
        XCTAssertEqual(try queue.pendingCount(), 1)
    }

    // MARK: - (5) 指数バックオフの計算

    func test_nextRetryDate_returnsCorrectBackoff_S5_006() throws {
        let (queue, _, _, _, _, _) = try makeQueue()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // retryCount = 1 → 30 秒後（インデックス [1] = 60 秒）
        // 注: backoffSeconds[1] = 60 秒（受け入れ条件 30s → 1m → 2m → 5m → 10m）
        // インデックスは 0:30s, 1:60s, 2:120s, 3:300s, 4:600s
        let p0 = PendingUpload(tripDate: Date(), providerKind: .googleDrive,
                               retryCount: 0, lastTriedAt: base)
        XCTAssertEqual(queue.nextRetryDate(for: p0).timeIntervalSince(base), 30, accuracy: 0.1)

        let p1 = PendingUpload(tripDate: Date(), providerKind: .googleDrive,
                               retryCount: 1, lastTriedAt: base)
        XCTAssertEqual(queue.nextRetryDate(for: p1).timeIntervalSince(base), 60, accuracy: 0.1)

        let p4 = PendingUpload(tripDate: Date(), providerKind: .googleDrive,
                               retryCount: 4, lastTriedAt: base)
        XCTAssertEqual(queue.nextRetryDate(for: p4).timeIntervalSince(base), 600, accuracy: 0.1)

        // インデックス上限を超えても 600 秒に貼り付く
        let p10 = PendingUpload(tripDate: Date(), providerKind: .googleDrive,
                                retryCount: 10, lastTriedAt: base)
        XCTAssertEqual(queue.nextRetryDate(for: p10).timeIntervalSince(base), 600, accuracy: 0.1)
    }

    // MARK: - (6) 同じ tripDate で enqueue した場合は retryCount を加算

    func test_enqueue_aggregatesByTripDate_S5_006() async throws {
        let (queue, _, repo, _, _, _) = try makeQueue()
        let trip = try repo.todayTrip()

        try await queue.enqueue(tripDate: trip.date, providerKind: .googleDrive,
                                lastError: .networkFailure(message: "x"))
        try await queue.enqueue(tripDate: trip.date, providerKind: .googleDrive,
                                lastError: .networkFailure(message: "y"))

        XCTAssertEqual(try queue.pendingCount(), 1, "同じ tripDate なら 1 件に集約")
    }
}

// MARK: - Test doubles

private final class StubProvider: CloudStorageProvider, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(CloudStorageError)
    }
    var kind: CloudProviderKind { .googleDrive }
    var uploadResult: Outcome = .failure(.networkFailure(message: "offline"))

    @MainActor func isAuthenticated() async -> Bool { true }
    @MainActor func authenticate() async throws {}
    @MainActor func signOut() {}

    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult {
        switch uploadResult {
        case .success:
            return CloudUploadResult(fileID: "ok", path: path, webViewLink: nil)
        case .failure(let error):
            throw error
        }
    }
}

private struct StubCSVExporter: CSVExporting {
    func csvData(for trip: TripRecord) throws -> Data {
        Data("csv".utf8)
    }
}

private actor StubNotifier: UploadFailureNotifying {
    private(set) var notifyCount: Int = 0
    func notifyFinalFailure(tripDate: Date, providerKind: CloudProviderKind) async {
        notifyCount += 1
    }
}

private final class StubNetworkObserver: NetworkPathObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((Bool) -> Void)?

    func startObserving(onPathChange: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        handler = onPathChange
        lock.unlock()
    }

    func stopObserving() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func simulatePathChange(satisfied: Bool) async {
        let h = lock.withLock { handler }
        h?(satisfied)
    }
}
