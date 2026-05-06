import Foundation
import SwiftData

/// 滞留ピン（10 分以上同じ場所にいたと判定された箇所）を表す SwiftData モデル。
///
/// Sprint 2 では「位置と滞留時間」だけを記録する。
/// お店情報（placeName / placeURL）はフィールドだけ用意して nil で運用し、
/// Sprint 3 で MKLocalSearch を使った逆ジオコーディングと連携して書き込む。
/// この設計により Sprint 3 でのスキーマ変更（マイグレーション）コストを下げる。
///
/// Sprint 2 で導入されるフィールド:
///   - `latitude`、`longitude`、`stayedFrom`、`stayedDurationSeconds`、`placeName`、`placeURL`、`trip`
///
/// Sprint 3 以降で書き込まれるフィールド（このファイルでは Sprint 2 時点では nil）:
///   - `placeName`: MKLocalSearch から得たお店 / 施設名
///   - `placeURL`: そのお店の詳細 URL（Apple Maps URL スキーム or web URL）
@Model
final class PinRecord {
    /// 滞留地点の緯度（WGS84）。
    var latitude: Double

    /// 滞留地点の経度（WGS84）。
    var longitude: Double

    /// 滞留が開始した時刻（同じ位置に居続けはじめた時刻）。
    /// 重複ピン判定（既に作成済みのピンか）にも `stayedFrom + 座標` を用いる。
    var stayedFrom: Date

    /// 滞留していた継続時間（秒）。10 分以上が前提。
    /// 表示用には「約 N 分」へ変換する（N = stayedDurationSeconds / 60 の整数化）。
    var stayedDurationSeconds: Double

    /// お店 / 施設名。**Sprint 2 では nil。Sprint 3 で MKLocalSearch から書き込む。**
    var placeName: String?

    /// お店 / 施設の詳細 URL。**Sprint 2 では nil。Sprint 3 で MKLocalSearch から書き込む。**
    var placeURL: URL?

    /// 住所文字列（S5-007）。
    /// MKLocalSearch のヒット時は `MKMapItem.address?.fullAddress` 由来、
    /// POI ヒット 0 件時は `MKReverseGeocodingRequest` 由来の住所が入る。
    /// nil 許容: MKLocalSearch / 逆ジオコーディング双方が失敗した場合は nil のまま。
    /// CalendarSyncService の 3 段フォールバック（placeName → address → 座標）で利用される。
    /// iOS 26 SwiftData ノート #5 に従い、新規プロパティは Optional で既存 DB と互換を取る。
    var address: String?

    /// この PinRecord に対して作成済みの EKEvent.eventIdentifier（S4-003）。
    /// nil = 未作成。値あり = 既に EventKit にイベントが書き込まれている（重複作成防止）。
    /// iOS 26 SwiftData ノート #5 に従い、新規プロパティは Optional で既存 DB と互換を取る。
    var calendarEventIdentifier: String?

    /// 親となる TripRecord への逆参照。
    /// `TripRecord.pins` 側で `inverse: \PinRecord.trip` と紐付けている。
    var trip: TripRecord?

    init(latitude: Double,
         longitude: Double,
         stayedFrom: Date,
         stayedDurationSeconds: Double,
         placeName: String? = nil,
         placeURL: URL? = nil,
         address: String? = nil,
         calendarEventIdentifier: String? = nil,
         trip: TripRecord? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.stayedFrom = stayedFrom
        self.stayedDurationSeconds = stayedDurationSeconds
        self.placeName = placeName
        self.placeURL = placeURL
        self.address = address
        self.calendarEventIdentifier = calendarEventIdentifier
        self.trip = trip
    }
}
