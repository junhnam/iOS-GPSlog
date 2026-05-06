import XCTest
import CoreLocation
@testable import GPSLogger

/// S6-005 受け入れ条件:
///   - 走行中（5 分以内に 100m 超移動）: .driving(Best / 10m)
///   - 停車中（5 分以内に 100m 以下）: .stopped(HundredMeters / 100m)
///   - 自宅滞在中: .stopRecording
///   - 状態遷移（走行 → 停車 / 停車 → 走行）
///
/// BatteryAdaptiveLocationPolicy はステートレス Sendable 構造体のため、
/// テストは同期的に実行でき @MainActor 不要。
final class BatteryAdaptiveLocationPolicyTests: XCTestCase {

    private let sut = BatteryAdaptiveLocationPolicy()

    // MARK: - ヘルパー

    /// 指定の緯度経度・タイムスタンプで CLLocation を生成する。
    private func location(lat: Double, lon: Double, at timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    /// 基準日時。テストの再現性確保のために固定値を使う。
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - 走行判定

    /// test_drivingState_returnsBestAccuracyAnd10mFilter_S6_005
    ///
    /// 直近 5 分以内に 100m を超える移動があれば .driving を返すことを検証する。
    /// 緯度 0.001 度 ≒ 111m（赤道付近）の移動を使って走行状態を作る。
    func test_drivingState_returnsBestAccuracyAnd10mFilter_S6_005() {
        let t0 = base
        let t1 = base.addingTimeInterval(60)  // 1 分後
        let locations: [CLLocation] = [
            location(lat: 35.681236, lon: 139.767125, at: t0),
            location(lat: 35.682236, lon: 139.767125, at: t1)  // 約 111m 移動
        ]
        let now = t1

        let result = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: now
        )

        switch result {
        case .driving(let accuracy, let filter):
            XCTAssertEqual(accuracy, kCLLocationAccuracyBest,
                "走行中は desiredAccuracy = kCLLocationAccuracyBest")
            XCTAssertEqual(filter, 10,
                "走行中は distanceFilter = 10m")
        default:
            XCTFail("走行状態（5 分以内に 100m 超移動）では .driving が返るべき。実際: \(result)")
        }
    }

    // MARK: - 停車判定

    /// test_stoppedState_returnsHundredMetersAccuracyAnd100mFilter_S6_005
    ///
    /// 直近 5 分以内に 100m 以下の移動しかない場合 .stopped を返すことを検証する。
    func test_stoppedState_returnsHundredMetersAccuracyAnd100mFilter_S6_005() {
        let t0 = base
        let t1 = base.addingTimeInterval(60)   // 1 分後
        let t2 = base.addingTimeInterval(120)  // 2 分後
        // 同じ緯度経度に留まる（距離 0）
        let locations: [CLLocation] = [
            location(lat: 35.681236, lon: 139.767125, at: t0),
            location(lat: 35.681236, lon: 139.767125, at: t1),
            location(lat: 35.681236, lon: 139.767125, at: t2)
        ]
        let now = t2

        let result = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: now
        )

        switch result {
        case .stopped(let accuracy, let filter):
            XCTAssertEqual(accuracy, kCLLocationAccuracyHundredMeters,
                "停車中は desiredAccuracy = kCLLocationAccuracyHundredMeters")
            XCTAssertEqual(filter, 100,
                "停車中は distanceFilter = 100m")
        default:
            XCTFail("停車状態（5 分以内に 100m 以下）では .stopped が返るべき。実際: \(result)")
        }
    }

    // MARK: - 自宅判定

    /// test_atHome_returnsStopRecording_S6_005
    ///
    /// 最新位置が自宅半径内にある場合 .stopRecording を返すことを検証する。
    func test_atHome_returnsStopRecording_S6_005() {
        let homeLatitude = 35.681236
        let homeLongitude = 139.767125
        let home = HomeLocation(latitude: homeLatitude, longitude: homeLongitude, address: "Home")

        // 自宅座標そのものを最新点として渡す
        let t0 = base
        let locations: [CLLocation] = [
            location(lat: homeLatitude, lon: homeLongitude, at: t0)
        ]
        let now = t0

        let result = sut.evaluate(
            recentLocations: locations,
            homeLocation: home,
            homeRadiusMeters: 100,
            now: now
        )

        XCTAssertEqual(result, .stopRecording,
            "最新位置が自宅半径内にある場合は .stopRecording が返るべき")
    }

    // MARK: - 状態遷移（走行 → 停車）

    /// test_transition_drivingToStopped_S6_005
    ///
    /// 走行状態から停車状態へ遷移した場合、古い走行履歴が 5 分ウィンドウ外に出ると
    /// .stopped に切り替わることを検証する。
    func test_transition_drivingToStopped_S6_005() {
        // Step 1: 走行状態（5 分以内に 100m 超移動）
        let t0 = base
        let t1 = base.addingTimeInterval(60)  // 1 分後に 111m 移動
        var locations: [CLLocation] = [
            location(lat: 35.681236, lon: 139.767125, at: t0),
            location(lat: 35.682236, lon: 139.767125, at: t1)
        ]
        let drivingResult = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: t1
        )
        switch drivingResult {
        case .driving:
            break  // 期待通り
        default:
            XCTFail("走行状態のはずが: \(drivingResult)")
        }

        // Step 2: 5 分以上経過後、同じ場所で新たな点を追加
        // 既存の 2 点は 5 分ウィンドウ外に出るため停車判定になる
        let t6 = base.addingTimeInterval(6 * 60)  // 6 分後（5 分ウィンドウ外）
        let t7 = base.addingTimeInterval(7 * 60)  // 7 分後
        locations = [
            // t0/t1 の点は 7 分後ウィンドウ外
            location(lat: 35.681236, lon: 139.767125, at: t0),
            location(lat: 35.682236, lon: 139.767125, at: t1),
            // 6/7 分後に同じ場所（距離 0）
            location(lat: 35.682236, lon: 139.767125, at: t6),
            location(lat: 35.682236, lon: 139.767125, at: t7)
        ]

        let stoppedResult = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: t7
        )
        switch stoppedResult {
        case .stopped:
            break  // 期待通り
        default:
            XCTFail("走行 → 停車遷移後は .stopped が返るべき。実際: \(stoppedResult)")
        }
    }

    // MARK: - 状態遷移（停車 → 走行）

    /// test_transition_stoppedToDriving_S6_005
    ///
    /// 停車状態から走行状態へ遷移した場合、5 分ウィンドウ内に 100m 超移動が生まれると
    /// .driving に切り替わることを検証する。
    func test_transition_stoppedToDriving_S6_005() {
        // Step 1: 停車状態（同じ場所に留まる）
        let t0 = base
        let t1 = base.addingTimeInterval(60)
        let t2 = base.addingTimeInterval(120)
        var locations: [CLLocation] = [
            location(lat: 35.681236, lon: 139.767125, at: t0),
            location(lat: 35.681236, lon: 139.767125, at: t1),
            location(lat: 35.681236, lon: 139.767125, at: t2)
        ]
        let stoppedResult = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: t2
        )
        switch stoppedResult {
        case .stopped:
            break  // 期待通り
        default:
            XCTFail("停車状態のはずが: \(stoppedResult)")
        }

        // Step 2: 5 分以内に 100m 超移動する点を追加 → 走行判定に切り替わる
        let t3 = base.addingTimeInterval(180)  // 3 分後（ウィンドウ内）に 111m 移動
        locations.append(location(lat: 35.682236, lon: 139.767125, at: t3))

        let drivingResult = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: t3
        )
        switch drivingResult {
        case .driving:
            break  // 期待通り
        default:
            XCTFail("停車 → 走行遷移後は .driving が返るべき。実際: \(drivingResult)")
        }
    }

    // MARK: - 追加: 点数不足時のフォールバック

    /// 位置履歴が 1 件以下の場合は省電力優先で .stopped を返すことを検証する。
    func test_insufficientLocations_returnsStopped_S6_005() {
        let locations: [CLLocation] = [
            location(lat: 35.681236, lon: 139.767125, at: base)
        ]
        let result = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: base
        )
        switch result {
        case .stopped:
            break  // 期待通り（省電力優先フォールバック）
        default:
            XCTFail("点数不足時は .stopped が返るべき。実際: \(result)")
        }
    }

    // MARK: - 追加: 5 分ウィンドウ境界のテスト

    /// 移動が 5 分ウィンドウのちょうど外（5 分 1 秒前）にある場合は .stopped を返すことを検証する。
    func test_movementOutsideWindow_returnsStopped_S6_005() {
        let tOld = base.addingTimeInterval(-(5 * 60 + 1))  // 5 分 1 秒前
        let tNow = base

        let locations: [CLLocation] = [
            location(lat: 35.681236, lon: 139.767125, at: tOld),  // ウィンドウ外
            location(lat: 35.682236, lon: 139.767125, at: tNow)   // ウィンドウ内のみ（1 点）
        ]

        let result = sut.evaluate(
            recentLocations: locations,
            homeLocation: nil,
            homeRadiusMeters: 100,
            now: tNow
        )
        // ウィンドウ内の点が 1 件（最新のみ）のため比較対象がなく .stopped にフォールバック
        switch result {
        case .stopped:
            break
        default:
            XCTFail("5 分ウィンドウ外の移動では .stopped が返るべき。実際: \(result)")
        }
    }
}
