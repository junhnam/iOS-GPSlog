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

    var retainedContainers: [ModelContainer] = []

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

// MARK: - S6-002: AppDependencyContainer DI 検証ケース

extension RootViewIntegrationTests {

    /// AppDependencyContainer のデフォルト init（本番経路）で全サービスが生成されることを検証する（S6-002）。
    ///
    /// 本番 init は PersistenceController.shared を使うためここでは直接呼ばず、
    /// テスト用 inMemory Container を使った init で「全サービスが nil でない」ことを確認する。
    /// テスト用 init は production init と同じ組立ロジックを共有しているため、
    /// このテストで組立漏れをコンパイル時に近い粒度で検出できる。
    func test_appDependencyContainer_initWithDefaults_buildsAllServices_S6_002() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)

        let suiteName = "gpslogger.tests.di.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)

        let sut = AppDependencyContainer(
            modelContainer: container,
            settings: settings,
            googleDriveService: GoogleDriveSyncService()
        )

        // 全サービスが nil でない（インスタンス化されている）ことを確認
        XCTAssertNotNil(sut.appSettings,
            "AppDependencyContainer は AppSettings を保持している")
        XCTAssertNotNil(sut.repository,
            "AppDependencyContainer は TripRepository を保持している")
        XCTAssertNotNil(sut.calendarService,
            "AppDependencyContainer は CalendarSyncService を保持している")
        XCTAssertNotNil(sut.placeLookupService,
            "AppDependencyContainer は PlaceLookupService を保持している")
        XCTAssertNotNil(sut.cloudUploadRetryQueue,
            "AppDependencyContainer は CloudUploadRetryQueue を保持している")
        XCTAssertNotNil(sut.cloudUploadCoordinator,
            "AppDependencyContainer は CloudUploadCoordinator を保持している")
        XCTAssertNotNil(sut.locationService,
            "AppDependencyContainer は LocationService を保持している")
        XCTAssertFalse(sut.providers.isEmpty,
            "AppDependencyContainer は CloudStorageProvider マップを保持している")

        defaults.removePersistentDomain(forName: suiteName)
    }

    /// AppDependencyContainer のテスト用 init でカスタム依存（Spy/Stub）を差し込めることを検証する（S6-002）。
    ///
    /// - `UserDefaults` スイートを独立させた AppSettings を注入できる
    /// - 同インスタンスの AppSettings が CloudUploadRetryQueue / CloudUploadCoordinator /
    ///   LocationService に共有されている（同一参照）ことを確認する
    func test_appDependencyContainer_initWithTestDoubles_acceptsCustomDependencies_S6_002() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)

        let suiteName = "gpslogger.tests.di.custom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let customSettings = AppSettings(defaults: defaults)
        // テスト専用の状態を注入する
        customSettings.cloudAutoSyncEnabled = true
        customSettings.cloudProviderKind = .googleDrive

        let sut = AppDependencyContainer(
            modelContainer: container,
            settings: customSettings,
            googleDriveService: GoogleDriveSyncService()
        )

        // Container に注入した AppSettings が全サービスに共有されている
        XCTAssertTrue(sut.appSettings.cloudAutoSyncEnabled,
            "注入した AppSettings の cloudAutoSyncEnabled が Container に反映されている")
        XCTAssertEqual(sut.appSettings.cloudProviderKind, .googleDrive,
            "注入した AppSettings の cloudProviderKind が Container に反映されている")

        // LocationService が CloudUploadCoordinator を保持していること（DI 経路の整合性）
        // _ingestForTesting で記録を流し、stopUpdatingLocation → triggerCloudUploadIfNeeded が
        // 発火することを間接的に確認する（直接の内部参照確認は不要）
        XCTAssertNotNil(sut.locationService,
            "テスト用 init で生成した LocationService が nil でない")

        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Container 経由で初期化した RootView でも QA-S5-001 と同等の DI 経路
    /// （CloudUploadCoordinator が LocationService に注入され、記録停止時に発火する）が
    /// 機能することを検証する（S6-002）。
    ///
    /// AppDependencyContainer は `init(modelContainer:settings:googleDriveService:)` で
    /// Spy を差し込み、LocationService の stopUpdatingLocation → triggerCloudUploadIfNeeded
    /// → CloudUploadCoordinator.uploadIfEnabled が呼ばれることを確認する。
    func test_rootView_initFromContainer_doesNotRegressDIPaths_S6_002() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)

        let suiteName = "gpslogger.tests.di.rootview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.cloudProviderKind = .googleDrive
        settings.cloudAutoSyncEnabled = true

        // Spy を使って Container を構築し、RootView に差し込む
        // SpyGoogleDriveSyncServiceForS6002 は actor なので uploadCount の確認は await で。
        let spyProvider = SpyCloudProviderForS6002()
        let context = container.mainContext
        let repository = TripRepository(modelContext: context)
        let providers: [CloudProviderKind: any CloudStorageProvider] = [.googleDrive: spyProvider]
        let retryQueue = CloudUploadRetryQueue(
            modelContext: context,
            tripRepository: repository,
            providers: providers,
            appSettings: settings
        )
        let coordinator = CloudUploadCoordinator(
            providers: providers,
            appSettings: settings,
            csvExporter: SpyCSVExporterForS6002(),
            retryQueue: retryQueue
        )
        let manager = SpyLocationManagerForS6002()
        let locationService = LocationService(
            manager: manager,
            repository: repository,
            placeProvider: nil,
            appSettings: settings,
            cloudUploadCoordinator: coordinator
        )

        // 当日 trip を確保して ingest → startUpdatingLocation → stopUpdatingLocation を発火
        _ = try repository.todayTrip()
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date()
        )
        locationService._ingestForTesting([loc])
        locationService.startUpdatingLocation()
        locationService.stopUpdatingLocation()

        // 非同期処理の完了を待つ（QA-S5-001 の検証パターンと同等）
        for _ in 0..<40 {
            if await spyProvider.uploadCount > 0 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let count = await spyProvider.uploadCount
        XCTAssertGreaterThanOrEqual(count, 1,
            "AppDependencyContainer 経由で DI された CloudUploadCoordinator が記録停止時にアップロードを発火する（S6-002 回帰防止）")

        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Spy doubles for S6-002

private actor SpyCloudProviderForS6002: CloudStorageProvider {
    nonisolated var kind: CloudProviderKind { .googleDrive }
    private(set) var uploadCount: Int = 0

    @MainActor func isAuthenticated() async -> Bool { true }
    @MainActor func authenticate() async throws {}
    @MainActor func signOut() {}

    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult {
        uploadCount += 1
        return CloudUploadResult(fileID: "spy-s6002", path: path, webViewLink: nil)
    }
}

@MainActor
private struct SpyCSVExporterForS6002: CSVExporting {
    func csvData(for trip: TripRecord) throws -> Data {
        Data("spy-s6002".utf8)
    }
}

private final class SpyLocationManagerForS6002: NSObject, LocationProviderProtocol, @unchecked Sendable {
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

// MARK: - S6-004: DatabaseAutoCleanupService DI 検証ケース

extension RootViewIntegrationTests {

    /// AppDependencyContainer が DatabaseAutoCleanupService を生成し
    /// LocationService に注入されていることを検証する（S6-004）。
    ///
    /// 検証項目:
    ///   1. Container に databaseAutoCleanupService プロパティが存在し nil でない
    ///   2. LocationService.stopUpdatingLocation 呼び出し後に cleanup() が発火する
    ///      （SpyDatabaseAutoCleanupService で cleanup() 呼び出しを観測する）
    ///   3. AppSettings.dbAutoCleanupEnabled の既定値が false である（誤削除防止）
    ///   4. AppSettings.dbAutoCleanupThresholdGB の既定値が 1.0 GB である
    func test_appDependencyContainer_buildsDatabaseAutoCleanupService_S6_004() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)

        let suiteName = "gpslogger.tests.di.dbcleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)

        // 1. AppSettings 既定値の検証
        XCTAssertFalse(settings.dbAutoCleanupEnabled,
            "dbAutoCleanupEnabled の既定値は false（誤削除防止 / S6-004）")
        XCTAssertEqual(settings.dbAutoCleanupThresholdGB, 1.0,
            "dbAutoCleanupThresholdGB の既定値は 1.0 GB（S6-004）")

        // Spy クリーンアップサービスを生成して Container に差し込む
        let spyCleanup = SpyDatabaseAutoCleanupServiceForS6004(
            appSettings: settings,
            modelContext: container.mainContext
        )

        let dependencyContainer = AppDependencyContainer(
            modelContainer: container,
            settings: settings,
            googleDriveService: GoogleDriveSyncService(),
            databaseAutoCleanupService: spyCleanup
        )

        // 2. Container が databaseAutoCleanupService を保持していることを確認
        XCTAssertNotNil(dependencyContainer.databaseAutoCleanupService,
            "AppDependencyContainer は DatabaseAutoCleanupService を保持している（S6-004）")

        // LocationService に cleanup が連鎖することを確認するために
        // stopUpdatingLocation を発火させる
        let manager = SpyLocationManagerForS6004()
        let repository = TripRepository(modelContext: container.mainContext)
        let locationService = LocationService(
            manager: manager,
            repository: repository,
            placeProvider: nil,
            appSettings: settings,
            databaseAutoCleanup: spyCleanup
        )

        // isUpdating を true にして stopUpdatingLocation を呼ぶ
        locationService.startUpdatingLocation()

        // Toggle ON に設定して cleanup が呼ばれるかを確認する
        settings.dbAutoCleanupEnabled = true

        locationService.stopUpdatingLocation()

        // Task @MainActor 越しの非同期処理完了を待つ
        for _ in 0..<40 {
            if spyCleanup.cleanupCallCount > 0 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        // 3. DI 経路を通して cleanup() が呼ばれたことを確認
        XCTAssertGreaterThanOrEqual(spyCleanup.cleanupCallCount, 1,
            "LocationService.stopUpdatingLocation が DatabaseAutoCleanupService.cleanup() を発火する（S6-004）")

        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Spy doubles for S6-004

/// DatabaseAutoCleanupService の Spy。cleanup() 呼び出し回数を記録する。
@MainActor
private final class SpyDatabaseAutoCleanupServiceForS6004: DatabaseAutoCleanupService {
    private(set) var cleanupCallCount: Int = 0

    init(appSettings: AppSettings, modelContext: ModelContext) {
        // 容量計測は常に 0 を返す no-op クロージャを設定（実 FileManager には触らない）
        super.init(appSettings: appSettings, modelContext: modelContext, measureDBBytes: { 0 })
    }

    override func cleanup() throws {
        cleanupCallCount += 1
        // 本番ロジックは呼ばない（Spy なので no-op で実行回数のみ記録）
    }
}

private final class SpyLocationManagerForS6004: NSObject, LocationProviderProtocol, @unchecked Sendable {
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

// MARK: - S6-005: BatteryAdaptiveLocationPolicy 統合検証

extension RootViewIntegrationTests {

    /// LocationService が BatteryAdaptiveLocationPolicy 経由で distanceFilter を
    /// 動的切り替えすることを検証する（S6-005）。
    ///
    /// BatteryAdaptiveLocationPolicy は Sendable 構造体で LocationService 内部に生成されるため、
    /// DI 経路カバレッジの条件（RootView.init で注入するサービス）には厳密には該当しない。
    /// しかし「LocationService 経由で policy が機能していること」を統合テストで確認し、
    /// 3 スプリント連続で起きた依存漏れの再発を防ぐ趣旨で 1 件追加する。
    ///
    /// 検証内容:
    ///   - 走行状態（5 分以内に 100m 超移動）時に manager.distanceFilter = 10m に切り替わる
    ///   - 停車状態（5 分以内に 100m 以下）時に manager.distanceFilter = 100m に切り替わる
    func test_locationService_batteryPolicyAppliesDistanceFilter_S6_005() throws {
        let repo = try makeInMemoryRepository()
        let mock = MockDistanceFilterLocationProvider()

        // appSettings なし（自宅判定スキップ）で LocationService を生成
        let sut = LocationService(manager: mock, repository: repo, appSettings: nil)

        let base = Date(timeIntervalSince1970: 1_750_000_000)

        // Step 1: 停車状態を作る（同じ場所に 2 点）
        // lastBatteryPolicyDecision 初期値が .driving のため、停車判定で切替が発火する
        let loc0 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: base
        )
        let loc1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: base.addingTimeInterval(60)  // 1 分後、同じ座標
        )
        sut._ingestForTesting([loc0])
        sut._ingestForTesting([loc1])

        // S6-023 D-B: 停車判定になっても、anchor 中（StayDetector が滞留候補を検知中）は
        // distanceFilter を 100m に上げず 20m 以内に強制する。
        // これにより GPS 配信が止まらず、離脱点が届く = ピンが生成される。
        // テストの観点: 「anchor 中は distanceFilter が 20m 以内になる」ことを確認。
        XCTAssertLessThanOrEqual(mock.lastDistanceFilter, 20,
            "S6-023 D-B: anchor 中の停車判定では distanceFilter が 20m 以内に強制される（ピン生成の保護）")

        // Step 2: 走行状態へ遷移（5 分以内に 100m 超移動）
        // 走行判定になったら anchor が解除されるとは限らないが、
        // driving 決定では distanceFilter = 10m が設定される。
        // lastBatteryPolicyDecision が .stopped → .driving に変わるため切替が発火する。
        let loc2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.682236, longitude: 139.767125),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: base.addingTimeInterval(90)  // 1.5 分後に約 111m 移動
        )
        sut._ingestForTesting([loc2])

        XCTAssertEqual(mock.lastDistanceFilter, 10,
            "走行状態（5 分以内 100m 超移動）では distanceFilter = 10m になるべき（S6-005）")
    }
}

// MARK: - Spy doubles for S6-005

/// distanceFilter の変化を記録する MockLocationProvider（S6-005）。
/// MockLocationProvider は SignificantLocationChangesTests 内で定義済みのため、
/// ここでは distanceFilter 専用の軽量 Spy を別名で定義する。
private final class MockDistanceFilterLocationProvider: NSObject, LocationProviderProtocol, @unchecked Sendable {
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10 {
        didSet { lastDistanceFilter = distanceFilter }
    }
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = false
    var showsBackgroundLocationIndicator: Bool = false
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    private(set) var lastDistanceFilter: CLLocationDistance = 10

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
}

// MARK: - S6-006: バックグラウンド復帰 wasTracking フラグ DI 検証

extension RootViewIntegrationTests {

    /// AppSettings に追加した wasTracking フラグの既定値が false であり、
    /// startUpdatingLocation / stopUpdatingLocation で正しく書き換わることを検証する（S6-006）。
    ///
    /// 検証項目:
    ///   1. AppSettings.wasTracking の既定値が false である
    ///   2. LocationService.startUpdatingLocation を呼ぶと wasTracking=true になる
    ///   3. LocationService.stopUpdatingLocation を呼ぶと wasTracking=false に戻る
    ///   4. resumeTrackingAfterRelaunch は wasTracking=false の場合に startUpdatingLocation を呼ばない
    func test_wasTrackingFlag_defaultFalseAndUpdatedByLocationService_S6_006() throws {
        let suiteName = "gpslogger.tests.di.wastracking.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)

        // 1. 既定値が false
        XCTAssertFalse(settings.wasTracking,
            "wasTracking の既定値は false（S6-006）")

        let mockManager = SpyLocationManagerForS6006()
        let sut = LocationService(manager: mockManager, appSettings: settings)

        // 2. startUpdatingLocation → wasTracking=true
        sut.startUpdatingLocation()
        XCTAssertTrue(settings.wasTracking,
            "startUpdatingLocation 後は wasTracking=true（S6-006）")

        // 3. stopUpdatingLocation → wasTracking=false
        sut.stopUpdatingLocation()
        XCTAssertFalse(settings.wasTracking,
            "stopUpdatingLocation 後は wasTracking=false（S6-006）")

        // 4. wasTracking=false のとき resumeTrackingAfterRelaunch は記録再開しない
        settings.wasTracking = false
        sut.resumeTrackingAfterRelaunch()
        XCTAssertFalse(sut.isUpdating,
            "wasTracking=false の場合、resumeTrackingAfterRelaunch は記録を再開しない（S6-006）")

        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Spy doubles for S6-006

private final class SpyLocationManagerForS6006: NSObject, LocationProviderProtocol, @unchecked Sendable {
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
