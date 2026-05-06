import Foundation
import CoreLocation

/// 自宅位置を表すモデル（S3-001 / S3-002）。
///
/// SwiftData ではなく `Codable` struct として実装する設計判断:
///   - 自宅位置は「設定 = 1 件のみ」のシンプルな構造で、UserDefaults に JSON で
///     格納するほうが取り回しが良い。SwiftData の `@Relationship` 配列ルール
///     （= [] 必須）の落とし穴も避けられる（`.scrum/notes/ios26-swiftdata.md` 参照）。
///   - 後で SwiftData に移行する場合も Codable のままシリアライズで橋渡しできる。
///
/// 保持するフィールドは最小限:
///   - `latitude` / `longitude`: WGS84 の緯度経度
///   - `address`: 逆ジオコーディングで取得した住所文字列（取得失敗時は nil 許容）
///   - `registeredAt`: 登録日時（履歴用）
///
/// 半径（home radius）は `AppSettings.homeRadiusMeters` 側で別管理する。
/// HomeLocation は「点」を表し、半径は「設定」として独立に持つ方針。
struct HomeLocation: Codable, Equatable, Hashable, Sendable {
    /// WGS84 緯度
    let latitude: Double

    /// WGS84 経度
    let longitude: Double

    /// 逆ジオコーディングで取得した住所文字列。
    /// ネットワーク失敗等で取れなかった場合は nil（受け入れ条件: 住所欠落でも保存可能）。
    let address: String?

    /// 登録日時。表示や監査用に保持。
    let registeredAt: Date

    init(latitude: Double,
         longitude: Double,
         address: String? = nil,
         registeredAt: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.registeredAt = registeredAt
    }

    /// CoreLocation 連携用に CLLocationCoordinate2D に変換。
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
