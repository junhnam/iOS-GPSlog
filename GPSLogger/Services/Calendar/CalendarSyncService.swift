import Foundation
import EventKit
import CoreLocation
import os

/// CalendarSyncService が扱うエラー（S4-002 / S4-003）。
///
/// `Sendable` で値型として伝搬するため、Result の Failure 側に詰めて呼び出し側に返す。
/// 呼び出し側はこの enum を見てログ・UI への通知（S4-004 のトースト等）を行う。
enum CalendarSyncError: Error, Equatable, Sendable {
    /// ユーザーがカレンダーへのフルアクセスを拒否している、もしくは未決定。
    case permissionDenied
    /// `AppSettings.calendarIdentifier` が未設定、または無効な識別子で
    /// EventKit から該当 EKCalendar が引けない。
    case calendarNotFound
    /// EventKit へのイベント保存（commit）に失敗。
    case saveFailed(message: String)
    /// AppSettings.calendarSyncEnabled が false のため同期をスキップ。
    /// エラーというより通知扱いだが、Result 経由で呼び出し側に伝えるため Error として表現する。
    case disabled

    static func == (lhs: CalendarSyncError, rhs: CalendarSyncError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied, .permissionDenied): return true
        case (.calendarNotFound, .calendarNotFound): return true
        case (.disabled, .disabled): return true
        case (.saveFailed(let l), .saveFailed(let r)): return l == r
        default: return false
        }
    }
}

/// `CalendarProviderProtocol.saveEvent` に渡すイベント情報（S4-003）。
///
/// EKEvent を直接プロトコルに載せるとテストで生成が難しいため、
/// 必要最小限のフィールドを値型として切り出してプロトコル境界に置く。
struct CalendarEventDraft: Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let latitude: Double
    let longitude: Double
    let calendarIdentifier: String
}

/// EventKit (`EKEventStore`) 操作の最小限のインタフェース（S4-002 / S4-003）。
///
/// テストで EventKit をモック化するための seam。本番実装は `EKEventStoreCalendarProvider`
/// が `EKEventStore` をそのまま包む。
///
/// `Sendable` 制約: テスト用フェイクは値型 (`struct`) または `Sendable` 準拠の参照型に
/// する想定。本番の `EKEventStoreCalendarProvider` は `EKEventStore` を保持する class だが、
/// `@MainActor` 隔離の `CalendarSyncService` 内部からのみ触るため `unchecked Sendable` で
/// 包む。
protocol CalendarProviderProtocol: Sendable {
    /// EventKit のフルアクセス権限が既に付与されているか。
    var isFullAccessAuthorized: Bool { get }

    /// フルアクセスを要求する。許可で true、拒否（含む未決定）で false。
    /// throw しない（ユーザーの選択を「失敗」とは扱わない方針）。
    func requestFullAccessIfNeeded() async -> Bool

    /// 書き込み可能な `.event` タイプの EKCalendar を返す。
    func availableEventCalendars() -> [EKCalendar]

    /// 指定識別子の EKCalendar が存在するか確認する（S4-003）。
    /// プロトコル境界では EKCalendar を返さず、Bool で十分（イベント保存は
    /// `saveEvent(_:)` 側で識別子から再解決する）。
    func calendarExists(identifier: String) -> Bool

    /// CalendarEventDraft を EventKit に保存し、作成された EKEvent.eventIdentifier を返す（S4-003）。
    /// - 成功時: EKEvent.eventIdentifier
    /// - calendarIdentifier に該当する EKCalendar が無い場合: nil
    /// - その他の保存エラー: throw
    func saveEvent(_ draft: CalendarEventDraft) throws -> String?
}

/// `EKEventStore` を `CalendarProviderProtocol` として包む本番実装（S4-002）。
///
/// アプリ全体で 1 インスタンスを推奨（EventKit の推奨）。`@MainActor` 上で生成・利用される
/// `CalendarSyncService` の内部からのみ触るため、保持している `EKEventStore` を
/// `Sendable` 不適合のまま使ってよい（`@unchecked Sendable` で抑止）。
final class EKEventStoreCalendarProvider: CalendarProviderProtocol, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var isFullAccessAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestFullAccessIfNeeded() async -> Bool {
        if isFullAccessAuthorized { return true }
        do {
            // iOS 17+ で `requestFullAccessToEvents()` が推奨。
            // 旧 `requestAccess(to: .event)` は deprecated（ios26-api-changes.md 参照）。
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func availableEventCalendars() -> [EKCalendar] {
        // .event タイプかつ書き込み可能（allowsContentModifications）な EKCalendar のみ返す。
        eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    func calendarExists(identifier: String) -> Bool {
        eventStore.calendar(withIdentifier: identifier) != nil
    }

    func saveEvent(_ draft: CalendarEventDraft) throws -> String? {
        guard let calendar = eventStore.calendar(withIdentifier: draft.calendarIdentifier) else {
            return nil
        }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        if let location = draft.location {
            event.location = location
        }
        // Apple 推奨: 構造化された位置情報（緯度経度）も付与する。
        let structured = EKStructuredLocation(title: draft.location ?? draft.title)
        structured.geoLocation = CLLocation(latitude: draft.latitude,
                                            longitude: draft.longitude)
        event.structuredLocation = structured

        // span: .thisEvent はシリーズではなく単一イベントのみ保存。commit: true で永続化。
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
}

/// EventKit へのカレンダーイベント書き込みを担当するサービス（S4-002 / S4-003）。
///
/// 役割:
///   - 権限の取得（`requestFullAccessIfNeeded`）
///   - 利用可能なカレンダー一覧の取得（設定 UI で利用、S4-004）
///   - 滞留ピン → カレンダーイベント自動作成（`createEvent(for:)`、S4-003）
///
/// 設計判断:
///   - `@MainActor` クラスで EventKit を扱う（受け入れ条件 S4-002）
///   - `CalendarProviderProtocol` を介してテスト容易性を確保
///   - エラーは `Result<String, CalendarSyncError>` で返し、UI を停止しない
@MainActor
final class CalendarSyncService {
    private let provider: any CalendarProviderProtocol
    private let appSettings: AppSettings

    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "CalendarSyncService")

    init(provider: any CalendarProviderProtocol = EKEventStoreCalendarProvider(),
         appSettings: AppSettings) {
        self.provider = provider
        self.appSettings = appSettings
    }

    // MARK: - Permission

    /// フルアクセス権限を要求する。
    /// 既に許可されていれば即 true。未決定なら system dialog を表示し、選択結果を返す。
    /// 拒否でも throw せず false を返す（受け入れ条件 S4-002）。
    func requestFullAccessIfNeeded() async -> Bool {
        return await provider.requestFullAccessIfNeeded()
    }

    // MARK: - Calendar list

    /// 利用可能な書き込み可能 `.event` カレンダーを返す（受け入れ条件 S4-002）。
    /// 権限が無い場合は空配列を返す（EventKit の挙動に従う）。
    func availableCalendars() -> [EKCalendar] {
        return provider.availableEventCalendars()
    }

    // MARK: - Event creation (S4-003)

    /// 滞留ピンに対応するカレンダーイベントを作成する（S4-003）。
    ///
    /// 受け入れ条件:
    /// - `AppSettings.calendarSyncEnabled` が false なら no-op で `.disabled` を返す
    /// - 権限が無い場合 `.permissionDenied`
    /// - `AppSettings.calendarIdentifier` が無効・未設定なら `.calendarNotFound`
    /// - 既に作成済（pin.calendarEventIdentifier != nil）なら再作成せず既存 ID を返す
    /// - イベントタイトル: placeName → address → "滞留地点 (緯度.., 経度..)" の順でフォールバック
    /// - 開始 / 終了時刻: pin.stayedFrom / pin.stayedFrom + stayedDurationSeconds
    /// - 場所: placeName または address
    /// - 構造化位置: 緯度経度を EKStructuredLocation に詰める
    /// - 成功時に EKEvent.eventIdentifier を pin.calendarEventIdentifier に書き戻す
    @discardableResult
    func createEvent(for pin: PinRecord) async -> Result<String, CalendarSyncError> {
        // 1. 同期 OFF
        guard appSettings.calendarSyncEnabled else {
            return .failure(.disabled)
        }
        // 2. 重複防止（受け入れ条件: 2 回目以降は再作成しない）
        if let existing = pin.calendarEventIdentifier {
            return .success(existing)
        }
        // 3. 権限確認
        let granted = await provider.requestFullAccessIfNeeded()
        guard granted else {
            return .failure(.permissionDenied)
        }
        // 4. カレンダー識別子確認
        guard let calendarId = appSettings.calendarIdentifier,
              !calendarId.isEmpty,
              provider.calendarExists(identifier: calendarId) else {
            return .failure(.calendarNotFound)
        }
        // 5. イベント情報を組み立て
        // S5-007: 3 段フォールバック「placeName → address → 座標」を素直に表現する。
        //   - title:    placeName → 座標フォールバック（Self.eventTitle）
        //   - location: placeName → address → nil（座標は EKStructuredLocation で別途付与）
        let title = Self.eventTitle(for: pin)
        let location = pin.placeName ?? pin.address
        let startDate = pin.stayedFrom
        let endDate = pin.stayedFrom.addingTimeInterval(max(pin.stayedDurationSeconds, 60))
        let draft = CalendarEventDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            latitude: pin.latitude,
            longitude: pin.longitude,
            calendarIdentifier: calendarId
        )
        // 6. 保存
        do {
            guard let identifier = try provider.saveEvent(draft) else {
                return .failure(.calendarNotFound)
            }
            // 7. 重複防止のため pin に書き戻す
            pin.calendarEventIdentifier = identifier
            return .success(identifier)
        } catch {
            Self.logger.warning("カレンダーイベント保存失敗: \(error.localizedDescription)")
            return .failure(.saveFailed(message: error.localizedDescription))
        }
    }

    /// イベントタイトルの組み立て（S4-003 受け入れ条件）。
    /// placeName → 「滞留地点 (緯度.., 経度..)」の順。
    /// 仕様メモ: S4-003 当初設計では title も「placeName → address → 座標」の 3 段だが、
    /// EKEvent では `title` と `location` が分離しているため、location 側で
    /// placeName → address の 2 段フォールバックを実施し、title は placeName と座標の
    /// 2 段に留める。これにより address のみのピンはタイトルが座標、location が住所文字列となり、
    /// カレンダー一覧での識別性を損なわない。
    private static func eventTitle(for pin: PinRecord) -> String {
        if let name = pin.placeName, !name.isEmpty {
            return name
        }
        // 座標フォールバック。小数点 5 桁（約 1m 精度）で表示。
        return String(format: "滞留地点 (%.5f, %.5f)", pin.latitude, pin.longitude)
    }
}
