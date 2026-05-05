import Foundation
import SwiftData

/// 経路点（GPS で取得した1つの位置情報）を表す SwiftData モデル。
///
/// 1 点 = `latitude` + `longitude` + `timestamp` の最小構成。
/// 親 TripRecord への逆参照を持ち、`TripRecord.routePoints` から
/// cascade delete で同時削除される。
///
/// Sprint 2 で導入されるフィールド:
///   - `latitude`、`longitude`、`timestamp`、`trip`
///
/// Sprint 3 以降で追加予定のフィールド（このファイルでは未定義）:
///   - 速度、進行方位、精度（horizontalAccuracy）等。
///     ピン化判定や経路の品質評価に必要になった段階で追加する。
@Model
final class RoutePoint {
    /// 緯度（WGS84）。`CLLocation.coordinate.latitude` の値をそのまま入れる。
    var latitude: Double

    /// 経度（WGS84）。`CLLocation.coordinate.longitude` の値をそのまま入れる。
    var longitude: Double

    /// この点が記録された時刻。経路を時系列順に並べるためのキー。
    var timestamp: Date

    /// 親となる TripRecord への逆参照。
    /// `TripRecord.routePoints` 側で `inverse: \RoutePoint.trip` と紐付けている。
    var trip: TripRecord?

    init(latitude: Double,
         longitude: Double,
         timestamp: Date,
         trip: TripRecord? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.trip = trip
    }
}
