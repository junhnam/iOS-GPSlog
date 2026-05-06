import XCTest
import EventKit
@testable import GPSLogger

/// S4-004 受け入れ条件:
///   (a) Toggle ON で AppSettings.calendarSyncEnabled が true になり、永続化される
///   (b) 権限拒否で Toggle が OFF に戻る
///   (c) calendarIdentifier の選択で AppSettings に永続化される
///   (d) AppSettings の calendarSyncEnabled / calendarIdentifier が UserDefaults に
///       書き戻されることの単体検証（既存 8 ケースに 1 ケース追加）
@MainActor
final class CalendarSyncSettingsTests: XCTestCase {

    // MARK: - Helpers

    private func makeIsolatedSettings() -> (AppSettings, UserDefaults) {
        let suiteName = "gpslogger.tests.calsync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppSettings(defaults: defaults), defaults)
    }

    /// S4-004 単体テスト用: CalendarProviderProtocol のフェイク実装。
    /// 権限の許可/拒否、利用可能カレンダー一覧、識別子の存在確認、saveEvent 結果を制御できる。
    private final class FakeCalendarProvider: CalendarProviderProtocol, @unchecked Sendable {
        var isFullAccessAuthorized: Bool = false
        var willGrantPermission: Bool = false
        var availableEventCalendarsResult: [EKCalendar] = []
        var existingCalendarIdentifiers: Set<String> = []
        var saveEventResult: String? = "fake-event-id"
        var saveEventError: Error?

        func requestFullAccessIfNeeded() async -> Bool {
            isFullAccessAuthorized = willGrantPermission
            return willGrantPermission
        }

        func availableEventCalendars() -> [EKCalendar] {
            availableEventCalendarsResult
        }

        func calendarExists(identifier: String) -> Bool {
            existingCalendarIdentifiers.contains(identifier)
        }

        func saveEvent(_ draft: CalendarEventDraft) throws -> String? {
            if let error = saveEventError { throw error }
            return saveEventResult
        }
    }

    // MARK: - (a) Toggle ON で AppSettings.calendarSyncEnabled が true になる

    func test_calendarSyncEnabled_setTrue_persistsToUserDefaults() {
        let (settings, defaults) = makeIsolatedSettings()
        XCTAssertFalse(settings.calendarSyncEnabled, "既定は OFF")

        settings.calendarSyncEnabled = true

        XCTAssertTrue(settings.calendarSyncEnabled)
        XCTAssertTrue(defaults.bool(forKey: AppSettings.Keys.calendarSyncEnabled),
                      "UserDefaults に true として永続化される")
    }

    // MARK: - (b) 権限拒否で Toggle が OFF に戻る

    func test_calendarPermissionDenied_revertsToggleToOff() async {
        let (settings, _) = makeIsolatedSettings()
        let provider = FakeCalendarProvider()
        provider.willGrantPermission = false
        let service = CalendarSyncService(provider: provider, appSettings: settings)

        // SettingsView.handleCalendarSyncToggle 相当のロジックを再現する。
        // CalendarSyncService.requestFullAccessIfNeeded() が false を返したら
        // settings.calendarSyncEnabled を false に戻す挙動を検証。
        settings.calendarSyncEnabled = true
        let granted = await service.requestFullAccessIfNeeded()
        if !granted {
            settings.calendarSyncEnabled = false
        }

        XCTAssertFalse(granted, "権限要求が拒否される")
        XCTAssertFalse(settings.calendarSyncEnabled,
                       "拒否時は Toggle が OFF に戻る")
    }

    // MARK: - (c) calendarIdentifier の永続化

    func test_calendarIdentifier_setValue_persistsToUserDefaults() {
        let (settings, defaults) = makeIsolatedSettings()
        XCTAssertNil(settings.calendarIdentifier, "既定は未選択")

        settings.calendarIdentifier = "calendar-id-abc"

        XCTAssertEqual(settings.calendarIdentifier, "calendar-id-abc")
        XCTAssertEqual(defaults.string(forKey: AppSettings.Keys.calendarIdentifier),
                       "calendar-id-abc",
                       "UserDefaults に文字列として永続化される")

        // nil に戻すと UserDefaults からも削除される
        settings.calendarIdentifier = nil
        XCTAssertNil(settings.calendarIdentifier)
        XCTAssertNil(defaults.string(forKey: AppSettings.Keys.calendarIdentifier),
                     "nil 代入で UserDefaults からも消える")
    }

    // MARK: - (d) 既存 AppSettings 永続化（後方互換）と複合テスト

    func test_appSettings_recreate_restoresCalendarSyncFields() {
        let (firstSettings, defaults) = makeIsolatedSettings()
        firstSettings.calendarSyncEnabled = true
        firstSettings.calendarIdentifier = "calendar-id-xyz"

        // 同じ UserDefaults から AppSettings を再生成すると値が復元される
        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.calendarSyncEnabled)
        XCTAssertEqual(restored.calendarIdentifier, "calendar-id-xyz")
    }

    // MARK: - (e) 権限許可時は Toggle が ON のまま

    func test_calendarPermissionGranted_keepsToggleOn() async {
        let (settings, _) = makeIsolatedSettings()
        let provider = FakeCalendarProvider()
        provider.willGrantPermission = true
        let service = CalendarSyncService(provider: provider, appSettings: settings)

        settings.calendarSyncEnabled = true
        let granted = await service.requestFullAccessIfNeeded()
        if !granted {
            settings.calendarSyncEnabled = false
        }

        XCTAssertTrue(granted, "権限許可時は true が返る")
        XCTAssertTrue(settings.calendarSyncEnabled,
                      "許可時は Toggle が ON のまま")
    }

    // MARK: - (f) availableCalendars が空でもクラッシュしない

    func test_calendarService_availableCalendars_emptyReturnsEmpty() {
        let (settings, _) = makeIsolatedSettings()
        let provider = FakeCalendarProvider()
        provider.availableEventCalendarsResult = []
        let service = CalendarSyncService(provider: provider, appSettings: settings)

        let calendars = service.availableCalendars()
        XCTAssertTrue(calendars.isEmpty, "権限なし or 空時は空配列")
    }
}
