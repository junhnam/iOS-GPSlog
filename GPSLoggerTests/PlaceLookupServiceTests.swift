import XCTest
import CoreLocation
import MapKit
import SwiftData
@testable import GPSLogger

/// S3-007 受け入れ条件: PlaceLookupService が
///   (a) MKLocalSearch ヒット時は名前と URL を返す
///   (b) 0 件時は逆ジオコーディングで住所のみ返す
///   (c) ネットワーク失敗時は nil 返却
///   (d) PinRecord に書き込まれる（LocationService 経由）
/// を検証する。
@MainActor
final class PlaceLookupServiceTests: XCTestCase {

    /// テスト中に作成した ModelContainer の強参照。
    /// ios26-swiftdata.md ノートに従い retainedContainers を保持する。
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

    // MARK: - (a) 検索成功

    func test_lookup_withSuccessfulPOIHit_returnsNameAndURL() async {
        let url = URL(string: "https://maps.apple.com/?q=Starbucks")!
        let stubSearcher = StubLocalSearcher(result: .success([
            PlaceCandidate(name: "スターバックス渋谷店", url: url, address: nil)
        ]))
        let stubGeo = StubGeocoder(result: .success(nil))
        let sut = PlaceLookupService(poiSearcher: stubSearcher, geocoder: stubGeo)

        let coord = CLLocationCoordinate2D(latitude: 35.658, longitude: 139.701)
        let candidate = await sut.lookup(coordinate: coord)

        XCTAssertEqual(candidate?.name, "スターバックス渋谷店")
        XCTAssertEqual(candidate?.url, url)
        XCTAssertNil(candidate?.address)
    }

    // MARK: - (b) 0 件 -> 住所 fallback

    func test_lookup_withZeroPOIHits_fallbacksToAddress() async {
        let stubSearcher = StubLocalSearcher(result: .success([]))
        let stubGeo = StubGeocoder(result: .success("東京都 渋谷区 道玄坂 2-29-5"))
        let sut = PlaceLookupService(poiSearcher: stubSearcher, geocoder: stubGeo)

        let coord = CLLocationCoordinate2D(latitude: 35.658, longitude: 139.701)
        let candidate = await sut.lookup(coordinate: coord)

        XCTAssertNil(candidate?.name)
        XCTAssertNil(candidate?.url)
        XCTAssertEqual(candidate?.address, "東京都 渋谷区 道玄坂 2-29-5")
    }

    // MARK: - PlacemarkAddressFormatter

    func test_addressFormatter_joinsAvailableComponents() {
        let formatted = PlacemarkAddressFormatter.format(
            administrativeArea: "東京都",
            locality: "渋谷区",
            thoroughfare: "道玄坂",
            subThoroughfare: "2-29-5"
        )
        XCTAssertEqual(formatted, "東京都 渋谷区 道玄坂 2-29-5")
    }

    func test_addressFormatter_returnsNilWhenAllNil() {
        let formatted = PlacemarkAddressFormatter.format(
            administrativeArea: nil,
            locality: nil,
            thoroughfare: nil,
            subThoroughfare: nil
        )
        XCTAssertNil(formatted)
    }

    // MARK: - (c) ネットワーク失敗

    func test_lookup_withNetworkFailureOnBoth_returnsNil() async {
        let stubSearcher = StubLocalSearcher(result: .failure(StubError.network))
        let stubGeo = StubGeocoder(result: .failure(StubError.network))
        let sut = PlaceLookupService(poiSearcher: stubSearcher, geocoder: stubGeo)

        let coord = CLLocationCoordinate2D(latitude: 35.658, longitude: 139.701)
        let candidate = await sut.lookup(coordinate: coord)

        XCTAssertNil(candidate)
    }

    // MARK: - S4-001: MKReverseGeocodingRequest 移行のレイヤ別テスト

    /// (a) 住所取得成功で住所文字列が返る（GeocoderPerforming の契約検証）。
    func test_geocoder_returnsAddressString_whenSucceeds_S4_001() async throws {
        let stubGeo = StubGeocoder(result: .success("東京都 渋谷区 道玄坂 2-29-5"))
        let result = try await stubGeo.reverseGeocode(
            location: CLLocation(latitude: 35.658, longitude: 139.701)
        )
        XCTAssertEqual(result, "東京都 渋谷区 道玄坂 2-29-5")
    }

    /// (b) 0 件相当（住所組み立て失敗）で nil が返る。
    func test_geocoder_returnsNil_whenNoAddress_S4_001() async throws {
        let stubGeo = StubGeocoder(result: .success(nil))
        let result = try await stubGeo.reverseGeocode(
            location: CLLocation(latitude: 35.658, longitude: 139.701)
        )
        XCTAssertNil(result)
    }

    /// (c) ネットワーク失敗で throw → PlaceLookupService 側で握って nil 化される。
    func test_lookup_withGeocoderNetworkFailure_returnsNil_S4_001() async {
        let stubSearcher = StubLocalSearcher(result: .success([]))
        let stubGeo = StubGeocoder(result: .failure(StubError.network))
        let sut = PlaceLookupService(poiSearcher: stubSearcher, geocoder: stubGeo)

        let candidate = await sut.lookup(
            coordinate: CLLocationCoordinate2D(latitude: 35.658, longitude: 139.701)
        )
        // POI ヒット 0 件 + 逆ジオ失敗 → 全体 nil
        XCTAssertNil(candidate)
    }

    // MARK: - POI 失敗時に住所 fallback

    func test_lookup_withPOIFailure_fallbacksToAddress() async {
        let stubSearcher = StubLocalSearcher(result: .failure(StubError.network))
        let stubGeo = StubGeocoder(result: .success("東京都 渋谷区"))
        let sut = PlaceLookupService(poiSearcher: stubSearcher, geocoder: stubGeo)

        let candidate = await sut.lookup(
            coordinate: CLLocationCoordinate2D(latitude: 35.658, longitude: 139.701)
        )

        XCTAssertEqual(candidate?.address, "東京都 渋谷区")
        XCTAssertNil(candidate?.name)
    }

    // MARK: - (d) LocationService 経由で PinRecord に書き込まれる

    func test_locationService_writesPlaceInfoIntoPinRecord() async throws {
        let repo = try makeInMemoryRepository()
        // 短時間で滞留判定するよう minDuration を 60 秒に下げる
        let stayDetector = StayDetector(config: StayDetectionConfig(minDuration: 60, radiusMeters: 10))
        let provider = StubPlaceProvider(candidate: PlaceCandidate(
            name: "スターバックス渋谷店",
            url: URL(string: "https://maps.apple.com/?q=Starbucks"),
            address: nil
        ))
        let sut = LocationService(repository: repo, stayDetector: stayDetector, placeProvider: provider)

        // 同一座標で 60 秒以上滞留 → 半径外移動でピン化
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let p1 = CLLocation(coordinate: .init(latitude: 35.658, longitude: 139.701),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base)
        let p2 = CLLocation(coordinate: .init(latitude: 35.658, longitude: 139.701),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base.addingTimeInterval(70))
        // 半径外への退出。緯度方向に 0.002 度（約 222m）動かす
        let p3 = CLLocation(coordinate: .init(latitude: 35.660, longitude: 139.701),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base.addingTimeInterval(140))

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])
        sut._ingestForTesting([p3])

        // PlaceProvider は async で呼ばれるため、書き込みが完了するまで少し待つ。
        // 実装は MainActor の Task で連結されるため、何度か main run loop に yield すれば十分。
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let unwrapped = try XCTUnwrap(trip)
        let pin = try XCTUnwrap(unwrapped.pins.first)
        XCTAssertEqual(pin.placeName, "スターバックス渋谷店")
        XCTAssertEqual(pin.placeURL?.absoluteString, "https://maps.apple.com/?q=Starbucks")
    }

    // MARK: - S5-007: PinRecord.address 書き戻し

    /// (S5-007 ケース 1) MKLocalSearch ヒット時、PlaceCandidate.address が
    /// PinRecord.address に書き戻される（POI 経由）。
    func test_locationService_writesAddressIntoPinRecord_whenPOIHit_withAddress_S5_007() async throws {
        let repo = try makeInMemoryRepository()
        let stayDetector = StayDetector(config: StayDetectionConfig(minDuration: 60, radiusMeters: 10))
        let provider = StubPlaceProvider(candidate: PlaceCandidate(
            name: "スターバックス渋谷店",
            url: URL(string: "https://maps.apple.com/?q=Starbucks"),
            address: "東京都 渋谷区 道玄坂 2-29-5"
        ))
        let sut = LocationService(repository: repo, stayDetector: stayDetector, placeProvider: provider)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let p1 = CLLocation(coordinate: .init(latitude: 35.658, longitude: 139.701),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: base)
        let p2 = CLLocation(coordinate: .init(latitude: 35.658, longitude: 139.701),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base.addingTimeInterval(70))
        let p3 = CLLocation(coordinate: .init(latitude: 35.660, longitude: 139.701),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base.addingTimeInterval(140))

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])
        sut._ingestForTesting([p3])

        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let pin = try XCTUnwrap(try XCTUnwrap(trip).pins.first)
        XCTAssertEqual(pin.placeName, "スターバックス渋谷店")
        XCTAssertEqual(pin.address, "東京都 渋谷区 道玄坂 2-29-5",
                       "S5-007: POI ヒット時にも MKMapItem.address?.fullAddress が書き戻される")
    }

    /// (S5-007 ケース 2) MKLocalSearch 0 件 → reverseGeocode 由来の住所が
    /// PlaceCandidate.address として渡され、PinRecord.address に書き戻される。
    func test_locationService_writesAddressIntoPinRecord_whenReverseGeocodeFallback_S5_007() async throws {
        let repo = try makeInMemoryRepository()
        let stayDetector = StayDetector(config: StayDetectionConfig(minDuration: 60, radiusMeters: 10))
        // POI 0 件 → 逆ジオコーディング fallback の出力は name=nil, url=nil, address=住所
        let provider = StubPlaceProvider(candidate: PlaceCandidate(
            name: nil,
            url: nil,
            address: "東京都 千代田区 丸の内 1-9-1"
        ))
        let sut = LocationService(repository: repo, stayDetector: stayDetector, placeProvider: provider)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let p1 = CLLocation(coordinate: .init(latitude: 35.6812, longitude: 139.7671),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: base)
        let p2 = CLLocation(coordinate: .init(latitude: 35.6812, longitude: 139.7671),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base.addingTimeInterval(70))
        let p3 = CLLocation(coordinate: .init(latitude: 35.6832, longitude: 139.7671),
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                            timestamp: base.addingTimeInterval(140))

        sut._ingestForTesting([p1])
        sut._ingestForTesting([p2])
        sut._ingestForTesting([p3])

        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let pin = try XCTUnwrap(try XCTUnwrap(trip).pins.first)
        // S6-013: POI ヒット 0 件時は placeName は nil のまま（住所に fallback しない）。
        // 住所は address フィールドに別途保存されるので、UI 側で「お店情報」と「住所」を
        // それぞれ別表示できる（PinDetailView / HistoryDetailPlaceList）。
        XCTAssertNil(pin.placeName,
                     "S6-013: POI なしのとき placeName は nil（住所は address に分離保存）")
        XCTAssertEqual(pin.address, "東京都 千代田区 丸の内 1-9-1",
                       "S5-007: 逆ジオコーディング fallback でも address が書き戻される")
        XCTAssertNil(pin.placeURL)
    }
}

// MARK: - Test doubles

/// LocalSearchPerforming のスタブ。事前定義した結果を返す。
private struct StubLocalSearcher: LocalSearchPerforming {
    enum Outcome {
        case success([PlaceCandidate])
        case failure(Error)
    }
    let result: Outcome
    func searchPOI(in region: MKCoordinateRegion) async throws -> [PlaceCandidate] {
        switch result {
        case .success(let candidates): return candidates
        case .failure(let err): throw err
        }
    }
}

/// GeocoderPerforming のスタブ。住所文字列を直接返す。
private struct StubGeocoder: GeocoderPerforming {
    enum Outcome {
        case success(String?)
        case failure(Error)
    }
    let result: Outcome
    func reverseGeocode(location: CLLocation) async throws -> String? {
        switch result {
        case .success(let str): return str
        case .failure(let err): throw err
        }
    }
}

private enum StubError: Error {
    case network
}

/// LocationService のテストで使う、最小の PlaceProviderProtocol 実装。
private struct StubPlaceProvider: PlaceProviderProtocol {
    let candidate: PlaceCandidate?
    func lookup(coordinate: CLLocationCoordinate2D) async -> PlaceCandidate? {
        return candidate
    }
}
