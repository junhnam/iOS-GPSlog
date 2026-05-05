import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// LocationService のロジック検証用テスト。
/// CLLocationManager 自体は OS のシミュレートに任せ、ここでは
/// `_ingestForTesting` で擬似座標を流し、route / currentLocation の挙動だけを確認する。
@MainActor
final class LocationServiceTests: XCTestCase {

    /// テスト中に作成した ModelContainer の強参照。
    /// SwiftData の ModelContext は ModelContainer が ARC で解放されると無効化され、
    /// fetch 時に内部 precondition で SIGTRAP するため、テストインスタンスのライフタイム中は
    /// container を必ず保持しておく必要がある。
    private var retainedContainers: [ModelContainer] = []

    override func tearDownWithError() throws {
        retainedContainers.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Sprint 1 互換テスト（route / currentLocation）

    func test_initialState_isEmpty() {
        let sut = LocationService()
        XCTAssertNil(sut.currentLocation)
        XCTAssertTrue(sut.route.isEmpty)
        XCTAssertFalse(sut.isUpdating)
    }

    func test_ingestSinglePoint_setsCurrentAndAppendsRoute() throws {
        let sut = LocationService()
        let point = CLLocation(latitude: 35.6812, longitude: 139.7671)

        sut._ingestForTesting([point])

        let lat = try XCTUnwrap(sut.currentLocation?.coordinate.latitude)
        XCTAssertEqual(lat, 35.6812, accuracy: 0.0001)
        XCTAssertEqual(sut.route.count, 1)
    }

    func test_ingestPointsCloserThan5Meters_areThinnedOut() throws {
        let sut = LocationService()
        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        // 緯度方向に約 1m の差。 `distance(from:) < 5` のため経路に追加されない想定。
        let p2 = CLLocation(latitude: 35.681245, longitude: 139.767125)

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])

        // currentLocation は最新点に追従する。
        let lat = try XCTUnwrap(sut.currentLocation?.coordinate.latitude)
        XCTAssertEqual(lat, p2.coordinate.latitude, accuracy: 0.000001)
        // 経路は 1 点のまま（間引かれた）。
        XCTAssertEqual(sut.route.count, 1)
    }

    func test_ingestPointsFartherThan5Meters_areAppended() {
        let sut = LocationService()
        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        // 緯度方向に約 0.001 度 ≒ 約 111m。十分 5m 以上。
        let p2 = CLLocation(latitude: 35.682236, longitude: 139.767125)

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])

        XCTAssertEqual(sut.route.count, 2)
    }

    // MARK: - Sprint 2 / S2-005: DB 永続化テスト

    /// インメモリ TripRepository を作るヘルパー。
    /// container はテストインスタンスのプロパティ `retainedContainers` に強参照として
    /// 保存し、ARC によって context が無効化されないようにする。
    /// 呼び出し側で `_ = container` のように受けると ARC のタイミング次第で
    /// SwiftData が precondition で SIGTRAP するため、container は返さない設計にした。
    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    func test_ingest_persistsRoutePointsToRepository() throws {
        let repo = try makeInMemoryRepository()
        let sut = LocationService(repository: repo)

        // 緯度を 0.001 度ずつ増やす。各区間 ≒ 111m。
        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let p2 = CLLocation(latitude: 35.682236, longitude: 139.767125)
        let p3 = CLLocation(latitude: 35.683236, longitude: 139.767125)

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])
        sut._ingestForTesting([p3])

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let unwrapped = try XCTUnwrap(trip)
        XCTAssertEqual(unwrapped.routePoints.count, 3)

        // 距離は p1→p2 + p2→p3 の合計。p1 自体は初回点なので加算されない。
        let expected = p1.distance(from: p2) + p2.distance(from: p3)
        XCTAssertEqual(unwrapped.totalDistanceMeters, expected, accuracy: 0.5)
    }

    func test_ingest_skipsDBWriteForSubFiveMeterMovements() throws {
        let repo = try makeInMemoryRepository()
        let sut = LocationService(repository: repo)

        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        // 緯度方向に 0.00001 度 ≒ 約 1m。5m 未満なので DB 書き込み対象外。
        let p2 = CLLocation(latitude: 35.681246, longitude: 139.767125)

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let unwrapped = try XCTUnwrap(trip)
        // 初回点 p1 のみ記録され、p2 はスキップされる。
        XCTAssertEqual(unwrapped.routePoints.count, 1)
        XCTAssertEqual(unwrapped.totalDistanceMeters, 0, accuracy: 0.001)
    }

    func test_ingest_withoutRepository_doesNotCrash() {
        // repository 未注入時はメモリのみで従来通り動作（後方互換）。
        let sut = LocationService(repository: nil)
        let p = CLLocation(latitude: 35.681236, longitude: 139.767125)
        sut._ingestForTesting([p])
        XCTAssertEqual(sut.route.count, 1)
    }
}
