import Foundation
import CoreLocation

/// 滞留検出のしきい値設定（S2-006）。
/// CLAUDE.md 要件「10分以上同じ位置に留まっていればピン化」に対応。
/// `radiusMeters` は GPS 精度（kCLLocationAccuracyBest = 約 5〜10m）に揺らぎマージンを足した値。
///
/// ## S6-012: 半径 30m → 100m 拡大（大型店対応）
/// jun さんの実機検証（2026-05-09）で「4 店舗で各 20 分滞在 → ピン 1 件」問題を確認。
/// 原因: 大型店舗内の回遊（30m 以上歩く）でアンカーが切り替わり、累積滞留時間が minDuration に
/// 届かないまま破棄されていた。100m に拡大することで店内回遊を「同一滞留」として扱う。
/// じゅんさん判断: 大型店対応優先 / 設定画面での可変化は不要（固定値）。
/// `RetroactiveStayDetector` の冪等性ガードも同 config を共有するため、自動的に 100m に追従する。
struct StayDetectionConfig {
    /// 滞留と見なす最小継続時間（秒）。デフォルト 10 分 = 600 秒。
    let minDuration: TimeInterval
    /// 滞留と見なす半径（メートル）。デフォルト 100m（S6-012: 大型店対応のため 30m から拡大）。
    let radiusMeters: Double

    init(minDuration: TimeInterval = 600, radiusMeters: Double = 100) {
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
/// S6-010 A 案: 内部状態を UserDefaults に永続化し、タスクキル後の再起動時に復元する。
///   - 永続化キー名前空間: `gpslogger.staydetector.v1.*`
///   - `anchorLocation`（緯度・経度）/ `stayStartedAt` / `lastInsideAt` を保存
///   - init 時に復元。ただし `lastInsideAt` から `minDuration * 2` 以上経過した
///     古い状態は「失効」とみなして破棄する（古い滞留判定の引きずり防止）
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

    // MARK: - S6-023 D-B: anchor 状態の外部公開

    /// anchor が立っている（= 滞留候補が生まれている）かどうかを返す（S6-023 D-B）。
    ///
    /// `LocationService.updateBatteryPolicy` がこの値を参照し、
    /// anchor 中は distanceFilter を緩めないようにする。
    /// anchor が立っていない（anchorLocation == nil）か失効している場合は false を返す。
    var isInsideAnchor: Bool {
        anchorLocation != nil
    }

    // MARK: - A 案: UserDefaults 永続化

    /// 永続化に使用する UserDefaults。テストでは独立スイートを差し込める。
    private let defaults: UserDefaults

    /// UserDefaults キーの名前空間（S6-010 A 案）。
    enum PersistenceKeys {
        static let anchorLatitude  = "gpslogger.staydetector.v1.anchorLatitude"
        static let anchorLongitude = "gpslogger.staydetector.v1.anchorLongitude"
        static let stayStartedAt   = "gpslogger.staydetector.v1.stayStartedAt"
        static let lastInsideAt    = "gpslogger.staydetector.v1.lastInsideAt"
    }

    /// 状態が「失効」とみなされるまでの時間 = minDuration * 2。
    /// `lastInsideAt` からこの時間以上経過した状態は init 時に破棄する。
    private var expirationInterval: TimeInterval { config.minDuration * 2 }

    // MARK: - Init

    init(config: StayDetectionConfig = StayDetectionConfig(),
         defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
        // A 案: UserDefaults から前回の状態を復元する
        restoreStateFromDefaults()
    }

    // MARK: - A 案: 状態復元

    /// UserDefaults から内部状態を復元する。
    ///
    /// 復元条件:
    ///   - anchorLatitude / anchorLongitude / stayStartedAt / lastInsideAt がすべて保存済み
    ///   - `lastInsideAt` から現在時刻まで `minDuration * 2` 未満（失効していない）
    ///
    /// 条件を満たさない場合は状態を nil のまま保持し、anchorLocation を新たに作り直す。
    private func restoreStateFromDefaults() {
        // anchorLocation の復元
        guard defaults.object(forKey: PersistenceKeys.anchorLatitude) != nil,
              defaults.object(forKey: PersistenceKeys.anchorLongitude) != nil else {
            return
        }
        let lat = defaults.double(forKey: PersistenceKeys.anchorLatitude)
        let lon = defaults.double(forKey: PersistenceKeys.anchorLongitude)

        // stayStartedAt / lastInsideAt の復元
        guard let startedData = defaults.object(forKey: PersistenceKeys.stayStartedAt) as? Date,
              let lastData = defaults.object(forKey: PersistenceKeys.lastInsideAt) as? Date else {
            return
        }

        // 失効チェック: lastInsideAt から minDuration * 2 以上経過していたら破棄
        let elapsed = Date().timeIntervalSince(lastData)
        if elapsed >= expirationInterval {
            // 失効した状態は UserDefaults からも削除して clean にする
            clearPersistedState()
            return
        }

        // 復元成功: 内部状態を設定
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        anchorLocation = CLLocation(coordinate: coordinate,
                                    altitude: 0,
                                    horizontalAccuracy: 30,
                                    verticalAccuracy: -1,
                                    timestamp: startedData)
        stayStartedAt = startedData
        lastInsideAt = lastData
    }

    // MARK: - A 案: 状態永続化

    /// 現在の内部状態を UserDefaults に書き込む。
    /// `ingest(location:)` で状態が更新されるたびに呼ばれる。
    /// 数分に 1 回程度の呼び出しなので、パフォーマンス影響は無視できる。
    private func persistCurrentState() {
        guard let anchor = anchorLocation,
              let started = stayStartedAt,
              let lastInside = lastInsideAt else {
            // anchorLocation が nil の場合は保存データをクリアする
            clearPersistedState()
            return
        }
        defaults.set(anchor.coordinate.latitude, forKey: PersistenceKeys.anchorLatitude)
        defaults.set(anchor.coordinate.longitude, forKey: PersistenceKeys.anchorLongitude)
        defaults.set(started, forKey: PersistenceKeys.stayStartedAt)
        defaults.set(lastInside, forKey: PersistenceKeys.lastInsideAt)
    }

    /// UserDefaults の永続化データを削除する。
    private func clearPersistedState() {
        defaults.removeObject(forKey: PersistenceKeys.anchorLatitude)
        defaults.removeObject(forKey: PersistenceKeys.anchorLongitude)
        defaults.removeObject(forKey: PersistenceKeys.stayStartedAt)
        defaults.removeObject(forKey: PersistenceKeys.lastInsideAt)
    }

    // MARK: - Core Logic

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
            persistCurrentState()
            return .moving
        }

        let distance = location.distance(from: anchor)
        if distance <= config.radiusMeters {
            // 半径内: 滞留候補を更新。
            lastInsideAt = location.timestamp
            persistCurrentState()
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
        // S6-023 D-C: duration 計算を時系列ベースに変更。
        // 従来は `lastInsideAt - stayStartedAt` で計算していたが、
        // バッテリー最適化（distanceFilter=100m）が滞留中の GPS 配信を止めると
        // lastInsideAt が更新されず duration ≒ 0 になるバグがあった。
        // 修正: 「anchor の stayStartedAt と離脱点 location.timestamp の差」で duration を計算する。
        // これにより、滞留中に GPS 点が届かなかった（間引かれた）場合でも、
        // 離脱点 1 点のタイムスタンプと anchor 設定時刻の差で正確な滞留時間を算出できる。
        let pin: PinRecord? = {
            guard let start = stayStartedAt else { return nil }
            // 離脱点の timestamp と anchor 開始時刻の差を duration として使用（D-C 修正）
            let duration = location.timestamp.timeIntervalSince(start)
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
        persistCurrentState()

        if let pin {
            return .stayEnded(pin)
        }
        return .moving
    }

    /// テスト用: 内部状態をリセット。UserDefaults の永続化データも同時にクリアする（S6-010 A 案）。
    func _resetForTesting() {
        anchorLocation = nil
        stayStartedAt = nil
        lastInsideAt = nil
        clearPersistedState()
    }
}
