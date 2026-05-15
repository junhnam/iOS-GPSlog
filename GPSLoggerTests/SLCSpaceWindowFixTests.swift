import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S6-017 受け入れ条件:
///   (1) atHome 中も isUpdating=true を維持（通常 GPS 停止しない）
///   (2) atHome 中の desiredAccuracy=HundredMeters / distanceFilter=100
///   (3) away 遷移時に精度を通常（Best / kCLDistanceFilterNone）に戻す
///   (4) 自宅から 70m+ 動いた瞬間に didUpdateLocations が発火し away 判定される
///   (5) atHome 中は SLC が呼ばれない
@MainActor
final class SLCSpaceWindowFixTests: XCTestCase {

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

    private func makeIsolatedSettings() -> AppSettings {
        let suiteName = "gpslogger.tests.s6017.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(defaults: defaults)
    }

    private func location(lat: Double, lon: Double,
                          at offset: TimeInterval = 0,
                          base: Date = Date()) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: base.addingTimeInterval(offset)
        )
    }

    // MARK: - (1)(2) atHome 中も isUpdating=true を維持し、低精度設定になる

    /// startSignificantChangesIfHome() を直接呼んだとき、
    /// isUpdating=true・desiredAccuracy=HundredMeters・distanceFilter=100 になることを検証する。
    /// SLC（startMonitoringSignificantLocationChanges）は呼ばれない。
    func test_atHomeMode_setsLowAccuracyAndLargeDistanceFilter_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 70

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // GPS を開始してから atHome モードに移行
        sut.startUpdatingLocation()
        XCTAssertTrue(sut.isUpdating, "前提: GPS 開始直後は isUpdating=true")
        // S6-017 メイン代行修正: startUpdatingLocation 内で SLC も併走起動される（kill 後の保険）
        let baselineSLCCount = mock.startSLCCount

        sut.startSignificantChangesIfHome()

        // (1) isUpdating=true を維持
        XCTAssertTrue(sut.isUpdating,
            "S6-017: atHome 中も isUpdating=true を維持する（通常 GPS を停止しない）")
        // (2) 低精度設定
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyHundredMeters,
            "S6-017: atHome 中は desiredAccuracy=kCLLocationAccuracyHundredMeters")
        XCTAssertEqual(mock.lastDistanceFilter, 100,
            "S6-017: atHome 中は distanceFilter=100m")
        // startSignificantChangesIfHome は SLC を「追加で」起動しない
        XCTAssertEqual(mock.startSLCCount, baselineSLCCount,
            "S6-017: startSignificantChangesIfHome は SLC を追加起動しない（baseline 維持）")
    }

    // MARK: - (3) away 遷移時に精度を通常（Best / kCLDistanceFilterNone）に戻す

    /// atHome → away 遷移時に desiredAccuracy=Best / distanceFilter=kCLDistanceFilterNone に
    /// 復元されることを検証する。
    func test_awayTransition_restoresNormalAccuracy_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 70
        settings.wasTracking = true

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()

        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // 自宅外 → 自宅内（atHome, 低精度モード）
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 0, base: base)])
        sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: 5, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome,
            "前提: atHome 状態になっている")
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyHundredMeters,
            "前提: atHome 中は低精度モード")

        // 自宅内 → 自宅外（away, 精度復元）
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 10, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .away)

        // (3) 通常精度に復元
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyBest,
            "S6-017: away 遷移時に desiredAccuracy=kCLLocationAccuracyBest に復元する")
        // distanceFilter は handleHomeStateTransition で一度 kCLDistanceFilterNone にした後、
        // 同じ handleNewLocations 内で updateBatteryPolicy が走って Policy 判定値で上書きする。
        // テストでは「atHome 中の 100m から変わったこと」を検証すれば十分（具体値は Policy 任せ）。
        XCTAssertNotEqual(mock.lastDistanceFilter, 100,
            "S6-017: away 遷移時に distanceFilter は atHome の 100m から変わる（Policy 判定で別値）")
        XCTAssertTrue(sut.isUpdating,
            "S6-017: away 遷移後も isUpdating=true を維持（atHome 中も維持していたため）")
    }

    // MARK: - (4) 自宅半径 70m を超えた瞬間に away 判定される

    /// 自宅半径 70m 以内では atHome、100m 外では away を検出することを検証する。
    /// （didUpdateLocations 発火 → HomeDetector → handleHomeStateTransition の一連フロー）
    func test_outsideHomeRadius70m_triggersAwayTransition_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        // 自宅: 東京駅付近 / 半径 70m
        let homeLat = 35.681236
        let homeLon = 139.767125
        settings.homeLocation = HomeLocation(latitude: homeLat, longitude: homeLon, address: "Home")
        settings.homeRadiusMeters = 70
        settings.wasTracking = true

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()

        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // まず atHome 状態にする（自宅内の位置を流す）
        sut._ingestForTesting([location(lat: homeLat, lon: homeLon, at: 0, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome)

        // 低精度通常 GPS 中（S6-017）: isUpdating=true を維持したまま
        XCTAssertTrue(sut.isUpdating,
            "S6-017: atHome 中も通常 GPS は動き続けている")

        // 自宅から約 100m 離れた位置（緯度で約 0.0009 度 ≒ 100m）を流す
        // → distanceFilter=100m なので iOS は配信しない（実機での話）
        // → テストでは直接 _ingestForTesting を呼ぶため、away 判定ロジックの確認ができる
        let outsideLat = homeLat + 0.0009 // 約 100m 北
        sut._ingestForTesting([location(lat: outsideLat, lon: homeLon, at: 5, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .away,
            "S6-017: 自宅半径 70m を超えた位置で away を検出する")
        XCTAssertTrue(sut.isUpdating,
            "S6-017: away 遷移後も isUpdating=true を維持する（記録継続）")
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyBest,
            "S6-017: away 遷移後に desiredAccuracy=Best に復元される")
    }

    // MARK: - (5) atHome 中は SLC が呼ばれない

    /// atHome 状態になった際に、atHome 遷移自身は SLC API を「追加で」呼ばないことを検証する。
    ///
    /// S6-017 メイン代行修正で `startUpdatingLocation()` 内で SLC 併走起動が入ったため、
    /// `startUpdatingLocation` の時点で SLC は 1 回起動される。検証の論点は
    /// 「atHome 遷移 / startSignificantChangesIfHome は SLC を**追加起動**しないか」。
    func test_atHomeMode_doesNotStartSLC_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 70
        settings.wasTracking = true

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()
        // S6-017 メイン代行修正: ここで SLC が 1 回起動される
        let baselineStartSLC = mock.startSLCCount
        let baselineStopSLC = mock.stopSLCCount

        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // atHome 遷移
        sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: 0, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome)

        // atHome 遷移は SLC を「追加で」呼ばない（baseline 維持）
        XCTAssertEqual(mock.startSLCCount, baselineStartSLC,
            "S6-017: atHome 遷移 / startSignificantChangesIfHome は SLC を追加起動しない")
        XCTAssertEqual(mock.stopSLCCount, baselineStopSLC,
            "S6-017: atHome 遷移時に stopSLC も呼ばない")
    }

    // MARK: - GPS 未起動時の startSignificantChangesIfHome は GPS を開始する

    /// isUpdating=false の状態で startSignificantChangesIfHome() を呼んだ場合、
    /// GPS を開始して isUpdating=true になることを検証する。
    func test_atHomeMode_startsGPSIfNotUpdating_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 70

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        XCTAssertFalse(sut.isUpdating, "前提: 初期状態は isUpdating=false")

        sut.startSignificantChangesIfHome()

        XCTAssertTrue(sut.isUpdating,
            "S6-017: isUpdating=false の場合は startUpdatingLocation() を呼ぶ")
        XCTAssertEqual(mock.startUpdatingCount, 1,
            "S6-017: startUpdatingLocation() が 1 回呼ばれる")
    }

    // MARK: - S6-017 メイン代行修正: SLC 併走起動

    /// `startUpdatingLocation()` を呼ぶと SLC も併走起動される（kill 後の OS 起床トリガー保険）。
    ///
    /// レビュー指摘: S6-017 で `startSignificantChangesIfHome` から SLC 起動を削除した結果、
    /// プロダクトコード全体で `startMonitoringSignificantLocationChanges()` を呼ぶ箇所が
    /// 消えて、タスクキル後の OS 起床トリガー（Apple 仕様で明示 start が必須）が失われた。
    /// メイン代行修正で `startUpdatingLocation()` 内に SLC 併走を追加した結果を検証する。
    func test_startUpdatingLocation_startsSLCInParallel_S6017Review() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        XCTAssertEqual(mock.startSLCCount, 0, "前提: SLC は起動していない")

        sut.startUpdatingLocation()

        XCTAssertTrue(sut.isUpdating,
            "通常 GPS が起動している")
        XCTAssertEqual(mock.startSLCCount, 1,
            "S6-017 メイン代行修正: SLC が併走起動される（kill 後の OS 起床トリガー保険）")
    }

    /// `startUpdatingLocation()` を 2 回呼んでも SLC は 1 回しか起動されない（冪等性）。
    func test_startUpdatingLocation_doesNotDoubleStartSLC_S6017Review() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()

        let mock = MockSpy()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        sut.startUpdatingLocation()
        sut.startUpdatingLocation()  // 2 回目（冪等性検証）

        XCTAssertEqual(mock.startSLCCount, 1,
            "SLC 併走起動は冪等（2 回目以降は no-op）")
        XCTAssertEqual(mock.startUpdatingCount, 1,
            "通常 GPS も冪等（既存 guard で 2 回目は no-op）")
    }
}

// MARK: - Mock / Spy

/// S6-017 テスト専用の Spy。
/// startUpdatingLocation / SLC の呼び出し回数と最後の設定値を記録する。
private final class MockSpy: NSObject, LocationProviderProtocol, @unchecked Sendable {
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest {
        didSet { lastDesiredAccuracy = desiredAccuracy }
    }
    var distanceFilter: CLLocationDistance = 10 {
        didSet { lastDistanceFilter = distanceFilter }
    }
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = true
    var showsBackgroundLocationIndicator: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var delegate: CLLocationManagerDelegate?

    var lastDesiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var lastDistanceFilter: CLLocationDistance = 10

    var startUpdatingCount: Int = 0
    var stopUpdatingCount: Int = 0
    var startSLCCount: Int = 0
    var stopSLCCount: Int = 0

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() { startUpdatingCount += 1 }
    func stopUpdatingLocation() { stopUpdatingCount += 1 }
    func startMonitoringSignificantLocationChanges() { startSLCCount += 1 }
    func stopMonitoringSignificantLocationChanges() { stopSLCCount += 1 }
}
