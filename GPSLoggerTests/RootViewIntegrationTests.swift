import XCTest
import SwiftUI
import CoreLocation
import SwiftData
@testable import GPSLogger

/// QA-S3-001 の回帰防止テスト。
///
/// Sprint 3 の QA で「MapView 内で LocationService を生成すると AppSettings /
/// placeProvider が DI されず、自宅判定 / SLC / MKLocalSearch が本番経路で無効化される」
/// 統合バグが見つかった。修正として RootView 側で LocationService を生成し、
/// AppSettings と同じインスタンスを LocationService に DI している。
///
/// 本テストでは LocationService の生成口（RootView の init 相当）が
/// 「AppSettings を伴った構築」で機能するかをユニットテスト相当で再現する。
@MainActor
final class RootViewIntegrationTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run { retainedContainers.removeAll() }
        try await super.tearDown()
    }

    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    /// RootView 相当の構築（AppSettings + LocationService の同居）で
    /// 自宅判定が有効化されることを検証する。
    func test_locationService_constructedWithAppSettings_enablesHomeDetection() throws {
        let repo = try makeInMemoryRepository()

        // RootView.init() と同じ生成順序を再現
        let suiteName = "gpslogger.tests.rootview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.homeLocation = HomeLocation(latitude: 35.681236,
                                             longitude: 139.767125,
                                             address: "Home")
        settings.homeRadiusMeters = 100

        let sut = LocationService(repository: repo,
                                  placeProvider: nil,
                                  appSettings: settings)

        // 自宅座標を流す → atHome 状態になる
        let homeLoc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.681236,
                                                                   longitude: 139.767125),
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                 timestamp: Date())
        sut._ingestForTesting([homeLoc])

        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome,
                       "RootView 経路で AppSettings を DI した LocationService は自宅判定が動く")
        XCTAssertEqual(sut.atHomeSkipCount, 1,
                       "atHome 状態で RoutePoint がスキップされている")

        // 自宅外座標を流す → away に遷移して RoutePoint 永続化が再開する
        let awayLoc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.700000,
                                                                   longitude: 139.767125),
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                 timestamp: Date().addingTimeInterval(60))
        sut._ingestForTesting([awayLoc])

        XCTAssertEqual(sut._lastHomeStateForTesting, .away)

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let unwrapped = try XCTUnwrap(trip)
        XCTAssertEqual(unwrapped.routePoints.count, 1,
                       "away 遷移後の点が永続化されている（自宅滞在中の点はスキップ）")
    }

    // MARK: - QA-S5-001 / QA-S5-002 回帰防止: CloudUploadCoordinator の DI

    /// QA-S5-001 で検出された「RootView が CloudUploadCoordinator を生成・注入していない」
    /// 統合バグの回帰防止テスト。
    ///
    /// Sprint 5 のスプリントゴール検証条件 #2 を満たすには:
    /// - RootView で CloudUploadCoordinator を生成し、LocationService に注入する
    /// - LocationService.stopUpdatingLocation が triggerCloudUploadIfNeeded を呼び、
    ///   Coordinator.uploadIfEnabled が actor 越しに走る
    ///
    /// 本テストでは RootView と同じ生成順序で各依存を組み立て、
    /// stopUpdatingLocation を起動した結果 CloudUploadCoordinator が呼ばれることを検証する。
    func test_locationService_stopRecording_invokesCloudUploadCoordinator_QA_S5_001() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        let context = container.mainContext
        let repo = TripRepository(modelContext: context)

        let suiteName = "gpslogger.tests.rootview.qa-s5-001.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.cloudProviderKind = .googleDrive
        settings.cloudAutoSyncEnabled = true

        // RootView と同パターンの DI（QA-S5-001 修正後の生成順序）
        let stubProvider = SpyCloudProvider()
        let providers: [CloudProviderKind: any CloudStorageProvider] = [.googleDrive: stubProvider]
        let coordinator = CloudUploadCoordinator(
            providers: providers,
            appSettings: settings,
            csvExporter: SpyCSVExporter()
        )
        let manager = SpyLocationManager()
        let sut = LocationService(manager: manager,
                                  repository: repo,
                                  placeProvider: nil,
                                  appSettings: settings,
                                  cloudUploadCoordinator: coordinator)

        // 当日の TripRecord を確保し、LocationService 内部の currentTrip を確定させる
        _ = try repo.todayTrip()
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7),
                             altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                             timestamp: Date())
        sut._ingestForTesting([loc])

        // 記録を開始（@isUpdating を true に倒す） → 停止して triggerCloudUploadIfNeeded を発火
        // SpyLocationManager.startUpdatingLocation は no-op だが LocationService 内部で
        // isUpdating = true になる（stopUpdatingLocation で false に戻り、その時点で発火）
        sut.startUpdatingLocation()
        sut.stopUpdatingLocation()

        // Task @MainActor 越しの非同期実行を待つ
        for _ in 0..<40 {
            if await stubProvider.uploadCount > 0 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let count = await stubProvider.uploadCount
        XCTAssertGreaterThanOrEqual(count, 1,
            "RootView 経路で DI された CloudUploadCoordinator が記録停止時にアップロードを発火する（QA-S5-001 回帰防止）")

        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Spy doubles (QA-S5-001 回帰防止用)

private actor SpyCloudProvider: CloudStorageProvider {
    nonisolated var kind: CloudProviderKind { .googleDrive }
    private(set) var uploadCount: Int = 0

    @MainActor func isAuthenticated() async -> Bool { true }
    @MainActor func authenticate() async throws {}
    @MainActor func signOut() {}

    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult {
        uploadCount += 1
        return CloudUploadResult(fileID: "spy", path: path, webViewLink: nil)
    }
}

@MainActor
private struct SpyCSVExporter: CSVExporting {
    func csvData(for trip: TripRecord) throws -> Data {
        Data("spy".utf8)
    }
}

private final class SpyLocationManager: NSObject, LocationProviderProtocol, @unchecked Sendable {
    weak var delegate: CLLocationManagerDelegate?
    var distanceFilter: CLLocationDistance = 10
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = false
    var showsBackgroundLocationIndicator: Bool = false
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
}

// MARK: - DI 経路カバレッジ（Sprint 6 / S6-001 で定型化）
//
// 新規サービス（class / actor / struct）または新規 @Model（SwiftData）を追加した場合、
// または既存サービスに新しい依存・起動時処理を足した場合は、ここに統合テストケースを追加すること。
// .scrum/process/dev-completion-checklist.md「8. 新規サービス / 新規 @Model 追加時の
// DI 経路カバレッジ」に詳細ルールあり。
//
// 最低限の検証 4 項目:
//   1. RootView.init 内で当該サービスがインスタンス化されているか（または注入されているか）
//   2. 依存先（LocationService 等）に正しく注入され、本番経路で nil にならないか
//   3. .task / onAppear / applicationDidBecomeActive で起動時処理が発火するか
//   4. AppSettings に新規プロパティを追加した場合、既定値が想定通りで UserDefaults 未設定時にも安全に動くか
//
// テスト名の規約:
//   test_<対象機能>_<期待動作>_<ticket_id>
//   例: test_locationService_stopRecording_invokesCloudUploadCoordinator_QA_S5_001
//
// Spy / Stub double はテストファイル内に private で書く
// （既存の SpyCloudProvider / SpyCSVExporter / SpyLocationManager を参考にする）。
//
// Actor / @MainActor 隔離型サービスは
//   await Task.yield()
//   try? await Task.sleep(nanoseconds: 20_000_000)
// でイベントループを進めて非同期処理の完了を待つ。
//
// 過去事例（再発防止対象）:
//   Sprint 3 QA-S3-001（PlaceLookupService 依存漏れ）
//   Sprint 4 QA-S4-001（CalendarSyncService 依存漏れ）
//   Sprint 5 QA-S5-001/002（CloudUploadCoordinator / RetryQueue 依存漏れ + .task 起動漏れ）
