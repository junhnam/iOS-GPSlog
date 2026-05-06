import Foundation
import CoreLocation

/// 自宅判定の状態（S3-003）。
///
/// - `.atHome`: 自宅半径内にいる。LocationService は記録をスキップする。
/// - `.away`: 自宅半径外にいる（自宅は登録済み）。通常通り記録する。
/// - `.unknown`: 自宅未登録または判定不能。通常通り記録する（後方互換）。
enum HomeState: Equatable, Sendable {
    case atHome
    case away
    case unknown
}

/// 自宅判定ロジック（S3-003）。
///
/// 設計方針:
///   - 純粋関数の `struct` として実装し、副作用なし → ユニットテストで容易に検証可能
///   - 入力: `homeLocation` / `radius` / `currentLocation`
///   - 出力: `HomeState`
///   - `homeLocation` が nil なら常に `.unknown`（後方互換）
///   - 半径ぴったり（distance == radius）は `.atHome` に含める仕様
///   - 距離計算は `CLLocation.distance(from:)`（球面距離）を使用。
///     Sprint 2 の `TripDistanceCalculator` は累積用なので流用しない。
///
/// 利用例:
/// ```swift
/// let state = HomeDetector.detect(
///     homeLocation: settings.homeLocation,
///     radius: settings.homeRadiusMeters,
///     currentLocation: location
/// )
/// guard state != .atHome else { return }  // 自宅滞在中は記録スキップ
/// ```
struct HomeDetector {
    /// 自宅判定を行う。
    /// - Parameters:
    ///   - homeLocation: 設定済みの自宅位置（nil = 未登録）
    ///   - radius: 自宅半径（メートル）。AppSettings.homeRadiusMeters を渡す
    ///   - currentLocation: 現在の CLLocation
    /// - Returns: HomeState
    static func detect(homeLocation: HomeLocation?,
                       radius: Double,
                       currentLocation: CLLocation) -> HomeState {
        guard let home = homeLocation else { return .unknown }
        let homeCL = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let distance = currentLocation.distance(from: homeCL)
        // 半径ぴったり（distance == radius）は atHome に含める（受け入れ条件: distance <= radius）
        return distance <= radius ? .atHome : .away
    }
}
