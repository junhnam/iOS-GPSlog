import XCTest
import EventKit
@testable import GPSLogger

/// S4-002 のユニットテスト: CalendarSyncService の権限取得・カレンダー一覧・AppSettings 永続化。
///
/// EventKit の `EKCalendar` はテストで安全にサブクラス化できない（内部 invariant に依存）ため、
/// `CalendarProviderProtocol` のフェイクで「呼び出された / 値が透過される」だけを検証する設計とする。
@MainActor
final class CalendarSyncServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CalendarSyncServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - (a) 権限許可ケース

    func test_requestFullAccessIfNeeded_returnsTrue_whenAuthorized() async {
        let provider = FakeCalendarProvider(authorized: true, requestResult: true)
        let settings = AppSettings(defaults: defaults)
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let granted = await sut.requestFullAccessIfNeeded()
        XCTAssertTrue(granted, "許可済みなら true が返る")
        XCTAssertEqual(provider.requestCallCount, 1)
    }

    // MARK: - (b) 拒否ケース

    func test_requestFullAccessIfNeeded_returnsFalse_whenDenied() async {
        let provider = FakeCalendarProvider(authorized: false, requestResult: false)
        let settings = AppSettings(defaults: defaults)
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let granted = await sut.requestFullAccessIfNeeded()
        XCTAssertFalse(granted, "拒否なら false が返る（throw しない）")
    }

    // MARK: - (c) カレンダー一覧の透過

    func test_availableCalendars_passesThroughProviderResult() {
        // EKCalendar のサブクラス化は安全に行えないため、
        // 権限なし時に「空配列が返る」プロバイダ応答が透過されることを確認する。
        let providerEmpty = FakeCalendarProvider(authorized: false,
                                                 requestResult: false,
                                                 calendarsEmpty: true)
        let settings = AppSettings(defaults: defaults)
        let sutEmpty = CalendarSyncService(provider: providerEmpty, appSettings: settings)
        XCTAssertEqual(sutEmpty.availableCalendars().count, 0,
                       "プロバイダが空配列を返すなら availableCalendars も空")

        // 受け入れ条件「.event タイプかつ書き込み可能のみ」のフィルタは
        // EKEventStoreCalendarProvider.availableEventCalendars 内の `.filter { $0.allowsContentModifications }` で担保する。
        // ここでは透過契約のみを検証し、本物の EKCalendar 生成は実機 / シミュレータ統合テストで確認する。
    }

    // MARK: - (d) AppSettings に identifier が永続化される

    func test_appSettings_persistsCalendarIdentifier() throws {
        let first = AppSettings(defaults: defaults)
        XCTAssertNil(first.calendarIdentifier, "初期値は nil")
        XCTAssertFalse(first.calendarSyncEnabled, "初期値は false")

        first.calendarIdentifier = "ek-cal-id-123"
        first.calendarSyncEnabled = true

        // 別インスタンスで再読み込みして永続化を確認
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.calendarIdentifier, "ek-cal-id-123")
        XCTAssertTrue(second.calendarSyncEnabled)

        // nil 設定で UserDefaults からキーが消える
        first.calendarIdentifier = nil
        XCTAssertNil(defaults.string(forKey: AppSettings.Keys.calendarIdentifier))
    }

    // MARK: - 後方互換: 既存設定値の読み書きが calendar* 追加で破綻していないこと

    func test_appSettings_calendarSyncEnabled_defaultsToFalse_whenStorageEmpty() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.calendarSyncEnabled)
        XCTAssertNil(settings.calendarIdentifier)
    }

    func test_appSettings_calendarSyncEnabled_doesNotAffectExistingProperties() {
        let settings = AppSettings(defaults: defaults)
        // calendar 系を変更しても既存プロパティは影響を受けない
        settings.calendarSyncEnabled = true
        settings.calendarIdentifier = "id"

        XCTAssertEqual(settings.recordingMode, AppSettings.defaultRecordingMode)
        XCTAssertNil(settings.homeLocation)
        XCTAssertEqual(settings.homeRadiusMeters, AppSettings.defaultHomeRadiusMeters)
    }
}

// MARK: - Test Doubles

/// CalendarProviderProtocol のフェイク実装（テスト専用）。
/// EventKit の生 API は呼ばず、in-memory に持った状態で振る舞いを返す。
private final class FakeCalendarProvider: CalendarProviderProtocol, @unchecked Sendable {
    private let authorized: Bool
    private let requestResult: Bool
    private let calendarsEmpty: Bool
    private(set) var requestCallCount: Int = 0

    init(authorized: Bool,
         requestResult: Bool,
         calendarsEmpty: Bool = true) {
        self.authorized = authorized
        self.requestResult = requestResult
        self.calendarsEmpty = calendarsEmpty
    }

    var isFullAccessAuthorized: Bool { authorized }

    func requestFullAccessIfNeeded() async -> Bool {
        requestCallCount += 1
        return requestResult
    }

    func availableEventCalendars() -> [EKCalendar] {
        // EKCalendar のテスト用インスタンスを安全に生成できないため、
        // フェイクは常に空配列を返す。一覧フィルタの本番ロジックは
        // EKEventStoreCalendarProvider.availableEventCalendars 側に閉じ込め、
        // 実機 / シミュレータでの統合確認に委ねる。
        return []
    }

    func calendar(withIdentifier identifier: String) -> EKCalendar? {
        return nil
    }

    func save(_ event: EKEvent) throws {
        // S4-002 のテストでは保存処理は呼ばないため no-op。
        // 保存パスのテストは S4-003 で別途実装する。
    }
}
