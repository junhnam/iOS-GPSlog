import Foundation
import CoreLocation

/// RoutePoint の DB 履歴から後追いで滞留区間を検出するサービス（S6-010 B 案）。
///
/// ## 設計思想
///
/// `StayDetector` はリアルタイムに位置情報を受け取って滞留を検知するが、
/// iOS が `pausesLocationUpdatesAutomatically = true` によって更新を自動停止したり、
/// アプリがタスクキルされた場合、その間は `StayDetector.ingest()` が呼ばれない。
/// → 滞留区間のピン作成が抜け落ちる。
///
/// 本サービスは「既に DB に保存された RoutePoint 配列を後から走査することで
/// 滞留区間を推定してピンを生成する」純粋関数的なアプローチで上記の穴を埋める。
///
/// ## 判定ロジック
///
/// 時系列ソート済みの RoutePoint 配列を受け取り、連続する点群の近接性を評価する。
/// - anchor（最初の点）から `config.radiusMeters` 以内に居続ける点群を収集
/// - 半径外の点が来た時点で「区間終了」
/// - 区間の継続時間 >= `config.minDuration` なら滞留と判定 → PinRecord を生成
/// - anchor を次の点に移して繰り返す
///
/// iOS が自動停止した場合、点の間隔が広がるが、それは「静止していた証拠」になる。
/// 移動中は点が密に取得されるが、静止中は取得が止まるため、
/// 間隔の大きい点列は「そこにずっといた」可能性が高い。
///
/// ## 冪等性
///
/// 既存の PinRecord と座標 + 時刻が近接（半径内かつ `minDuration / 2` 以内）なら
/// 新規作成をスキップする。呼び出し元 (`LocationService`) が既存ピンリストを渡す必要がある。
///
/// ## 発火タイミング
///
/// - `LocationService.resumeTrackingAfterRelaunch()` 末尾（SLC 起床 / scenePhase 復帰）
/// - アプリ起動時（`AppDependencyContainer` 初期化後 / `RootView.task`）
///
/// ## Swift 6 / SwiftData の注意
///
/// - `@MainActor struct` で実装。SwiftData の `@Model` クラスは MainActor 隔離が必要。
/// - `detectStays(from:excluding:)` は純粋関数として実装し、副作用を排除する。
///   DB 書き込みは呼び出し元（LocationService）が担う。
/// - 新規 `@Model` クラスは追加しない（ios26-swiftdata.md の落とし穴回避）。
@MainActor
struct RetroactiveStayDetector {

    let config: StayDetectionConfig

    init(config: StayDetectionConfig = StayDetectionConfig()) {
        self.config = config
    }

    // MARK: - Core Detection

    /// 時系列ソート済みの RoutePoint 配列から滞留候補を検出し、PinRecord の配列を返す。
    ///
    /// - Parameters:
    ///   - points: 時系列昇順にソートされた RoutePoint 配列
    ///   - existingPins: 既存の PinRecord 配列（冪等性チェックに使用）
    /// - Returns: 新規作成すべき PinRecord の配列（既存ピンと重複するものはスキップ済み）
    func detectStays(from points: [RoutePoint],
                     excluding existingPins: [PinRecord] = []) -> [PinRecord] {
        guard points.count >= 2 else { return [] }

        var newPins: [PinRecord] = []
        var anchorIndex = 0
        var i = 1

        while i < points.count {
            let anchor = points[anchorIndex]
            let current = points[i]

            let distance = haversineDistance(
                lat1: anchor.latitude, lon1: anchor.longitude,
                lat2: current.latitude, lon2: current.longitude
            )

            if distance <= config.radiusMeters {
                // 半径内: 引き続き同じ anchor に居続けている
                i += 1
            } else {
                // 半径外に出た: 区間を評価
                let lastInside = points[i - 1]
                let duration = lastInside.timestamp.timeIntervalSince(anchor.timestamp)

                if duration >= config.minDuration {
                    let candidate = PinRecord(
                        latitude: anchor.latitude,
                        longitude: anchor.longitude,
                        stayedFrom: anchor.timestamp,
                        stayedDurationSeconds: duration
                    )
                    if !isDuplicate(candidate, against: existingPins + newPins) {
                        newPins.append(candidate)
                    }
                }
                // anchor を current の位置に移してループ継続
                anchorIndex = i
                i += 1
            }
        }

        // ループ末尾の残り: 最後まで半径内に居続けたケース
        if anchorIndex < points.count - 1 {
            let anchor = points[anchorIndex]
            let last = points[points.count - 1]
            let duration = last.timestamp.timeIntervalSince(anchor.timestamp)

            if duration >= config.minDuration {
                let candidate = PinRecord(
                    latitude: anchor.latitude,
                    longitude: anchor.longitude,
                    stayedFrom: anchor.timestamp,
                    stayedDurationSeconds: duration
                )
                if !isDuplicate(candidate, against: existingPins + newPins) {
                    newPins.append(candidate)
                }
            }
        }

        return newPins
    }

    // MARK: - Idempotency Check

    /// 候補ピンが既存ピンリストと「同一」かどうかを判定する。
    ///
    /// 同一条件:
    ///   - 距離が `config.radiusMeters` 以内（同じ場所）
    ///   - `stayedFrom` の差が `config.minDuration / 2`（デフォルト 300 秒）以内
    ///
    /// この条件を満たす既存ピンがあれば「重複」とみなしてスキップする。
    func isDuplicate(_ candidate: PinRecord, against existingPins: [PinRecord]) -> Bool {
        let halfDuration = config.minDuration / 2  // デフォルト 300 秒

        return existingPins.contains { existing in
            let distMeters = haversineDistance(
                lat1: candidate.latitude, lon1: candidate.longitude,
                lat2: existing.latitude,  lon2: existing.longitude
            )
            let timeDiff = abs(candidate.stayedFrom.timeIntervalSince(existing.stayedFrom))
            return distMeters <= config.radiusMeters && timeDiff <= halfDuration
        }
    }

    // MARK: - Geometry

    /// Haversine 公式で 2 点間の距離（メートル）を計算する。
    ///
    /// CLLocation を使わず純粋な値型計算にすることで、
    /// テストでの CLLocation インスタンス生成コストを排除し、
    /// 並行性・Sendable の問題も回避する。
    ///
    /// 精度: ±0.5% 程度（30m スケールでは ±15cm 相当で十分）。
    func haversineDistance(lat1: Double, lon1: Double,
                           lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0  // 地球半径（メートル）
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}
