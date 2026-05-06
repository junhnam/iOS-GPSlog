import XCTest
@testable import GPSLogger

/// S3-002 のユニットテスト: 自宅登録ロジック（HomeLocation の保存・住所欠落許容・半径境界）。
///
/// HomeRegistrationView 自体は UI なのでここでは直接テストせず、
/// 受け入れ条件「逆ジオコーディング失敗時に住所が空でも保存可能」「半径の境界値（50/300）」
/// を AppSettings + HomeLocation のロジックで担保する。
@MainActor
final class HomeRegistrationTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HomeRegistrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    /// 受け入れ条件: 逆ジオコーディング失敗時に住所が空（nil）でも保存可能。
    func test_homeLocation_canBeSaved_withoutAddress() throws {
        let settings = AppSettings(defaults: defaults)
        let home = HomeLocation(latitude: 35.6812,
                                longitude: 139.7671,
                                address: nil,
                                registeredAt: Date(timeIntervalSince1970: 1_700_000_000))
        settings.homeLocation = home

        // 別インスタンスで再読込しても住所 nil で残る
        let reloaded = AppSettings(defaults: defaults)
        let restored = try XCTUnwrap(reloaded.homeLocation)
        XCTAssertEqual(restored.latitude, 35.6812, accuracy: 0.0001)
        XCTAssertEqual(restored.longitude, 139.7671, accuracy: 0.0001)
        XCTAssertNil(restored.address)
    }

    /// 受け入れ条件: 半径の境界値（50m / 300m）。
    func test_homeRadiusBoundaries_areAccepted() {
        let settings = AppSettings(defaults: defaults)

        settings.homeRadiusMeters = AppSettings.homeRadiusMinMeters // 50
        XCTAssertEqual(settings.homeRadiusMeters, 50)

        settings.homeRadiusMeters = AppSettings.homeRadiusMaxMeters // 300
        XCTAssertEqual(settings.homeRadiusMeters, 300)

        // 境界外は自動でクランプされる
        settings.homeRadiusMeters = 49
        XCTAssertEqual(settings.homeRadiusMeters, 50)
        settings.homeRadiusMeters = 301
        XCTAssertEqual(settings.homeRadiusMeters, 300)
    }

    /// HomeLocation の Codable 往復で全フィールドが復元できる。
    func test_homeLocation_codableRoundTrip() throws {
        let original = HomeLocation(latitude: 35.6812,
                                    longitude: 139.7671,
                                    address: "東京都千代田区",
                                    registeredAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeLocation.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
