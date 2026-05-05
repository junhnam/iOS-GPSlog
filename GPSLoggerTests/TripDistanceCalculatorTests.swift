import XCTest
import CoreLocation
@testable import GPSLogger

/// S2-004 の受け入れ条件に対応する純粋ロジックテスト。
final class TripDistanceCalculatorTests: XCTestCase {

    // MARK: - distance(from:to:)

    func test_distance_samePoint_returnsZero() {
        let p = CLLocation(latitude: 35.6812, longitude: 139.7671)
        XCTAssertEqual(TripDistanceCalculator.distance(from: p, to: p),
                       0,
                       accuracy: 0.5)
    }

    func test_distance_tokyoToShinjuku_isAround6300m() {
        // 東京駅 (35.681236, 139.767125) と 新宿駅 (35.690921, 139.700258)
        let tokyo = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let shinjuku = CLLocation(latitude: 35.690921, longitude: 139.700258)

        let meters = TripDistanceCalculator.distance(from: tokyo, to: shinjuku)
        // 期待値 6300m ± 100m
        XCTAssertEqual(meters, 6300, accuracy: 100)
    }

    // MARK: - totalDistance(of:)

    func test_totalDistance_emptyOrSingle_returnsZero() {
        XCTAssertEqual(TripDistanceCalculator.totalDistance(of: []), 0)
        let p = CLLocation(latitude: 35.6812, longitude: 139.7671)
        XCTAssertEqual(TripDistanceCalculator.totalDistance(of: [p]), 0)
    }

    func test_totalDistance_threePoints_equalsSumOfSegments() {
        // 緯度方向に約 0.001 度ずつ動く（≒ 約 111m × 2）
        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let p2 = CLLocation(latitude: 35.682236, longitude: 139.767125)
        let p3 = CLLocation(latitude: 35.683236, longitude: 139.767125)

        let seg1 = TripDistanceCalculator.distance(from: p1, to: p2)
        let seg2 = TripDistanceCalculator.distance(from: p2, to: p3)
        let total = TripDistanceCalculator.totalDistance(of: [p1, p2, p3])

        XCTAssertEqual(total, seg1 + seg2, accuracy: 0.001)
    }

    func test_totalDistance_skipsSubMeterSegments() {
        // 距離 0 の重複点を挟む
        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let pDup = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let p2 = CLLocation(latitude: 35.682236, longitude: 139.767125)

        let direct = TripDistanceCalculator.distance(from: p1, to: p2)
        let withDup = TripDistanceCalculator.totalDistance(of: [p1, pDup, p2])
        // 重複点はスキップされ、p1→p2 と等しくなる
        XCTAssertEqual(withDup, direct, accuracy: 0.5)
    }

    // MARK: - kilometers(_:)

    func test_kilometers_roundingHalfUp() {
        // 12345.6 m → 12.3456 km → 四捨五入で 12.35
        XCTAssertEqual(TripDistanceCalculator.kilometers(12345.6), 12.35, accuracy: 0.0001)
        // 12344.0 m → 12.344 km → 12.34
        XCTAssertEqual(TripDistanceCalculator.kilometers(12344.0), 12.34, accuracy: 0.0001)
        // 0 m → 0
        XCTAssertEqual(TripDistanceCalculator.kilometers(0), 0)
    }

    func test_formatKilometers_returnsTwoDecimals() {
        XCTAssertEqual(TripDistanceCalculator.formatKilometers(12345.6), "12.35 km")
        XCTAssertEqual(TripDistanceCalculator.formatKilometers(0), "0.00 km")
    }
}
