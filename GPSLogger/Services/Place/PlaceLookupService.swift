import Foundation
import CoreLocation
import MapKit

/// 滞留地点に紐づく「お店 / 施設情報」を表す値（S3-007）。
///
/// `name` は MKLocalSearch / 逆ジオコーディングから得られた最も上位の候補。
/// `url` は Apple Maps SDK が返す `MKMapItem.url`（あれば）をそのまま String 化したもの。
/// `address` は `CLPlacemark` を組み立てた住所文字列（あれば）。
///
/// すべて Optional だが、少なくともどれか 1 つは値が入っていることを呼び出し側で期待してよい。
struct PlaceCandidate: Equatable {
    /// お店 / 施設名。例: 「スターバックス渋谷店」「東京駅」。
    let name: String?
    /// 詳細 URL。`MKMapItem.url` の値。Apple Maps の URL スキームになることが多い。
    let url: URL?
    /// 住所文字列。MKLocalSearch のヒットが無い場合の fallback で使う。
    let address: String?
}

/// PlaceLookupService の抽象化（S3-007 受け入れ条件）。
///
/// 実装差し替えのモック化を可能にし、ネットワーク失敗時の挙動をユニットテストでカバーする。
/// 純関数的なインタフェースだが、内部実装は Apple MapKit / CoreLocation の async API を呼ぶため
/// `async throws` で揃える。
protocol PlaceProviderProtocol: Sendable {
    /// 指定座標の周辺から「お店 / 施設」候補を 1 件返す。
    /// - 検索結果が 1 件以上あれば最上位の `PlaceCandidate` を返す
    /// - 検索結果が 0 件なら逆ジオコーディングで住所のみ詰めた `PlaceCandidate` を返す
    /// - どちらも失敗（住所も取れない）した場合は nil を返す
    /// - ネットワークエラーやレート制限はエラーを throw せず、内部で握って nil もしくは住所のみで返す
    func lookup(coordinate: CLLocationCoordinate2D) async -> PlaceCandidate?
}

/// MKLocalSearch（Apple MapKit 標準・無料・認証不要）を使って滞留地点周辺のお店情報を取得する（S3-007）。
///
/// 設計方針:
///   - 半径 50m の正方形領域を `MKCoordinateRegion` で構築し POI のみを検索
///   - 結果 0 件のときは `CLGeocoder.reverseGeocodeLocation` で住所だけ取得し fallback
///   - MKLocalSearch / CLGeocoder のレート制限・ネットワーク失敗時は throw せず nil 化
///   - `Sendable` 準拠の `actor` ではなく struct + async でシンプルに（状態を持たない）
///
/// LocationService から呼ぶ際は `await` で受け、StayDetector の PinRecord 生成直後に
/// PinRecord.placeName / placeURL に書き戻す。
struct PlaceLookupService: PlaceProviderProtocol {
    /// 検索する正方形領域のひとつの辺の長さ（メートル）。
    /// 受け入れ条件「半径 50m」の正方形版（`MKCoordinateRegion` は矩形指定）。
    private static let searchSpanMeters: CLLocationDistance = 100

    /// POI 検索担当。テスト時は差し替え可能。既定は MapKit の MKLocalSearch を呼ぶ実装。
    private let poiSearcher: any LocalSearchPerforming

    /// 逆ジオコーディング担当。テスト時は差し替え可能。
    private let geocoder: any GeocoderPerforming

    init(
        poiSearcher: any LocalSearchPerforming = AppleLocalSearcher(),
        geocoder: any GeocoderPerforming = AppleGeocoder()
    ) {
        self.poiSearcher = poiSearcher
        self.geocoder = geocoder
    }

    func lookup(coordinate: CLLocationCoordinate2D) async -> PlaceCandidate? {
        if let candidate = await searchPointOfInterest(at: coordinate) {
            return candidate
        }
        // POI ヒット 0 件: 逆ジオコーディングで住所のみ返す
        if let address = await reverseGeocode(coordinate: coordinate) {
            return PlaceCandidate(name: nil, url: nil, address: address)
        }
        return nil
    }

    // MARK: - Private

    /// POI を検索して 1 件返す。失敗・0 件は nil。
    private func searchPointOfInterest(at coordinate: CLLocationCoordinate2D) async -> PlaceCandidate? {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Self.searchSpanMeters,
            longitudinalMeters: Self.searchSpanMeters
        )
        do {
            let candidates = try await poiSearcher.searchPOI(in: region)
            return candidates.first
        } catch {
            // レート制限 / ネットワーク失敗は握って nil。住所 fallback に進ませる。
            return nil
        }
    }

    /// 逆ジオコーディングで住所文字列を組み立てる。失敗は nil。
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            return try await geocoder.reverseGeocode(location: location)
        } catch {
            return nil
        }
    }
}

/// CLPlacemark から住所文字列を組み立てる共有ヘルパー。
/// 「administrativeArea + locality + thoroughfare + subThoroughfare」を「 」区切りで連結。
/// 例: 「東京都 渋谷区 道玄坂 2-29-5」。
/// 全て nil なら nil を返す。
enum PlacemarkAddressFormatter {
    static func format(administrativeArea: String?,
                       locality: String?,
                       thoroughfare: String?,
                       subThoroughfare: String?) -> String? {
        let components: [String?] = [administrativeArea, locality, thoroughfare, subThoroughfare]
        let joined = components
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    static func format(_ placemark: CLPlacemark) -> String? {
        return format(administrativeArea: placemark.administrativeArea,
                      locality: placemark.locality,
                      thoroughfare: placemark.thoroughfare,
                      subThoroughfare: placemark.subThoroughfare)
    }
}

// MARK: - Test seam protocols

/// POI 検索の最小限のインタフェース。テストでモック差し替えできるよう抽象化する（S3-007）。
/// `MKLocalSearch.Response` は public init を持たないためテストでスタブできない。
/// よって戻り値を `[PlaceCandidate]` に揃え、本番実装側で MKMapItem -> PlaceCandidate へ変換する。
protocol LocalSearchPerforming: Sendable {
    func searchPOI(in region: MKCoordinateRegion) async throws -> [PlaceCandidate]
}

/// MKLocalSearch を `LocalSearchPerforming` として包む実装。
/// `MKLocalSearch.Request` を組み立てて start() を呼び、結果を PlaceCandidate に変換する。
struct AppleLocalSearcher: LocalSearchPerforming {
    func searchPOI(in region: MKCoordinateRegion) async throws -> [PlaceCandidate] {
        let request = MKLocalSearch.Request()
        request.region = region
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems.map { item in
            PlaceCandidate(name: item.name, url: item.url, address: nil)
        }
    }
}

/// 逆ジオコーディングの最小限のインタフェース。
/// 戻り値は組み立て済みの住所文字列 (`String?`) で、CLPlacemark 自体を直接扱わない。
/// CLPlacemark のインスタンス生成は iOS で `init()` が unavailable なためテストで stub できないので、
/// プロトコル境界では文字列に統一してテスト容易性を確保する（S3-007）。
protocol GeocoderPerforming: Sendable {
    func reverseGeocode(location: CLLocation) async throws -> String?
}

/// CLGeocoder を `GeocoderPerforming` として包む実装。
/// `reverseGeocodeLocation` の結果から `PlacemarkAddressFormatter` で住所文字列を組み立てる。
struct AppleGeocoder: GeocoderPerforming {
    func reverseGeocode(location: CLLocation) async throws -> String? {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { return nil }
        return PlacemarkAddressFormatter.format(placemark)
    }
}
