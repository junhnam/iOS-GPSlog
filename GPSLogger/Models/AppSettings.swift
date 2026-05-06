import Foundation
import Observation

/// 記録モード（S3-001 / S3-004）。
///
/// - `continuous`: 常時記録（CLAUDE.md のデフォルト挙動）。
///   ※ 自宅判定が `.atHome` の場合は記録停止（S3-003 連携）。
/// - `trigger`: フローティングボタンで開始/停止を制御（S3-005）。
enum RecordingMode: String, Codable, CaseIterable, Sendable {
    case continuous
    case trigger

    var displayName: String {
        switch self {
        case .continuous: return "常時記録"
        case .trigger:    return "トリガー記録"
        }
    }
}

/// クラウドストレージの保存先種別（S5-001 / S5-003 / S5-004 / S5-005）。
///
/// - `googleDrive`: Google Drive（Sprint 5 Must。S5-001 で実装）
/// - `dropbox`: Dropbox（Sprint 6 へ繰越。enum 値だけ Sprint 5 で予約しておくと
///              UI 側 / Settings 側のスキーマ互換が Sprint 6 で楽になる）
///
/// nil（AppSettings.cloudProviderKind == nil）= 「未選択」状態。
/// 自動同期 ON でも cloudProviderKind が nil なら CloudUploadCoordinator は no-op。
enum CloudProviderKind: String, Codable, CaseIterable, Sendable {
    case googleDrive
    case dropbox

    var displayName: String {
        switch self {
        case .googleDrive: return "Google Drive"
        case .dropbox:     return "Dropbox"
        }
    }
}

/// アプリ全体の設定状態（S3-001）。
///
/// 役割:
///   - 設定画面（SettingsView）が読み書きする状態のソース・オブ・トゥルース
///   - UserDefaults との read/write を 1 箇所に集約
///   - LocationService 等のサービス層が AppSettings を参照して挙動を切り替える
///
/// 永続化キー（名前空間 `gpslogger.settings.v1.*`）:
///   - `gpslogger.settings.v1.recordingMode`: String (RecordingMode.rawValue)
///   - `gpslogger.settings.v1.homeLocation`: Data (HomeLocation を JSON エンコード)
///   - `gpslogger.settings.v1.homeRadiusMeters`: Double
///   - `gpslogger.settings.v1.calendarSyncEnabled`: Bool（S4-002 で追加）
///   - `gpslogger.settings.v1.calendarIdentifier`: String?（S4-002 で追加）
///
/// 設計判断:
///   - `@Observable` macro（iOS 17+）を採用。SwiftUI から `@Bindable` で双方向バインドできる。
///   - SwiftData ではなく UserDefaults に保存することで `@Relationship` 配列ルールの
///     落とし穴を回避（`.scrum/notes/ios26-swiftdata.md`）。
///   - 不正データ（破損 JSON 等）に出会った場合はデフォルト値にフォールバックする。
///     UserDefaults に書き込まずに済むよう「読み込み時のみ」フォールバックを行う。
///   - DI 用に UserDefaults を差し替え可能にし、テストで分離できるようにする。
@MainActor
@Observable
final class AppSettings {
    // MARK: - Keys

    enum Keys {
        static let recordingMode       = "gpslogger.settings.v1.recordingMode"
        static let homeLocation        = "gpslogger.settings.v1.homeLocation"
        static let homeRadiusMeters    = "gpslogger.settings.v1.homeRadiusMeters"
        // S4-002: カレンダー同期 ON/OFF と対象カレンダー識別子。
        static let calendarSyncEnabled = "gpslogger.settings.v1.calendarSyncEnabled"
        static let calendarIdentifier  = "gpslogger.settings.v1.calendarIdentifier"
        // S5-001 / S5-004: クラウド保存先 / 自動同期 ON/OFF。
        static let cloudProviderKind   = "gpslogger.settings.v1.cloudProviderKind"
        static let cloudAutoSyncEnabled = "gpslogger.settings.v1.cloudAutoSyncEnabled"
        // S6-004: DB 自動消去 ON/OFF / しきい値。
        static let dbAutoCleanupEnabled = "gpslogger.settings.v1.dbAutoCleanupEnabled"
        static let dbAutoCleanupThresholdGB = "gpslogger.settings.v1.dbAutoCleanupThresholdGB"
        // S6-006: バックグラウンド復帰用フラグ。kill 後の SLC 起床時に記録を再開するか判定する。
        static let wasTracking = "gpslogger.settings.v1.wasTracking"
    }

    // MARK: - Defaults

    static let defaultRecordingMode: RecordingMode = .continuous
    static let defaultHomeRadiusMeters: Double = 100.0
    static let homeRadiusMinMeters: Double = 50.0
    static let homeRadiusMaxMeters: Double = 300.0
    /// S4-002: カレンダー同期は既定 OFF（jun さんの明示的な ON 操作を要求）。
    static let defaultCalendarSyncEnabled: Bool = false
    /// S5-004: クラウド自動同期は既定 OFF（jun さんが明示的に ON にしないと動かない）。
    static let defaultCloudAutoSyncEnabled: Bool = false
    /// S6-004: DB 自動消去は既定 OFF（誤削除防止のため jun さんが明示的に ON にしないと動かない）。
    static let defaultDbAutoCleanupEnabled: Bool = false
    /// S6-004: DB 自動消去のしきい値（GB）。1.0 GB = 1,073,741,824 bytes。
    static let defaultDbAutoCleanupThresholdGB: Double = 1.0
    /// S6-006: バックグラウンド復帰フラグは既定 false（初回起動・クリーンインストール時は自動再開しない）。
    static let defaultWasTracking: Bool = false

    // MARK: - Stored Properties (observed)

    /// 記録モード。書き込み時に UserDefaults に同期する。
    var recordingMode: RecordingMode {
        didSet {
            guard recordingMode != oldValue else { return }
            defaults.set(recordingMode.rawValue, forKey: Keys.recordingMode)
        }
    }

    /// 自宅位置。nil = 未登録。書き込み時に UserDefaults に JSON で同期。
    var homeLocation: HomeLocation? {
        didSet {
            guard homeLocation != oldValue else { return }
            if let homeLocation {
                if let data = try? JSONEncoder().encode(homeLocation) {
                    defaults.set(data, forKey: Keys.homeLocation)
                }
            } else {
                defaults.removeObject(forKey: Keys.homeLocation)
            }
        }
    }

    /// 自宅半径（メートル）。50〜300 の範囲にクランプして保存。
    var homeRadiusMeters: Double {
        didSet {
            let clamped = Self.clampRadius(homeRadiusMeters)
            // 範囲外は自動修正。didSet 内で代入するため、再帰防止のため値が違うときのみ書き戻す。
            if clamped != homeRadiusMeters {
                homeRadiusMeters = clamped
                return
            }
            guard homeRadiusMeters != oldValue else { return }
            defaults.set(homeRadiusMeters, forKey: Keys.homeRadiusMeters)
        }
    }

    /// カレンダー同期 ON/OFF（S4-002）。
    /// true のとき、滞留ピン作成時に CalendarSyncService がイベントを生成する（S4-003）。
    /// 既定は false（jun さんが明示的に ON にしないと書き込まれない）。
    var calendarSyncEnabled: Bool {
        didSet {
            guard calendarSyncEnabled != oldValue else { return }
            defaults.set(calendarSyncEnabled, forKey: Keys.calendarSyncEnabled)
        }
    }

    /// 同期対象カレンダーの `EKCalendar.calendarIdentifier`（S4-002）。
    /// nil = 未選択（同期 ON でも書き込みは行わない）。文字列 = EventKit の不変識別子。
    /// 同期 OFF にしても識別子は破棄せず、ON 時に最後の選択を復元できるよう保持する。
    var calendarIdentifier: String? {
        didSet {
            guard calendarIdentifier != oldValue else { return }
            if let calendarIdentifier {
                defaults.set(calendarIdentifier, forKey: Keys.calendarIdentifier)
            } else {
                defaults.removeObject(forKey: Keys.calendarIdentifier)
            }
        }
    }

    /// クラウド保存先の選択（S5-001 / S5-003）。
    /// nil = 未選択（自動同期 ON でも CloudUploadCoordinator は no-op）。
    /// `googleDrive` / `dropbox` の rawValue を UserDefaults に文字列で保存する。
    var cloudProviderKind: CloudProviderKind? {
        didSet {
            guard cloudProviderKind != oldValue else { return }
            if let cloudProviderKind {
                defaults.set(cloudProviderKind.rawValue, forKey: Keys.cloudProviderKind)
            } else {
                defaults.removeObject(forKey: Keys.cloudProviderKind)
            }
        }
    }

    /// クラウド自動同期 ON/OFF（S5-004）。
    /// true のとき、記録停止時に CloudUploadCoordinator が CSV をアップロードする（S5-005）。
    /// 既定は false（jun さんが明示的に ON にしないと動かない）。
    var cloudAutoSyncEnabled: Bool {
        didSet {
            guard cloudAutoSyncEnabled != oldValue else { return }
            defaults.set(cloudAutoSyncEnabled, forKey: Keys.cloudAutoSyncEnabled)
        }
    }

    /// DB 自動消去 ON/OFF（S6-004）。
    /// true のとき、記録停止時に DatabaseAutoCleanupService が容量をチェックし
    /// しきい値超過で古い TripRecord から削除する。
    /// 既定は false（誤削除防止のため jun さんが明示的に ON にしないと動かない）。
    var dbAutoCleanupEnabled: Bool {
        didSet {
            guard dbAutoCleanupEnabled != oldValue else { return }
            defaults.set(dbAutoCleanupEnabled, forKey: Keys.dbAutoCleanupEnabled)
        }
    }

    /// バックグラウンド復帰用フラグ（S6-006）。
    ///
    /// `startUpdatingLocation` 時に true、`stopUpdatingLocation` 時に false を書き込む。
    /// アプリが OS により kill された後、SLC で起床した際に `resumeTrackingAfterRelaunch()`
    /// がこのフラグを見て記録を再開すべきか判定する。
    /// 既定は false（意図的な記録なし状態から起動した場合、自動再開しない）。
    var wasTracking: Bool {
        didSet {
            guard wasTracking != oldValue else { return }
            defaults.set(wasTracking, forKey: Keys.wasTracking)
        }
    }

    /// DB 自動消去のしきい値（GB）（S6-004）。
    /// この値を超えたとき、古い日付の TripRecord から削除を行う。
    /// 既定は 1.0 GB。0.1 未満は 0.1 にフォールバックして保存する。
    var dbAutoCleanupThresholdGB: Double {
        didSet {
            let clamped = max(dbAutoCleanupThresholdGB, 0.1)
            if clamped != dbAutoCleanupThresholdGB {
                dbAutoCleanupThresholdGB = clamped
                return
            }
            guard dbAutoCleanupThresholdGB != oldValue else { return }
            defaults.set(dbAutoCleanupThresholdGB, forKey: Keys.dbAutoCleanupThresholdGB)
        }
    }

    // MARK: - Dependencies

    /// 注入された UserDefaults。本番では `.standard`、テストでは独立スイート。
    private let defaults: UserDefaults

    // MARK: - Init

    /// 本番用イニシャライザ（UserDefaults.standard）。
    convenience init() {
        self.init(defaults: .standard)
    }

    /// DI 用イニシャライザ。テスト時は `UserDefaults(suiteName:)` で独立した defaults を渡す。
    init(defaults: UserDefaults) {
        self.defaults = defaults

        // 読み込み: 不正データはデフォルト値にフォールバック。
        if let raw = defaults.string(forKey: Keys.recordingMode),
           let mode = RecordingMode(rawValue: raw) {
            self.recordingMode = mode
        } else {
            self.recordingMode = Self.defaultRecordingMode
        }

        if let data = defaults.data(forKey: Keys.homeLocation),
           let decoded = try? JSONDecoder().decode(HomeLocation.self, from: data) {
            self.homeLocation = decoded
        } else {
            self.homeLocation = nil
        }

        let storedRadius = defaults.object(forKey: Keys.homeRadiusMeters) as? Double
        let radius = storedRadius ?? Self.defaultHomeRadiusMeters
        self.homeRadiusMeters = Self.clampRadius(radius)

        // S4-002: カレンダー同期設定。
        // 値が未設定（object(forKey:) が nil）のときはデフォルト false に倒す。
        // bool(forKey:) は未設定時に false を返すため Bool 単体では区別できないが、
        // 既定が false のため同等扱いで問題ない。
        if defaults.object(forKey: Keys.calendarSyncEnabled) != nil {
            self.calendarSyncEnabled = defaults.bool(forKey: Keys.calendarSyncEnabled)
        } else {
            self.calendarSyncEnabled = Self.defaultCalendarSyncEnabled
        }
        self.calendarIdentifier = defaults.string(forKey: Keys.calendarIdentifier)

        // S5-001 / S5-003 / S5-004: クラウド保存先 / 自動同期。
        // 不正な rawValue（CloudProviderKind に存在しない文字列）はデフォルト nil に倒す。
        if let raw = defaults.string(forKey: Keys.cloudProviderKind),
           let kind = CloudProviderKind(rawValue: raw) {
            self.cloudProviderKind = kind
        } else {
            self.cloudProviderKind = nil
        }
        if defaults.object(forKey: Keys.cloudAutoSyncEnabled) != nil {
            self.cloudAutoSyncEnabled = defaults.bool(forKey: Keys.cloudAutoSyncEnabled)
        } else {
            self.cloudAutoSyncEnabled = Self.defaultCloudAutoSyncEnabled
        }

        // S6-004: DB 自動消去 ON/OFF / しきい値。
        // 既定 false（誤削除防止のため明示的に ON にしないと動かない）。
        if defaults.object(forKey: Keys.dbAutoCleanupEnabled) != nil {
            self.dbAutoCleanupEnabled = defaults.bool(forKey: Keys.dbAutoCleanupEnabled)
        } else {
            self.dbAutoCleanupEnabled = Self.defaultDbAutoCleanupEnabled
        }
        let storedThreshold = defaults.object(forKey: Keys.dbAutoCleanupThresholdGB) as? Double
        self.dbAutoCleanupThresholdGB = storedThreshold ?? Self.defaultDbAutoCleanupThresholdGB

        // S6-006: バックグラウンド復帰フラグ。
        // 未設定時（クリーンインストール直後）は false（自動再開しない）。
        // bool(forKey:) は未設定時に false を返すため、ここでは object(forKey:) で未設定判定不要
        // （既定値も false のため同等）。
        self.wasTracking = defaults.bool(forKey: Keys.wasTracking)
    }

    // MARK: - Helpers

    /// 半径値を許容範囲（50〜300）にクランプする。
    static func clampRadius(_ value: Double) -> Double {
        min(max(value, homeRadiusMinMeters), homeRadiusMaxMeters)
    }
}
