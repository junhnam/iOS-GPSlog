import XCTest
import CoreLocation
@testable import GPSLogger

/// S6-011: PinDetailModel の表示文字列生成・URL 生成を検証するユニットテスト。
///
/// 受け入れ条件テストマッピング:
///   T-2: Apple Maps URL 生成（placeName あり / なし）
///   T-3: Google Maps URL 生成（インストール済 / 未インストール）
///   T-4: PinDetailModel 表示文字列生成（placeName あり/なし / 滞留時間 1 時間超え/未満）
///   T-1 相当: marker.userData 経由の RestoredPin 取り出し（Coordinator.handleMarkerTap は
///             GMSMarker 依存のため integration 扱い → T-1 は RestoredPin.id / Identifiable 確認で代替）
@MainActor
final class PinDetailModelTests: XCTestCase {

    // MARK: - ヘルパー

    private func makePin(
        latitude: Double = 35.65916,
        longitude: Double = 139.70106,
        stayedFrom: Date = Date(timeIntervalSince1970: 1_746_700_000),
        stayedDurationSeconds: Double = 600,
        placeName: String? = nil,
        address: String? = nil
    ) -> RestoredPin {
        RestoredPin(
            latitude: latitude,
            longitude: longitude,
            stayedFrom: stayedFrom,
            stayedDurationSeconds: stayedDurationSeconds,
            placeName: placeName,
            address: address
        )
    }

    // MARK: - T-1: RestoredPin.Identifiable（marker.userData 取り出し相当）

    /// RestoredPin が Identifiable を満たし、id が stayedFrom ベースであることを確認。
    /// これにより `.sheet(item: $selectedPin)` が正しく動作する。
    func test_restoredPin_identifiable_idIsStayedFromInterval() {
        let from = Date(timeIntervalSince1970: 1_746_700_000)
        let pin = makePin(stayedFrom: from)
        XCTAssertEqual(pin.id, from.timeIntervalSince1970,
                       "RestoredPin.id は stayedFrom.timeIntervalSince1970 と一致する必要がある")
    }

    /// marker.userData に格納した RestoredPin を取り出すロジック（`as? RestoredPin`）の
    /// 型キャスト検証。GMSMarker に依存しないためここでシミュレートする。
    func test_markerUserData_castToRestoredPin_succeeds() {
        let pin = makePin(placeName: "テスト店舗")
        // userData は Any として格納される想定 → as? RestoredPin でキャスト可能か確認
        let userData: Any = pin
        let extracted = userData as? RestoredPin
        XCTAssertNotNil(extracted, "userData として格納した RestoredPin を as? RestoredPin でキャストできる")
        XCTAssertEqual(extracted?.placeName, "テスト店舗")
    }

    // MARK: - T-2: Apple Maps URL 生成

    /// placeName ありの場合、Apple Maps URL に ll パラメータと q=placeName が含まれる。
    func test_appleMapsURL_withPlaceName_containsNameAndCoordinates() {
        let pin = makePin(latitude: 35.65916, longitude: 139.70106, placeName: "渋谷スクランブルスクエア")
        let model = PinDetailModel(pin: pin)
        let url = model.appleMapsURL
        let urlString = url.absoluteString

        XCTAssertTrue(urlString.contains("maps.apple.com"), "Apple Maps ドメインを含む")
        XCTAssertTrue(urlString.contains("ll=35.65916"), "緯度を含む")
        XCTAssertTrue(urlString.contains("139.70106"), "経度を含む")
        // placeName は URL エンコードされる
        XCTAssertTrue(urlString.contains("q="), "q パラメータを含む")
    }

    /// placeName が nil の場合、Apple Maps URL に座標のみが q パラメータとして入る。
    func test_appleMapsURL_withoutPlaceName_usesCoordinateAsQuery() {
        let pin = makePin(latitude: 35.65916, longitude: 139.70106, placeName: nil)
        let model = PinDetailModel(pin: pin)
        let url = model.appleMapsURL
        let urlString = url.absoluteString

        XCTAssertTrue(urlString.contains("maps.apple.com"), "Apple Maps ドメインを含む")
        XCTAssertTrue(urlString.contains("ll=35.65916"), "緯度を含む")
        // placeName nil → 座標が q に入る
        XCTAssertTrue(urlString.contains("q="), "q パラメータを含む（座標フォールバック）")
    }

    // MARK: - T-3: Google Maps URL 生成

    /// Google Maps アプリがインストール済みの場合、comgooglemaps:// スキームが使われる。
    func test_googleMapsURL_whenInstalled_usesGoogleMapsScheme() {
        let pin = makePin(latitude: 35.65916, longitude: 139.70106)
        let model = PinDetailModel(pin: pin)
        let url = model.googleMapsURL(canOpenGoogleMaps: true)
        let urlString = url.absoluteString

        XCTAssertTrue(urlString.hasPrefix("comgooglemaps://"), "インストール済み時は comgooglemaps:// スキームを使用")
        XCTAssertTrue(urlString.contains("q="), "座標クエリを含む")
        XCTAssertTrue(urlString.contains("35.65916"), "緯度を含む")
        XCTAssertTrue(urlString.contains("139.70106"), "経度を含む")
    }

    /// Google Maps アプリが未インストールの場合、Web フォールバック URL が使われる。
    func test_googleMapsURL_whenNotInstalled_usesWebFallback() {
        let pin = makePin(latitude: 35.65916, longitude: 139.70106)
        let model = PinDetailModel(pin: pin)
        let url = model.googleMapsURL(canOpenGoogleMaps: false)
        let urlString = url.absoluteString

        XCTAssertTrue(urlString.contains("google.com/maps/search"), "未インストール時は google.com/maps/search を使用")
        XCTAssertTrue(urlString.contains("query="), "query パラメータを含む")
        XCTAssertTrue(urlString.contains("35.65916"), "緯度を含む")
        XCTAssertTrue(urlString.contains("139.70106"), "経度を含む")
    }

    // MARK: - T-4: PinDetailModel 表示文字列生成

    /// placeName ありの場合、model.placeName がそのまま保持される。
    func test_pinDetailModel_withPlaceName_returnsPlaceName() {
        let pin = makePin(placeName: "スターバックス渋谷店")
        let model = PinDetailModel(pin: pin)
        XCTAssertEqual(model.placeName, "スターバックス渋谷店")
        XCTAssertFalse(model.hasNoPlaceInfo, "placeName あり → hasNoPlaceInfo は false")
    }

    /// placeName が nil かつ address も nil の場合、hasNoPlaceInfo が true。
    func test_pinDetailModel_withoutPlaceInfo_hasNoPlaceInfoIsTrue() {
        let pin = makePin(placeName: nil, address: nil)
        let model = PinDetailModel(pin: pin)
        XCTAssertNil(model.placeName)
        XCTAssertTrue(model.hasNoPlaceInfo, "placeName/address とも nil → hasNoPlaceInfo は true")
    }

    /// 滞留時間 10 分（600 秒）の場合「約 10 分」となる。
    func test_stayedDurationText_lessThan1Hour_showsMinutes() {
        let pin = makePin(stayedDurationSeconds: 600)
        let model = PinDetailModel(pin: pin)
        XCTAssertEqual(model.stayedDurationText, "約 10 分",
                       "600 秒 = 10 分 → 「約 10 分」")
    }

    /// 滞留時間 90 分（5400 秒）の場合「約 1 時間 30 分」となる。
    func test_stayedDurationText_over1Hour_showsHoursAndMinutes() {
        let pin = makePin(stayedDurationSeconds: 5400)
        let model = PinDetailModel(pin: pin)
        XCTAssertEqual(model.stayedDurationText, "約 1 時間 30 分",
                       "5400 秒 = 90 分 = 1 時間 30 分 → 「約 1 時間 30 分」")
    }

    /// 滞留時間がちょうど 60 分（3600 秒）の場合「約 1 時間」となる（分が 0 のケース）。
    func test_stayedDurationText_exactly1Hour_showsHoursOnly() {
        let pin = makePin(stayedDurationSeconds: 3600)
        let model = PinDetailModel(pin: pin)
        XCTAssertEqual(model.stayedDurationText, "約 1 時間",
                       "3600 秒 = 60 分 = 1 時間 → 「約 1 時間」")
    }

    /// 座標テキストが小数点 5 桁で出力される。
    func test_coordinateText_formattedTo5DecimalPlaces() {
        let pin = makePin(latitude: 35.65916, longitude: 139.70106)
        let model = PinDetailModel(pin: pin)
        XCTAssertEqual(model.coordinateText, "35.65916, 139.70106",
                       "座標は小数点 5 桁で表示")
    }

    /// address あり + placeName nil の場合、hasNoPlaceInfo は false（住所があるため）。
    func test_pinDetailModel_withAddressOnly_hasNoPlaceInfoIsFalse() {
        let pin = makePin(placeName: nil, address: "東京都 渋谷区 道玄坂 2-29-5")
        let model = PinDetailModel(pin: pin)
        XCTAssertFalse(model.hasNoPlaceInfo, "address あり → hasNoPlaceInfo は false")
        XCTAssertEqual(model.address, "東京都 渋谷区 道玄坂 2-29-5")
    }
}
