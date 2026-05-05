import Foundation
import SwiftData

/// 1日分の移動記録を表す SwiftData モデル。
///
/// 「1日 = 1レコード」が基本方針で、`date` を主キーとして当日 0 時で正規化する。
/// 経路点（RoutePoint）と滞留ピン（PinRecord）はリレーションで保持し、
/// TripRecord が削除されたときに同時に削除される（cascade delete）。
///
/// Sprint 2 で導入されるフィールド:
///   - `date`、`startedAt`、`endedAt`、`totalDistanceMeters`、`routePoints`、`pins`
///
/// Sprint 3 以降で追加予定のフィールド（このファイルでは未定義）:
///   - 自宅 / 外出フラグ、CSV エクスポート済みフラグ、クラウド同期済みフラグ等
@Model
final class TripRecord {
    /// 当日の 0 時に正規化された日付。同一日付の重複保存を防ぐためユニーク制約を付与。
    /// 利用側では `Calendar.current.startOfDay(for: Date())` を入れる前提。
    @Attribute(.unique) var date: Date

    /// 当日に最初に位置情報が記録された時刻（記録開始時刻）。
    /// `date`（0 時）とは別。例: 2026-05-05 00:00:00 が `date` のとき、
    /// `startedAt` は 2026-05-05 09:30:42 のように具体的な開始時刻が入る。
    var startedAt: Date

    /// 当日の記録終了時刻。記録継続中は nil。
    /// 翌日になったタイミングや、トリガーモードでの停止操作時に書き込む。
    var endedAt: Date?

    /// 累積移動距離（メートル）。
    /// 内部はメートル保持で、表示時は `totalDistanceKm` 計算プロパティで km 換算する
    /// （精度ロスを防ぐため double のままメートルで保持する設計判断）。
    var totalDistanceMeters: Double

    /// この日の経路点。time 順に並べる前提（並べ替えは取得側で実施）。
    /// TripRecord 削除時に RoutePoint も削除する（cascade）。
    @Relationship(deleteRule: .cascade, inverse: \RoutePoint.trip)
    var routePoints: [RoutePoint]

    /// この日の滞留ピン。stayedFrom 順に並べる前提。
    /// TripRecord 削除時に PinRecord も削除する（cascade）。
    @Relationship(deleteRule: .cascade, inverse: \PinRecord.trip)
    var pins: [PinRecord]

    init(date: Date,
         startedAt: Date,
         endedAt: Date? = nil,
         totalDistanceMeters: Double = 0,
         routePoints: [RoutePoint] = [],
         pins: [PinRecord] = []) {
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalDistanceMeters = totalDistanceMeters
        self.routePoints = routePoints
        self.pins = pins
    }

    /// 表示用に小数点第 2 位で丸めた km 値。
    /// 例: 1234.567m → 1.23km（切り捨てではなく一般的な四捨五入）。
    /// HUD ラベル等でこの値を直接 String 化して表示する。
    var totalDistanceKm: Double {
        let km = totalDistanceMeters / 1000.0
        return (km * 100).rounded() / 100
    }
}
