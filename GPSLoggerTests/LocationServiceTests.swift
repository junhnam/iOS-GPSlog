import XCTest
import CoreLocation
@testable import GPSLogger

/// LocationService のロジック検証用テスト。
/// CLLocationManager 自体は OS のシミュレートに任せ、ここでは
/// `_ingestForTesting` で擬似座標を流し、route / currentLocation の挙動だけを確認する。
@MainActor
final class LocationServiceTests: XCTestCase {

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
}
