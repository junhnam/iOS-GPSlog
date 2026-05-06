import Foundation
import EventKit
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

/// EventKit (`EKEventStore`) 操作の最小限のインタフェース（S4-002）。
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

    /// 指定識別子の EKCalendar を返す。見つからなければ nil。
    func calendar(withIdentifier identifier: String) -> EKCalendar?

    /// イベントを保存（commit）する。失敗時は throw。
    func save(_ event: EKEvent) throws
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

    func calendar(withIdentifier identifier: String) -> EKCalendar? {
        eventStore.calendar(withIdentifier: identifier)
    }

    func save(_ event: EKEvent) throws {
        // span: .thisEvent はシリーズではなく単一イベントのみ保存。commit: true で永続化。
        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    /// CalendarSyncService から `EKEvent` を生成するために使う共有 EKEventStore。
    /// テスト時はフェイクプロバイダ側で EKEvent を直接モックするため、本番 path のみ利用。
    var sharedEventStore: EKEventStore { eventStore }
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
}
