import XCTest
import CoreLocation
@testable import GPSLogger

/// S2-006 受け入れ条件に対応する StayDetector のテスト。
@MainActor
final class StayDetectorTests: XCTestCase {

    /// 同じ座標の CLLocation を時刻だけずらして作るヘルパー。
    private func loc(lat: Double = 35.681236,
                     lon: Double = 139.767125,
                     at offset: TimeInterval) -> CLLocation {
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                          altitude: 0,
                          horizontalAccuracy: 5,
                          verticalAccuracy: 5,
                          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset))
    }

    // MARK: - 受け入れ条件のテスト

    func test_samePoint10MinPlus_returnsStaying() {
        let sut = StayDetector()
        // 0 秒, 60秒, …, 600秒 までの 11 点を投入。すべて同じ座標で半径内。
        var lastEvent: StayEvent = .moving
        for i in 0...10 {
            lastEvent = sut.ingest(location: loc(at: TimeInterval(i * 60)))
        }
        // 600 秒経過時点（>= minDuration 600）の点で `.skipped`（滞留中の間引き）が返る。
        XCTAssertEqual(lastEvent, .skipped)
    }

    func test_stayEndedAfter10Min_returnsPin() throws {
        let sut = StayDetector()
        // 滞留: 0〜600 秒、同じ座標を 11 点投入
        for i in 0...10 {
            _ = sut.ingest(location: loc(at: TimeInterval(i * 60)))
        }
        // 700 秒で半径外（緯度を 0.001 度ずらして約 111m 離す）の点を投入。
        let leaveEvent = sut.ingest(location: loc(lat: 35.682236, at: 700))

        guard case .stayEnded(let pin) = leaveEvent else {
            XCTFail("期待値: .stayEnded(pin), 実測: \(leaveEvent)")
            return
        }
        // PinRecord の中心は最初の点（東京駅相当）
        XCTAssertEqual(pin.latitude, 35.681236, accuracy: 0.0001)
        XCTAssertEqual(pin.longitude, 139.767125, accuracy: 0.0001)
        // duration は約 600 秒（最後の半径内点 = 600 秒 - 開始時刻 0 秒）
        XCTAssertEqual(pin.stayedDurationSeconds, 600, accuracy: 1.0)
    }

    func test_stayShorterThan10Min_doesNotReturnPin() {
        let sut = StayDetector()
        // 9 分間（0〜540 秒）の同一点滞留
        for i in 0...9 {
            _ = sut.ingest(location: loc(at: TimeInterval(i * 60)))
        }
        // 600 秒で半径外へ移動（minDuration 未満なのでピン化されない）
        let leaveEvent = sut.ingest(location: loc(lat: 35.682236, at: 600))

        // 滞留時間 540s < 600s なので .moving が返る（ピンなし）
        if case .stayEnded = leaveEvent {
            XCTFail("9 分滞留ではピンが作られないはず")
        }
        XCTAssertEqual(leaveEvent, .moving)
    }

    func test_stayingPointsAreSkippedAfterMinDuration() {
        let sut = StayDetector()
        // 10 分越えの滞留中、複数点が `.skipped` で返ること。
        var skippedCount = 0
        for i in 0...12 {
            let event = sut.ingest(location: loc(at: TimeInterval(i * 60)))
            if event == .skipped {
                skippedCount += 1
            }
        }
        // 10 分を超えてからの点 (i=10, 11, 12) のうち少なくとも 2 点は skipped。
        XCTAssertGreaterThanOrEqual(skippedCount, 2)
    }

    // MARK: - 設定テスト

    func test_customConfig_isApplied() {
        let config = StayDetectionConfig(minDuration: 60, radiusMeters: 10)
        let sut = StayDetector(config: config)
        XCTAssertEqual(sut.config.minDuration, 60)
        XCTAssertEqual(sut.config.radiusMeters, 10)

        // 60 秒で滞留判定 -> 半径外移動でピン化される
        for i in 0...1 {
            _ = sut.ingest(location: loc(at: TimeInterval(i * 60)))
        }
        let leave = sut.ingest(location: loc(lat: 35.682236, at: 70))
        if case .stayEnded(let pin) = leave {
            XCTAssertEqual(pin.stayedDurationSeconds, 60, accuracy: 1.0)
        } else {
            XCTFail("カスタム minDuration=60 で滞留終了を検知できなかった: \(leave)")
        }
    }
}
