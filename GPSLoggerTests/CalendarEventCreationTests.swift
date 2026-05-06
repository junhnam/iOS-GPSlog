import XCTest
import EventKit
@testable import GPSLogger

/// S4-003 のユニットテスト: 滞留ピン → カレンダーイベント自動作成。
///
/// 5 ケース:
///   (a) placeName ありで作成成功
///   (b) placeName なし → 座標 fallback でタイトル生成
///   (c) 同期 OFF で no-op (.disabled)
///   (d) 重複呼び出しで 2 回作成されない
///   (e) 権限拒否で .permissionDenied を返す
///
/// EKEvent / EKEventStore はテスト容易な代物ではないため、`CalendarProviderProtocol`
/// のフェイクを差し込み、保存呼び出しの引数（CalendarEventDraft）を検証する。
@MainActor
final class CalendarEventCreationTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CalendarEventCreationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func makeSettings(syncEnabled: Bool, calendarId: String?) -> AppSettings {
        let settings = AppSettings(defaults: defaults)
        settings.calendarSyncEnabled = syncEnabled
        settings.calendarIdentifier = calendarId
        return settings
    }

    // MARK: - (a) placeName ありで作成成功

    func test_createEvent_succeeds_withPlaceName() async {
        let settings = makeSettings(syncEnabled: true, calendarId: "cal-1")
        let provider = StubCalendarProvider(
            authorized: true,
            requestResult: true,
            existingCalendarIds: ["cal-1"],
            saveResult: .success("event-id-001")
        )
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let pin = PinRecord(latitude: 35.658,
                            longitude: 139.701,
                            stayedFrom: Date(timeIntervalSince1970: 1_700_000_000),
                            stayedDurationSeconds: 720,
                            placeName: "スターバックス渋谷店")
        let result = await sut.createEvent(for: pin)

        switch result {
        case .success(let id):
            XCTAssertEqual(id, "event-id-001")
            XCTAssertEqual(pin.calendarEventIdentifier, "event-id-001",
                           "成功時に PinRecord に identifier が書き戻される")
        case .failure(let err):
            XCTFail("予想外の失敗: \(err)")
        }

        XCTAssertEqual(provider.savedDrafts.count, 1)
        let draft = provider.savedDrafts.first!
        XCTAssertEqual(draft.title, "スターバックス渋谷店")
        XCTAssertEqual(draft.calendarIdentifier, "cal-1")
        XCTAssertEqual(draft.startDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(draft.endDate.timeIntervalSince1970,
                       1_700_000_720, accuracy: 0.5,
                       "endDate は stayedFrom + stayedDurationSeconds")
        XCTAssertEqual(draft.location, "スターバックス渋谷店")
        XCTAssertEqual(draft.latitude, 35.658, accuracy: 0.0001)
        XCTAssertEqual(draft.longitude, 139.701, accuracy: 0.0001)
    }

    // MARK: - (b) placeName なし → 座標 fallback

    func test_createEvent_fallbacksToCoordinateTitle_whenPlaceNameNil() async {
        let settings = makeSettings(syncEnabled: true, calendarId: "cal-1")
        let provider = StubCalendarProvider(
            authorized: true,
            requestResult: true,
            existingCalendarIds: ["cal-1"],
            saveResult: .success("event-id-002")
        )
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let pin = PinRecord(latitude: 35.6812,
                            longitude: 139.7671,
                            stayedFrom: Date(timeIntervalSince1970: 1_700_000_000),
                            stayedDurationSeconds: 600,
                            placeName: nil)
        let result = await sut.createEvent(for: pin)

        XCTAssertNoThrow({
            if case .failure(let err) = result {
                XCTFail("失敗: \(err)")
            }
        }())

        XCTAssertEqual(provider.savedDrafts.count, 1)
        let title = provider.savedDrafts.first?.title ?? ""
        XCTAssertTrue(title.hasPrefix("滞留地点 ("),
                      "placeName なしの場合は座標フォールバックでタイトル生成: actual=\(title)")
        XCTAssertTrue(title.contains("35.68120"))
        XCTAssertTrue(title.contains("139.76710"))
    }

    // MARK: - (c) 同期 OFF で no-op

    func test_createEvent_returnsDisabled_whenSyncOff() async {
        let settings = makeSettings(syncEnabled: false, calendarId: "cal-1")
        let provider = StubCalendarProvider(
            authorized: true,
            requestResult: true,
            existingCalendarIds: ["cal-1"],
            saveResult: .success("ignored")
        )
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let pin = PinRecord(latitude: 35.658, longitude: 139.701,
                            stayedFrom: Date(), stayedDurationSeconds: 600,
                            placeName: "Test")
        let result = await sut.createEvent(for: pin)

        if case .failure(let err) = result {
            XCTAssertEqual(err, .disabled)
        } else {
            XCTFail("同期 OFF なら .disabled を期待")
        }
        XCTAssertEqual(provider.savedDrafts.count, 0, "同期 OFF なら保存呼び出しは発生しない")
        XCTAssertNil(pin.calendarEventIdentifier, "OFF なら PinRecord に書き戻されない")
    }

    // MARK: - (d) 重複呼び出しで 2 回作成されない

    func test_createEvent_doesNotCreateTwice_whenAlreadyHasIdentifier() async {
        let settings = makeSettings(syncEnabled: true, calendarId: "cal-1")
        let provider = StubCalendarProvider(
            authorized: true,
            requestResult: true,
            existingCalendarIds: ["cal-1"],
            saveResult: .success("new-id")
        )
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let pin = PinRecord(latitude: 35.658, longitude: 139.701,
                            stayedFrom: Date(), stayedDurationSeconds: 600,
                            placeName: "Test",
                            calendarEventIdentifier: "existing-id-999")
        let result = await sut.createEvent(for: pin)

        if case .success(let id) = result {
            XCTAssertEqual(id, "existing-id-999",
                           "既存 ID をそのまま返す（再作成しない）")
        } else {
            XCTFail("重複呼び出しでは既存 ID を返すはず")
        }
        XCTAssertEqual(provider.savedDrafts.count, 0,
                       "重複呼び出しでは saveEvent が呼ばれない")
    }

    // MARK: - (e) 権限拒否で .permissionDenied

    func test_createEvent_returnsPermissionDenied_whenAccessDenied() async {
        let settings = makeSettings(syncEnabled: true, calendarId: "cal-1")
        let provider = StubCalendarProvider(
            authorized: false,
            requestResult: false,
            existingCalendarIds: ["cal-1"],
            saveResult: .success("ignored")
        )
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let pin = PinRecord(latitude: 35.658, longitude: 139.701,
                            stayedFrom: Date(), stayedDurationSeconds: 600,
                            placeName: "Test")
        let result = await sut.createEvent(for: pin)

        if case .failure(let err) = result {
            XCTAssertEqual(err, .permissionDenied)
        } else {
            XCTFail("拒否なら .permissionDenied を期待")
        }
        XCTAssertEqual(provider.savedDrafts.count, 0)
    }

    // MARK: - (f) calendarIdentifier が無効で .calendarNotFound

    func test_createEvent_returnsCalendarNotFound_whenIdInvalid() async {
        let settings = makeSettings(syncEnabled: true, calendarId: "cal-not-exist")
        let provider = StubCalendarProvider(
            authorized: true,
            requestResult: true,
            existingCalendarIds: ["cal-1"], // 別 ID のみ存在
            saveResult: .success("ignored")
        )
        let sut = CalendarSyncService(provider: provider, appSettings: settings)

        let pin = PinRecord(latitude: 35.658, longitude: 139.701,
                            stayedFrom: Date(), stayedDurationSeconds: 600,
                            placeName: "Test")
        let result = await sut.createEvent(for: pin)

        if case .failure(let err) = result {
            XCTAssertEqual(err, .calendarNotFound)
        } else {
            XCTFail("無効な識別子なら .calendarNotFound")
        }
    }
}

// MARK: - Test Doubles

/// CalendarProviderProtocol のスタブ。saveEvent の呼び出し履歴を保持する。
private final class StubCalendarProvider: CalendarProviderProtocol, @unchecked Sendable {
    enum SaveResult {
        case success(String?)
        case failure(Error)
    }

    private let authorized: Bool
    private let requestResult: Bool
    private let existingCalendarIds: Set<String>
    private let saveResult: SaveResult

    private(set) var savedDrafts: [CalendarEventDraft] = []

    init(authorized: Bool,
         requestResult: Bool,
         existingCalendarIds: [String],
         saveResult: SaveResult) {
        self.authorized = authorized
        self.requestResult = requestResult
        self.existingCalendarIds = Set(existingCalendarIds)
        self.saveResult = saveResult
    }

    var isFullAccessAuthorized: Bool { authorized }

    func requestFullAccessIfNeeded() async -> Bool {
        return requestResult
    }

    func availableEventCalendars() -> [EKCalendar] {
        return []
    }

    func calendarExists(identifier: String) -> Bool {
        return existingCalendarIds.contains(identifier)
    }

    func saveEvent(_ draft: CalendarEventDraft) throws -> String? {
        savedDrafts.append(draft)
        switch saveResult {
        case .success(let id): return id
        case .failure(let err): throw err
        }
    }
}
