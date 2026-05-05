import Foundation
import CoreLocation

/// 滞留検出のしきい値設定（S2-006）。
/// CLAUDE.md 要件「10分以上同じ位置に留まっていればピン化」に対応。
/// `radiusMeters` は GPS 精度（kCLLocationAccuracyBest = 約 5〜10m）に揺らぎマージンを足した値。
struct StayDetectionConfig {
    /// 滞留と見なす最小継続時間（秒）。デフォルト 10 分 = 600 秒。
    let minDuration: TimeInterval
    /// 滞留と見なす半径（メートル）。デフォルト 30m。
    let radiusMeters: Double

    init(minDuration: TimeInterval = 600, radiusMeters: Double = 30) {
        self.minDuration = minDuration
        self.radiusMeters = radiusMeters
    }
}

/// `StayDetector.ingest(location:)` の戻り値。
/// LocationService 側で switch しながら、永続化や経路記録の挙動を切り替える。
enum StayEvent: Equatable {
    /// 滞留中ではない（通常の移動中）。LocationService は通常通り経路保存を続ける。
    case moving

    /// 滞留中（半径内に居続けている）。新規 RoutePoint の保存は間引き対象。
    case staying

    /// 滞留中の点として間引かれた（呼び出し側は無視してよい）。
    case skipped

    /// 滞留が終了した（半径外への移動を検知）。引数の PinRecord を永続化する。
    case stayEnded(PinRecord)

    static func == (lhs: StayEvent, rhs: StayEvent) -> Bool {
        switch (lhs, rhs) {
        case (.moving, .moving), (.staying, .staying), (.skipped, .skipped):
            return true
        case (.stayEnded(let l), .stayEnded(let r)):
            return l.latitude == r.latitude
                && l.longitude == r.longitude
                && l.stayedFrom == r.stayedFrom
                && abs(l.stayedDurationSeconds - r.stayedDurationSeconds) < 0.001
        default:
            return false
        }
    }
}

/// 連続する位置情報から「同じ場所に 10 分以上いた」滞留区間を検出する（S2-006）。
///
/// 設計方針:
///   - 入力 1 点ごとに `ingest(location:)` を呼ぶストリーム型 API
///   - 内部で「滞留候補の中心点」と「直近の滞留開始時刻」を保持
///   - 中心点から `radiusMeters` 以内の点は同じ滞留と判定
///   - 半径外の点が来たタイミングで:
///     - 滞留時間 >= `minDuration` なら PinRecord を生成して返す
///     - そうでなければ「短期停止」として無視
///   - 中心点は滞留が始まった最初の点の座標をそのまま使う（簡易実装、Sprint 6 で重心へ精緻化）
///
/// LocationService から `ingest(location:) -> StayEvent` を呼び、戻り値で挙動を分岐する。
@MainActor
final class StayDetector {
    let config: StayDetectionConfig

    /// 現在の滞留中心。座標を直接持ち、CLLocation の余分な情報（accuracy 等）は捨てる。
    private var anchorLocation: CLLocation?

    /// 滞留候補の開始時刻。anchor が設定された時点の location.timestamp。
    private var stayStartedAt: Date?

    /// 直近の滞留候補内の点の timestamp。半径外への離脱検知時に「滞留終了時刻」として使う。
    private var lastInsideAt: Date?

    init(config: StayDetectionConfig = StayDetectionConfig()) {
        self.config = config
    }

    /// 1 点取り込み、現在の滞留状態に応じてイベントを返す。
    /// - 戻り値 `.moving`: 滞留候補なし。LocationService は通常通り経路保存。
    /// - 戻り値 `.staying`: 滞留候補が継続中（最初の数点）。経路保存は通常。
    /// - 戻り値 `.skipped`: 滞留中で、点を間引いた（経路保存しない）。
    /// - 戻り値 `.stayEnded(pin)`: 半径外へ離脱したタイミング。pin を永続化する。
    func ingest(location: CLLocation) -> StayEvent {
        // 滞留候補がまだない: 今の点を滞留候補のアンカーにする（仮）。
        // ただしこの段階では「滞留中」とは断言できない（10 分経過してから確定）。
        guard let anchor = anchorLocation else {
            anchorLocation = location
            stayStartedAt = location.timestamp
            lastInsideAt = location.timestamp
            return .moving
        }

        let distance = location.distance(from: anchor)
        if distance <= config.radiusMeters {
            // 半径内: 滞留候補を更新。
            lastInsideAt = location.timestamp
            // 既に minDuration を超えているなら「滞留中」状態。
            // 最初の minDuration 経過前の点は、滞留としても通常としても扱える。
            // ここでは「一度でも minDuration を超えたら staying、以降はその場の点を skipped」する仕様。
            if let start = stayStartedAt,
               location.timestamp.timeIntervalSince(start) >= config.minDuration {
                // 滞留が確定している間は、初回確定時のみ .staying、以降は .skipped で間引く。
                // 実装簡略化のため、確定前の点も含め半径内の点はすべて .staying とする
                // （受け入れ条件: 滞留中の RoutePoint は間引かれる = LocationService 側で skipped 扱い）。
                return .skipped
            }
            return .moving
        }

        // 半径外: 離脱検知。
        // ここで滞留時間 >= minDuration なら PinRecord を生成。
        let pin: PinRecord? = {
            guard let start = stayStartedAt,
                  let lastInside = lastInsideAt else { return nil }
            let duration = lastInside.timeIntervalSince(start)
            guard duration >= config.minDuration else { return nil }
            return PinRecord(latitude: anchor.coordinate.latitude,
                             longitude: anchor.coordinate.longitude,
                             stayedFrom: start,
                             stayedDurationSeconds: duration)
        }()

        // 状態リセット: 新しい点を新たな滞留候補のアンカーに（離脱直後から次の滞留判定を開始）。
        anchorLocation = location
        stayStartedAt = location.timestamp
        lastInsideAt = location.timestamp

        if let pin {
            return .stayEnded(pin)
        }
        return .moving
    }

    /// テスト用: 内部状態をリセット。
    func _resetForTesting() {
        anchorLocation = nil
        stayStartedAt = nil
        lastInsideAt = nil
    }
}
