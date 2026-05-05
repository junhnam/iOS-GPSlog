import Foundation
import CoreLocation
import os

/// 総移動距離（km/m）を計算するための純粋ロジック群。
///
/// 設計方針（S2-004）:
///   - `CLLocation.distance(from:)` をラップ。Apple 内部実装が WGS84 ベースのため自前 Haversine は不要
///   - 計算は「保存時に区間距離を加算」方式（バッテリー対策）。リアルタイム累計はしない
///   - GPS 揺らぎ排除のため、1m 未満の点間距離はスキップ
///   - 1km 以上の飛び（テレポート相当）は警告ログのみ。Sprint 6 の異常値検出で本格対応
enum TripDistanceCalculator {

    /// GPS 揺らぎ排除のしきい値（m）。1m 未満の点間移動は計算に含めない。
    static let minDistanceMeters: Double = 1.0

    /// テレポート警告のしきい値（m）。1km 以上飛んだら警告ログ。
    static let teleportWarningMeters: Double = 1000.0

    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "TripDistanceCalculator")

    /// 2 点間の距離（メートル）を返す。
    /// `CLLocation.distance(from:)` をラップし、テレポート検知用の警告ログを出す。
    static func distance(from: CLLocation, to: CLLocation) -> Double {
        let meters = to.distance(from: from)
        if meters >= teleportWarningMeters {
            logger.warning("テレポート相当の距離: \(meters, format: .fixed(precision: 1)) m。一時的なGPS誤差の可能性あり。")
        }
        return meters
    }

    /// 連続する点列の総距離（メートル）を返す。
    /// `< minDistanceMeters` の区間はスキップ（GPS 揺らぎ排除）。
    static func totalDistance(of locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<locations.count {
            let segment = distance(from: locations[i - 1], to: locations[i])
            if segment >= minDistanceMeters {
                total += segment
            }
        }
        return total
    }

    /// メートルを km へ変換し、小数点第 2 位で丸める（四捨五入）。
    /// 例: 12345m → 12.35km、12344m → 12.34km
    static func kilometers(_ meters: Double) -> Double {
        let km = meters / 1000.0
        return (km * 100).rounded() / 100
    }

    /// 表示用フォーマット。例: 12345m → "12.35 km"。
    static func formatKilometers(_ meters: Double) -> String {
        return String(format: "%.2f km", kilometers(meters))
    }
}
