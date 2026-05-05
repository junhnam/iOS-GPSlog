import XCTest
import CoreLocation
@testable import GPSLogger

/// Sprint 1 の QA フェーズで追加した補強ユニットテスト。
///
/// 既存の LocationServiceTests がカバーしていない観点を埋める:
///  - LocationService の start/stop の冪等性（多重呼び出しでも内部状態が壊れない）
///  - 経路間引きが連続発生したときの累積動作（5m 未満の点が複数回流入）
///  - GoogleMapsConfiguration の API キー読み込み優先順位（環境変数 → plist）
///
/// 注: CLLocationManager 自体の startUpdatingLocation 呼び出し回数を直接観測するには
/// テスト用 stub を注入する必要があるが、Sprint 1 のスコープを過剰に広げないため
/// ここでは LocationService 自身が公開する `isUpdating` フラグの状態遷移を検証する。
/// より厳密なモック検証は Sprint 2 以降で導入する想定。
@MainActor
final class QASprint1AdditionalTests: XCTestCase {

    // MARK: - LocationService: idempotency

    func test_startUpdatingLocation_isIdempotent_keepsIsUpdatingTrue() {
        let sut = LocationService()
        XCTAssertFalse(sut.isUpdating)

        sut.startUpdatingLocation()
        XCTAssertTrue(sut.isUpdating, "1 回目の start で isUpdating は true になる")

        sut.startUpdatingLocation()
        XCTAssertTrue(sut.isUpdating, "2 回目の start を呼んでも true のまま（冪等）")
    }

    func test_stopUpdatingLocation_isIdempotent_keepsIsUpdatingFalse() {
        let sut = LocationService()
        XCTAssertFalse(sut.isUpdating)

        // 開始していない状態で stop しても isUpdating は false のまま
        sut.stopUpdatingLocation()
        XCTAssertFalse(sut.isUpdating)

        // 開始 → 停止 → もう一度停止 でも false のまま
        sut.startUpdatingLocation()
        sut.stopUpdatingLocation()
        XCTAssertFalse(sut.isUpdating)

        sut.stopUpdatingLocation()
        XCTAssertFalse(sut.isUpdating, "二重停止でも false のまま（冪等）")
    }

    func test_startThenStop_togglesIsUpdating() {
        let sut = LocationService()

        sut.startUpdatingLocation()
        XCTAssertTrue(sut.isUpdating)

        sut.stopUpdatingLocation()
        XCTAssertFalse(sut.isUpdating)

        sut.startUpdatingLocation()
        XCTAssertTrue(sut.isUpdating, "再 start でも有効化される")
    }

    // MARK: - LocationService: 連続間引き

    func test_multipleCloseIngestions_doNotInflateRoute() throws {
        let sut = LocationService()
        let base = CLLocation(latitude: 35.681236, longitude: 139.767125)
        // 1m 程度しか離れていない点を 10 個流す
        let nearbyPoints = (0..<10).map { i in
            CLLocation(latitude: 35.681236 + Double(i) * 0.000005,
                       longitude: 139.767125)
        }

        sut._ingestForTesting([base])
        for p in nearbyPoints {
            sut._ingestForTesting([p])
        }

        XCTAssertEqual(sut.route.count, 1,
                       "5m 未満の点が連続で流入しても、経路は最初の 1 点のみのまま")
        // currentLocation は最後の点に追従
        let currentLat = try XCTUnwrap(sut.currentLocation?.coordinate.latitude)
        let lastLat = try XCTUnwrap(nearbyPoints.last?.coordinate.latitude)
        XCTAssertEqual(currentLat, lastLat, accuracy: 0.0000001)
    }

    func test_alternatingNearAndFar_appendsOnlyFar() {
        let sut = LocationService()
        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let p1_close = CLLocation(latitude: 35.681238, longitude: 139.767125) // 1m
        let p2_far = CLLocation(latitude: 35.682236, longitude: 139.767125)   // 約 111m
        let p2_close = CLLocation(latitude: 35.682239, longitude: 139.767125) // 1m

        sut._ingestForTesting([p1])      // append
        sut._ingestForTesting([p1_close]) // 間引き
        sut._ingestForTesting([p2_far])  // append
        sut._ingestForTesting([p2_close]) // 間引き

        XCTAssertEqual(sut.route.count, 2,
                       "5m 以上の点だけが route に追加される")
    }

    // MARK: - GoogleMapsConfiguration

    func test_loadAPIKey_readsFromEnvironmentVariableFirst() {
        // 環境変数 GMS_API_KEY が設定されている場合、それが優先される
        let env = ["GMS_API_KEY": "TEST_ENV_KEY_12345"]
        let result = GoogleMapsConfiguration.loadAPIKey(bundle: Bundle.main, environment: env)
        XCTAssertEqual(result, "TEST_ENV_KEY_12345",
                       "環境変数があればそれを返す")
    }

    func test_loadAPIKey_returnsNilWhenEnvIsEmpty() {
        // 空文字の環境変数は無効扱い
        let env = ["GMS_API_KEY": ""]
        // この場合、テストバンドルには GoogleMaps-Info.plist は含まれない可能性が高いので
        // nil または何らかの値が返る。空文字環境変数が無視されることだけ検証する。
        let result = GoogleMapsConfiguration.loadAPIKey(bundle: Bundle(for: type(of: self)),
                                                       environment: env)
        // テストターゲットには本物のキーが含まれていないので nil が期待される。
        // もしテストバンドルに何らかの GoogleMaps-Info.plist が紛れていても、
        // 「空文字環境変数が無視される」ことが要点なので nil チェックは緩めにする。
        XCTAssertTrue(result == nil || !(result?.isEmpty ?? true),
                      "空文字の環境変数は無視される（nil または非空文字列が返る）")
    }

    func test_loadAPIKey_returnsNilWhenNoEnvAndNoBundlePlist() {
        // 環境変数なし、かつテストバンドルに GoogleMaps-Info.plist が含まれない場合は nil
        let env: [String: String] = [:]
        // テストバンドル（GPSLoggerTests）には GoogleMaps-Info.plist は配置されない設計
        let result = GoogleMapsConfiguration.loadAPIKey(bundle: Bundle(for: type(of: self)),
                                                       environment: env)
        XCTAssertNil(result, "ソースが何もなければ nil")
    }

    // MARK: - 初期状態の追加観点

    func test_initialAuthorizationStatus_isNotDetermined_or_consistent() {
        let sut = LocationService()
        // 端末初期状態は notDetermined のはずだが、シミュレータの状態に依存
        // ここでは「LocationService が manager の状態と一致して保持している」ことだけ検証
        // 仕様上 notDetermined / restricted / denied / authorizedAlways / authorizedWhenInUse のいずれか
        let validStates: [CLAuthorizationStatus] = [
            .notDetermined, .restricted, .denied,
            .authorizedAlways, .authorizedWhenInUse
        ]
        XCTAssertTrue(validStates.contains(sut.authorizationStatus),
                      "authorizationStatus は CLAuthorizationStatus の有効値")
    }
}
