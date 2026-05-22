import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S6-023 E: MapViewModel のリアルタイムピン描画テスト。
///
/// ## テスト対象
///   - 走行中に新規ピンが生成されたとき、MapViewModel.pins にリアルタイムで追加される
///   - didRestore フラグが立っていても、subscribeToNewPins 経由のランタイム更新は反映される
///   - 重複ピン（同一 stayedFrom）は二重追加されない
///   - LocationService.newPinSubject が appendPin(pin:) を呼び出すことで地図が更新される
@MainActor
final class MapViewRealtimePinRenderingTests: XCTestCase {

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

    private func makeIsolatedSettings() -> AppSettings {
        let suiteName = "gpslogger.tests.realtimepin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(defaults: defaults)
    }

    private func makePinRecord(lat: Double = 35.681236, lon: Double = 139.767125,
                                offset: TimeInterval = 0) -> PinRecord {
        PinRecord(
            latitude: lat,
            longitude: lon,
            stayedFrom: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            stayedDurationSeconds: 660
        )
    }

    // MARK: - E: 走行中に新規ピンが地図に反映される

    /// LocationService.newPinSubject.send() → MapViewModel.pins に即時追加される（S6-023 E）。
    func test_E_newPinPublished_addedToViewModelPins_S6023() async throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProviderForRealtimePin()
        let sut_location = LocationService(manager: mock, repository: repo)
        let sut_map = MapViewModel(repository: repo)

        // MapViewModel が LocationService を購読
        sut_map.subscribeToNewPins(from: sut_location)

        // 初期状態: ピンなし
        XCTAssertEqual(sut_map.pins.count, 0, "初期状態: ピンなし")

        // LocationService から新規ピンを送信
        let pin = makePinRecord(offset: 0)
        sut_location.newPinSubject.send(pin)

        // Combine が DispatchQueue.main を経由するため 1 ループ待つ
        for _ in 0..<20 {
            if sut_map.pins.count > 0 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(sut_map.pins.count, 1,
            "newPinSubject.send() 後に pins に 1 件追加される（S6-023 E）")
        XCTAssertEqual(sut_map.pins.first?.latitude ?? 0, 35.681236, accuracy: 0.0001)
    }

    /// didRestore が true の状態でも subscribeToNewPins 経由の更新は反映される（S6-023 E）。
    func test_E_newPin_addedEvenAfterDidRestore_S6023() async throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProviderForRealtimePin()
        let sut_location = LocationService(manager: mock, repository: repo)
        let sut_map = MapViewModel(repository: repo)

        // restoreTodayTrip を呼んで didRestore=true にする（当日トリップなしでも OK）
        sut_map.restoreTodayTrip()
        XCTAssertTrue(sut_map.didRestore, "restoreTodayTrip 後は didRestore=true")

        // 購読を設定
        sut_map.subscribeToNewPins(from: sut_location)

        // 新規ピンを送信
        let pin = makePinRecord(offset: 100)
        sut_location.newPinSubject.send(pin)

        for _ in 0..<20 {
            if sut_map.pins.count > 0 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(sut_map.pins.count, 1,
            "didRestore=true でもランタイム更新は反映される（S6-023 E）")
    }

    /// 同一 stayedFrom のピンが重複して送信されても二重追加されない（S6-023 E）。
    func test_E_duplicatePin_notAddedTwice_S6023() async throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProviderForRealtimePin()
        let sut_location = LocationService(manager: mock, repository: repo)
        let sut_map = MapViewModel(repository: repo)

        sut_map.subscribeToNewPins(from: sut_location)

        let pin = makePinRecord(offset: 200)
        sut_location.newPinSubject.send(pin)
        sut_location.newPinSubject.send(pin)  // 同じピンを 2 回送信

        for _ in 0..<20 {
            if sut_map.pins.count > 0 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // 少し追加で待って重複が入らないことを確認
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sut_map.pins.count, 1,
            "同一 stayedFrom のピンは重複追加されない（S6-023 E）")
    }

    /// 複数の異なるピンが順番に追加されることを検証（S6-023 E）。
    func test_E_multiplePins_allAdded_S6023() async throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProviderForRealtimePin()
        let sut_location = LocationService(manager: mock, repository: repo)
        let sut_map = MapViewModel(repository: repo)

        sut_map.subscribeToNewPins(from: sut_location)

        let pin1 = makePinRecord(offset: 300)
        let pin2 = makePinRecord(lat: 35.690000, lon: 139.770000, offset: 900)
        sut_location.newPinSubject.send(pin1)
        sut_location.newPinSubject.send(pin2)

        for _ in 0..<30 {
            if sut_map.pins.count >= 2 { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(sut_map.pins.count, 2,
            "異なる 2 件のピンが順番に追加される（S6-023 E）")
    }

    /// subscribeToNewPins 前に送信されたピンは受け取らない（PassthroughSubject の仕様確認）。
    func test_E_pinBeforeSubscription_notReceived_S6023() async throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProviderForRealtimePin()
        let sut_location = LocationService(manager: mock, repository: repo)
        let sut_map = MapViewModel(repository: repo)

        // 購読前にピンを送信
        let pin = makePinRecord(offset: 400)
        sut_location.newPinSubject.send(pin)

        // 購読を設定
        sut_map.subscribeToNewPins(from: sut_location)

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sut_map.pins.count, 0,
            "購読前に送信されたピンは受け取らない（PassthroughSubject）（S6-023 E）")
    }
}

// MARK: - Mock

/// S6-023 E テスト用: 最小限の LocationProviderProtocol 実装。
final class MockLocationProviderForRealtimePin: NSObject, LocationProviderProtocol, @unchecked Sendable {
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10
    var activityType: CLActivityType = .automotiveNavigation
    var pausesLocationUpdatesAutomatically: Bool = false
    var allowsBackgroundLocationUpdates: Bool = true
    var showsBackgroundLocationIndicator: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var delegate: CLLocationManagerDelegate?

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
    func startMonitoringSignificantLocationChanges() {}
    func stopMonitoringSignificantLocationChanges() {}
}
