import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S3-003 受け入れ条件:
///   (a) 自宅未登録 -> .unknown
///   (b) 半径内 -> .atHome
///   (c) 半径外 -> .away
///   (d) 半径ぴったり -> .atHome
///   (e) 自宅から外へ移動した瞬間に LocationService の lastHomeState が .away になる
@MainActor
final class HomeDetectorTests: XCTestCase {

    /// テスト中に作成した ModelContainer の強参照（ios26-swiftdata.md ノート参照）。
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run {
            retainedContainers.removeAll()
        }
        try await super.tearDown()
    }

    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    /// テスト専用に独立した UserDefaults を返す（AppSettings 用）。
    private func makeIsolatedSettings() -> AppSettings {
        let suiteName = "gpslogger.tests.home.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(defaults: defaults)
    }

    /// 自宅座標（東京駅）と現在位置を作るヘルパー。
    private func tokyoStationHome() -> HomeLocation {
        HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "東京駅")
    }

    private func location(lat: Double, lon: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                   timestamp: Date())
    }

    // MARK: - (a) 自宅未登録

    func test_detect_withNoHomeLocation_returnsUnknown() {
        let state = HomeDetector.detect(homeLocation: nil,
                                        radius: 100,
                                        currentLocation: location(lat: 35.681236, lon: 139.767125))
        XCTAssertEqual(state, .unknown)
    }

    // MARK: - (b) 半径内

    func test_detect_withinRadius_returnsAtHome() {
        let home = tokyoStationHome()
        // 緯度を 0.0001 度ずらす ≒ 約 11m。半径 100m 内なので atHome。
        let cur = location(lat: 35.681336, lon: 139.767125)
        let state = HomeDetector.detect(homeLocation: home, radius: 100, currentLocation: cur)
        XCTAssertEqual(state, .atHome)
    }

    // MARK: - (c) 半径外

    func test_detect_outsideRadius_returnsAway() {
        let home = tokyoStationHome()
        // 緯度を 0.01 度ずらす ≒ 約 1.1km。半径 100m 外。
        let cur = location(lat: 35.691236, lon: 139.767125)
        let state = HomeDetector.detect(homeLocation: home, radius: 100, currentLocation: cur)
        XCTAssertEqual(state, .away)
    }

    // MARK: - (d) 半径ぴったり (distance == radius は atHome に含む)

    func test_detect_exactlyOnRadius_isAtHome() {
        let home = tokyoStationHome()
        // 自宅と同じ点を作り、距離 0 で半径ぴったり境界相当を再現するのは難しいので、
        // 自宅自身の座標を渡し、半径 0 で「distance == 0 == radius」が atHome に入ることを確認。
        let cur = location(lat: home.latitude, lon: home.longitude)
        let state = HomeDetector.detect(homeLocation: home, radius: 0, currentLocation: cur)
        XCTAssertEqual(state, .atHome)
    }

    func test_detect_justBeyondRadius_isAway() {
        let home = tokyoStationHome()
        // 自宅から約 100m 離れる（緯度 0.0009 度 ≒ 100m）。
        let cur = location(lat: home.latitude + 0.0009, lon: home.longitude)
        let state100 = HomeDetector.detect(homeLocation: home, radius: 100, currentLocation: cur)
        // 距離が 100m を僅かに下回るか上回るかは緯度経度の精度次第。
        // ここでは半径を 50 に絞ることで「距離 > radius」を確実に成立させる。
        XCTAssertEqual(state100, .atHome) // 100m 半径ならまだ atHome 寄り
        let stateNarrow = HomeDetector.detect(homeLocation: home, radius: 50, currentLocation: cur)
        XCTAssertEqual(stateNarrow, .away)
    }

    // MARK: - (f) S4-008: HUD バナーメッセージは HomeDetector から取得される

    /// S4-008 受け入れ条件: HUD のメッセージは HomeDetector が一元的に返し、
    /// MapView 側で独自に判定/文言生成しない。
    func test_bannerMessage_atHome_returnsWarning() {
        let home = tokyoStationHome()
        let cur = location(lat: home.latitude, lon: home.longitude)
        let message = HomeDetector.bannerMessage(homeLocation: home,
                                                 radius: 100,
                                                 currentLocation: cur)
        XCTAssertNotNil(message, "atHome 時は HUD 文言が返る")
        XCTAssertTrue(message?.contains("自宅") ?? false,
                      "HUD 文言は自宅滞在を示すメッセージである")
    }

    func test_bannerMessage_away_returnsNil() {
        let home = tokyoStationHome()
        // 約 1.1km 離れた点
        let cur = location(lat: 35.691236, lon: 139.767125)
        let message = HomeDetector.bannerMessage(homeLocation: home,
                                                 radius: 100,
                                                 currentLocation: cur)
        XCTAssertNil(message, "away 時は HUD 文言を出さない")
    }

    func test_bannerMessage_unknown_returnsNil() {
        let cur = location(lat: 35.681236, lon: 139.767125)
        let message = HomeDetector.bannerMessage(homeLocation: nil,
                                                 radius: 100,
                                                 currentLocation: cur)
        XCTAssertNil(message, "自宅未登録（unknown）時は HUD 文言を出さない")
    }

    // MARK: - (e) LocationService と統合: 自宅滞在中はスキップ → 退出で再開

    func test_locationService_skipsRoutePersistence_whileAtHome() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = tokyoStationHome()
        settings.homeRadiusMeters = 100

        let sut = LocationService(repository: repo, appSettings: settings)

        // 自宅 + 数 m 内の点を 2 つ流す → 永続化されない
        let p1 = location(lat: 35.681236, lon: 139.767125)
        let p2 = location(lat: 35.681246, lon: 139.767125) // 約 1m
        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])

        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome)
        XCTAssertEqual(sut.atHomeSkipCount, 2)

        // 自宅から離れた点 (緯度 +0.01 ≒ 約 1.1km) を流す → 永続化される
        let pAway = location(lat: 35.691236, lon: 139.767125)
        sut._ingestForTesting([pAway])

        XCTAssertEqual(sut._lastHomeStateForTesting, .away)
        let trip = try repo.todayTrip(creatingIfMissing: false)
        let unwrapped = try XCTUnwrap(trip)
        XCTAssertEqual(unwrapped.routePoints.count, 1)
    }
}
