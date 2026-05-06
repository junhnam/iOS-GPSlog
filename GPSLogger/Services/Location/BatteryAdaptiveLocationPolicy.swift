import Foundation
import CoreLocation

/// バッテリー適応型位置情報ポリシー（S6-005）。
///
/// 走行状態 / 停車状態 / 自宅滞在状態に応じて、CLLocationManager の
/// desiredAccuracy と distanceFilter の設定値を決定する純粋関数 struct。
///
/// 設計方針:
///   - ステートレスな `Sendable` 構造体とする。状態（recentLocations 等）は
///     呼び出し側（LocationService）が保持し、Policy 自体は副作用を持たない。
///   - Swift 6 strict concurrency: `Sendable` を自然に満たすため actor は不要。
///   - Sprint 3 の `updateDynamicAccuracy` ロジック（5秒/10m 短時間判定）と
///     本 Policy の長時間判定（5分/100m）は判定ウィンドウが異なり用途が別個のため、
///     `updateDynamicAccuracy` は既存テスト回帰防止のために存置し、本 Policy は
///     distanceFilter の動的切り替えを担う補完的な役割として統合する。
///
/// 判定ロジック（チケット S6-005 受け入れ条件）:
///   - 自宅滞在中: `.stopRecording`
///   - 走行中（直近 5 分以内に 100m 超移動）: `.driving` (Best / 10m)
///   - 停車中（直近 5 分以内に 100m 以下）: `.stopped` (HundredMeters / 100m)
struct BatteryAdaptiveLocationPolicy: Sendable {

    // MARK: - Decision

    /// ポリシー評価の出力。LocationService がこれを読んで manager の設定を変更する。
    enum Decision: Equatable, Sendable {
        /// 自宅滞在中。位置更新を継続しても記録しない（SLC 移行は LocationService 側が担当）。
        case stopRecording
        /// 走行中。精度 Best / distanceFilter 10m で高頻度更新する。
        case driving(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance)
        /// 停車中。精度 HundredMeters / distanceFilter 100m で更新を間引く。
        case stopped(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance)
    }

    // MARK: - Constants

    /// 走行判定ウィンドウ（秒）。直近この時間内に `drivingDistanceThresholdMeters` 超の
    /// 移動があれば「走行中」と判定する。
    static let drivingTimeWindowSeconds: TimeInterval = 5 * 60  // 5 分

    /// 走行判定の移動距離しきい値（メートル）。
    static let drivingDistanceThresholdMeters: CLLocationDistance = 100

    /// 走行中の desiredAccuracy。
    static let drivingAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest

    /// 走行中の distanceFilter（メートル）。
    static let drivingDistanceFilter: CLLocationDistance = 10

    /// 停車中の desiredAccuracy。
    static let stoppedAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters

    /// 停車中の distanceFilter（メートル）。
    static let stoppedDistanceFilter: CLLocationDistance = 100

    // MARK: - Evaluation

    /// ポリシーを評価し、LocationManager に適用すべき設定を返す。
    ///
    /// - Parameters:
    ///   - recentLocations: 直近の位置情報配列（新しい順ではなく記録順）。
    ///     最低 2 件以上あることが望ましい。1 件以下の場合は `.stopped` を返す。
    ///   - homeLocation: 登録済み自宅位置。nil = 自宅未登録（判定スキップ）。
    ///   - homeRadiusMeters: 自宅判定半径（メートル）。
    ///   - now: 判定基準時刻（テスト時に固定日時を渡せるよう引数化）。
    /// - Returns: Decision
    func evaluate(recentLocations: [CLLocation],
                  homeLocation: HomeLocation?,
                  homeRadiusMeters: Double,
                  now: Date = Date()) -> Decision {

        // 1. 自宅判定
        if let latest = recentLocations.last {
            let state = HomeDetector.detect(
                homeLocation: homeLocation,
                radius: homeRadiusMeters,
                currentLocation: latest
            )
            if state == .atHome {
                return .stopRecording
            }
        }

        // 2. 走行 / 停車判定
        // 直近 5 分以内の点だけを対象に、最も古い点と最新点の距離を計算する。
        let windowStart = now.addingTimeInterval(-Self.drivingTimeWindowSeconds)
        let windowLocations = recentLocations.filter { $0.timestamp >= windowStart }

        guard windowLocations.count >= 2,
              let oldest = windowLocations.first,
              let latest = windowLocations.last else {
            // 判定に十分な点数がなければ停車扱い（省電力優先）
            return .stopped(
                accuracy: Self.stoppedAccuracy,
                distanceFilter: Self.stoppedDistanceFilter
            )
        }

        let distance = latest.distance(from: oldest)
        if distance > Self.drivingDistanceThresholdMeters {
            return .driving(
                accuracy: Self.drivingAccuracy,
                distanceFilter: Self.drivingDistanceFilter
            )
        } else {
            return .stopped(
                accuracy: Self.stoppedAccuracy,
                distanceFilter: Self.stoppedDistanceFilter
            )
        }
    }
}
