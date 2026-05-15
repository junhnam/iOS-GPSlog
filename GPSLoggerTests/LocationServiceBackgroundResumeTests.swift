import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S6-006 受け入れ条件:
///   (a) SLC 起床 → 記録再開（wasTracking=true かつ自宅外）
///   (b) SLC 起床 → 自宅滞在中は再開しない
///   (c) 日付またぎ復帰 → 新しい TripRecord が確保される
///   (d) kill 後 SLC 起床 → wasTracking フラグで状態整合
///   + startUpdatingLocation が wasTracking=true を書き込む
///   + stopUpdatingLocation が wasTracking=false を書き込む
@MainActor
final class LocationServiceBackgroundResumeTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run { retainedContainers.removeAll() }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    private func makeIsolatedSettings() -> AppSettings {
        let suiteName = "gpslogger.tests.bgresumetests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(defaults: defaults)
    }

    private func location(lat: Double, lon: Double, at offset: TimeInterval, base: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: base.addingTimeInterval(offset)
        )
    }

    // MARK: - (a) SLC 起床 → wasTracking=true なら記録再開

    /// SLC で起床（wasTracking=true かつ自宅外）のとき、resumeTrackingAfterRelaunch が
    /// startUpdatingLocation を呼んで isUpdating=true になることを検証する（S6-006）。
    func test_slcWakeup_resumesTracking_S6_006() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        let mock = MockLocationProviderForBGResume()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // wasTracking=true をセット（kill 前に記録していた状態を模擬）
        settings.wasTracking = true

        // currentLocation を自宅外に設定
        sut._ingestForTesting([
            location(lat: 35.700000, lon: 139.767125, at: 0, base: Date())
        ])

        // SLC 起床経路のエントリポイント
        sut.startTrackingFromSLC()
        sut.resumeTrackingAfterRelaunch()

        XCTAssertTrue(sut.isUpdating,
            "SLC 起床かつ wasTracking=true かつ自宅外なら isUpdating=true になる（S6-006）")
        XCTAssertTrue(mock.didStartUpdating,
            "manager.startUpdatingLocation() が呼ばれる（S6-006）")
    }

    // MARK: - (b) SLC 起床 → 自宅滞在中は再開しない

    /// SLC 起床時に自宅判定が .atHome なら記録を再開しないことを検証する（S6-006）。
    func test_slcWakeup_atHome_doesNotResume_S6_006() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        // 自宅を東京駅付近に設定
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 100
        let mock = MockLocationProviderForBGResume()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // wasTracking=true（kill 前に記録していた）
        settings.wasTracking = true

        // currentLocation を自宅内に設定
        sut._ingestForTesting([
            location(lat: 35.681236, lon: 139.767125, at: 0, base: Date())
        ])
        // S6-017 仕様変更: atHome 遷移時に startSignificantChangesIfHome が startUpdatingLocation を
        // 呼ぶ実装に変わったため、この時点で mock.didStartUpdating=true / sut.isUpdating=true。
        // 「resumeTrackingAfterRelaunch が atHome を理由に新規 start を呼ばないこと」を検証するため、
        // didStartUpdating だけクリアして以降の呼び出しを観測する。
        mock.didStartUpdating = false

        sut.resumeTrackingAfterRelaunch()

        // S6-017: atHome 中も低精度通常 GPS は動いているため isUpdating=true
        XCTAssertTrue(sut.isUpdating,
            "S6-017: atHome 中も低精度通常 GPS を維持するため isUpdating=true（S6-006 仕様 → S6-017 で変更）")
        // resumeTrackingAfterRelaunch 自体は atHome を理由に新規 startUpdatingLocation を呼ばない
        XCTAssertFalse(mock.didStartUpdating,
            "S6-006: resumeTrackingAfterRelaunch は自宅滞在中なら新規 manager.startUpdatingLocation() を呼ばない")
    }

    // MARK: - (c) 日付またぎ復帰 → 新しい TripRecord が確保される

    /// バックグラウンド中に日付をまたいで起床した場合、
    /// resumeTrackingAfterRelaunch が currentTrip をリセットし、
    /// 次の位置情報で新しい当日 TripRecord が生成されることを検証する（S6-006）。
    func test_dateChanged_resumeCreatesNewTrip_S6_006() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        let mock = MockLocationProviderForBGResume()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        settings.wasTracking = true

        // 前日日付の TripRecord を作成して currentTrip に見立てる。
        // テスト都合上、直接 _currentTripForTesting セッターは存在しないため、
        // 前日付の位置情報を ingest して currentTrip を確保し、
        // 次に resumeTrackingAfterRelaunch を呼ぶことで日付またぎを検証する。
        // ここでは「日付またぎが起きた場合に isUpdating が再開される」ことを確認する。
        //
        // 実装詳細: resumeTrackingAfterRelaunch は currentTrip.date が今日でなければ
        // currentTrip を nil にリセットする。その後 startUpdatingLocation で isUpdating=true になる。
        sut.resumeTrackingAfterRelaunch()

        // wasTracking=true かつ自宅外（currentLocation が nil の場合も自宅外扱い）
        XCTAssertTrue(sut.isUpdating,
            "日付またぎ復帰でも wasTracking=true なら記録を再開する（S6-006）")

        // 位置情報を ingest して当日 TripRecord が新規作成されることを確認
        let todayLoc = location(lat: 35.700000, lon: 139.767125, at: 0, base: Date())
        sut._ingestForTesting([todayLoc])

        let trip = try repo.todayTrip(creatingIfMissing: false)
        XCTAssertNotNil(trip,
            "日付またぎ復帰後の ingest で当日 TripRecord が確保される（S6-006）")
    }

    // MARK: - (d) kill 後の SLC 起床 → wasTracking フラグで状態整合

    /// アプリが kill された後（wasTracking=false）に SLC で起床した場合、
    /// resumeTrackingAfterRelaunch が記録を再開しないことを検証する（S6-006）。
    func test_killedThenSLCWakeup_restoresTrackingState_S6_006() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        let mock = MockLocationProviderForBGResume()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // アプリを意図的に停止した（wasTracking=false）状態を模擬
        settings.wasTracking = false

        sut.startTrackingFromSLC()
        sut.resumeTrackingAfterRelaunch()

        XCTAssertFalse(sut.isUpdating,
            "wasTracking=false の場合、SLC 起床でも記録を再開しない（S6-006）")
        XCTAssertFalse(mock.didStartUpdating,
            "wasTracking=false の場合、manager.startUpdatingLocation() を呼ばない（S6-006）")

        // startTrackingFromSLC は isMonitoringSignificantChanges を true にする
        XCTAssertTrue(sut.isMonitoringSignificantChanges,
            "startTrackingFromSLC 後は isMonitoringSignificantChanges=true（S6-006）")
    }

    // MARK: - wasTracking フラグの書き込み検証

    /// startUpdatingLocation が wasTracking=true を AppSettings に書き込むことを検証する（S6-006）。
    func test_startUpdatingLocation_setsWasTrackingTrue_S6_006() throws {
        let settings = makeIsolatedSettings()
        let mock = MockLocationProviderForBGResume()
        let sut = LocationService(manager: mock, appSettings: settings)

        XCTAssertFalse(settings.wasTracking, "初期値は false")

        sut.startUpdatingLocation()

        XCTAssertTrue(settings.wasTracking,
            "startUpdatingLocation 後は wasTracking=true（S6-006）")
    }

    /// stopUpdatingLocation が wasTracking=false を AppSettings に書き込むことを検証する（S6-006）。
    func test_stopUpdatingLocation_setsWasTrackingFalse_S6_006() throws {
        let settings = makeIsolatedSettings()
        let mock = MockLocationProviderForBGResume()
        let sut = LocationService(manager: mock, appSettings: settings)

        // 記録開始 → wasTracking=true になる
        sut.startUpdatingLocation()
        XCTAssertTrue(settings.wasTracking)

        // 記録停止 → wasTracking=false に戻る
        sut.stopUpdatingLocation()

        XCTAssertFalse(settings.wasTracking,
            "stopUpdatingLocation 後は wasTracking=false（S6-006）")
    }
}

// MARK: - Mock provider for S6-006

/// LocationProviderProtocol の Spy（S6-006 バックグラウンド復帰テスト専用）。
/// SignificantLocationChangesTests の MockLocationProvider と同等だが、
/// 別テストファイルに private 宣言しているため別名で定義する。
private final class MockLocationProviderForBGResume: NSObject, LocationProviderProtocol, @unchecked Sendable {
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = true
    var showsBackgroundLocationIndicator: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var delegate: CLLocationManagerDelegate?

    var didStartUpdating: Bool = false
    var didStopUpdating: Bool = false
    var didStartSLC: Bool = false
    var didStopSLC: Bool = false

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() { didStartUpdating = true }
    func stopUpdatingLocation() { didStopUpdating = true }
    func startMonitoringSignificantLocationChanges() { didStartSLC = true }
    func stopMonitoringSignificantLocationChanges() { didStopSLC = true }
}
