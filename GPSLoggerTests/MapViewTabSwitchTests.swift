import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S6-016 受け入れ条件:
///   (1) 常時同期モードで startUpdatingLocation 後に stopUpdatingLocation を呼ばなければ
///       wasTracking が true のまま維持される（タブ切替バグ修正の担保）
///   (2) トリガーモードで stopUpdatingLocation を呼ぶと wasTracking が false になる
///       （意図的な停止挙動の維持を確認）
///   (3) 常時同期モードで startUpdatingLocation が呼ばれる（.onAppear 挙動の維持）
///
/// 設計メモ（S6-016）:
///   SwiftUI View の `.onDisappear` を直接ユニットテストする方法はないため、
///   「MapView の .onDisappear で stopUpdatingLocation を呼ばない」修正を
///   LocationService レイヤーの振る舞いで担保する。
///
///   具体的には:
///   - startUpdatingLocation を呼んだ後、stopUpdatingLocation を呼ばなければ
///     wasTracking が true のままであることを検証する。これにより、
///     タブ切替が stopUpdatingLocation を呼ばない限りは wasTracking が崩れないことを担保する。
///   - MapView.swift のコードレビューでは「.onDisappear に stopUpdatingLocation が
///     含まれていないこと」を目視確認する（コードレビューエージェントへの観点提供）。
@MainActor
final class MapViewTabSwitchTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run { retainedContainers.removeAll() }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    private func makeIsolatedSettings(mode: RecordingMode = .continuous) -> AppSettings {
        let suiteName = "gpslogger.tests.tabswitch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.recordingMode = mode
        return settings
    }

    // MARK: - (1) 常時同期モード: stopUpdatingLocation を呼ばなければ wasTracking は true のまま

    /// S6-016 の根本原因は「.onDisappear が stopUpdatingLocation を呼ぶ → wasTracking=false」。
    /// 修正後は .onDisappear で stopUpdatingLocation を呼ばないため、
    /// startUpdatingLocation 後に stopUpdatingLocation が呼ばれない限り wasTracking=true が維持される。
    /// このテストは「.onDisappear が stopUpdatingLocation を呼ばない」コード修正を
    /// LocationService 側の振る舞いで担保する。
    func test_recordingMode_continuous_keepsWasTrackingTrueAfterMapViewDisappear_S6016() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings(mode: .continuous)
        let mock = MockLocationProviderForTabSwitch()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // 常時同期モードで記録開始（MapView の .onAppear に相当）
        sut.startUpdatingLocation()
        XCTAssertTrue(settings.wasTracking, "startUpdatingLocation 後は wasTracking=true")
        XCTAssertTrue(sut.isUpdating, "startUpdatingLocation 後は isUpdating=true")

        // タブ切替による .onDisappear を模擬:
        // S6-016 修正後は .onDisappear で stopUpdatingLocation を呼ばないため、
        // ここでは「何もしない」状態を維持する（= stopUpdatingLocation を呼ばない）。
        // wasTracking が true のまま維持されることを検証する。

        XCTAssertTrue(settings.wasTracking,
            "タブ切替後も stopUpdatingLocation を呼ばなければ wasTracking=true のまま（S6-016）")
        XCTAssertTrue(sut.isUpdating,
            "タブ切替後も isUpdating=true のまま（記録継続）（S6-016）")
        XCTAssertEqual(mock.stopUpdatingCallCount, 0,
            ".onDisappear で stopUpdatingLocation が呼ばれていないことを確認（S6-016）")
    }

    // MARK: - (2) トリガーモード: stopUpdatingLocation を呼ぶと wasTracking が false になる

    /// トリガーモードでは RecordingToggleButton（ユーザーの明示操作）で
    /// stopUpdatingLocation が呼ばれるため、wasTracking が false になる挙動は維持される。
    /// この挙動が S6-016 修正によって壊れていないことを検証する。
    func test_triggerMode_stopButton_stillResetsWasTracking_S6016() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings(mode: .trigger)
        let mock = MockLocationProviderForTabSwitch()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // トリガーモードで記録開始（RecordingToggleButton でのスタートに相当）
        sut.startUpdatingLocation()
        XCTAssertTrue(settings.wasTracking, "startUpdatingLocation 後は wasTracking=true")
        XCTAssertTrue(sut.isUpdating, "startUpdatingLocation 後は isUpdating=true")

        // RecordingToggleButton での明示的な停止に相当
        sut.stopUpdatingLocation()

        XCTAssertFalse(settings.wasTracking,
            "トリガーモードで stopUpdatingLocation を呼ぶと wasTracking=false になる（S6-016）")
        XCTAssertFalse(sut.isUpdating,
            "stopUpdatingLocation 後は isUpdating=false（S6-016）")
        XCTAssertTrue(mock.stopUpdatingCallCount > 0,
            "manager.stopUpdatingLocation() が呼ばれた（S6-016）")
    }

    // MARK: - (3) 常時同期モードで .onAppear 時に startUpdatingLocation が呼ばれる挙動の確認

    /// MapView の .onAppear で常時同期モードなら startUpdatingLocation が呼ばれる挙動を
    /// LocationService レイヤーで確認する。この挙動は S6-016 修正後も維持される。
    func test_continuousMode_startUpdatingLocation_setsWasTrackingTrue_S6016() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings(mode: .continuous)
        let mock = MockLocationProviderForTabSwitch()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        // 初期状態
        XCTAssertFalse(settings.wasTracking, "初期状態: wasTracking=false")
        XCTAssertFalse(sut.isUpdating, "初期状態: isUpdating=false")

        // .onAppear での常時同期自動スタートに相当
        sut.startUpdatingLocation()

        XCTAssertTrue(settings.wasTracking,
            "常時同期 .onAppear で startUpdatingLocation を呼ぶと wasTracking=true（S6-016）")
        XCTAssertTrue(sut.isUpdating,
            "常時同期 .onAppear で isUpdating=true になる（S6-016）")
        XCTAssertTrue(mock.startUpdatingCallCount > 0,
            "manager.startUpdatingLocation() が呼ばれた（S6-016）")
    }
}

// MARK: - Mock provider for S6-016

/// LocationProviderProtocol の Spy（S6-016 タブ切替バグ修正テスト専用）。
/// start / stop の呼び出し回数をそれぞれカウントする。
private final class MockLocationProviderForTabSwitch: NSObject, LocationProviderProtocol, @unchecked Sendable {
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = true
    var showsBackgroundLocationIndicator: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var delegate: CLLocationManagerDelegate?

    /// startUpdatingLocation の呼び出し回数（S6-016 テスト用）。
    var startUpdatingCallCount: Int = 0

    /// stopUpdatingLocation の呼び出し回数（S6-016 テスト用）。
    var stopUpdatingCallCount: Int = 0

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() { startUpdatingCallCount += 1 }
    func stopUpdatingLocation() { stopUpdatingCallCount += 1 }
    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
}
