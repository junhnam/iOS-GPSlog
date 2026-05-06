import XCTest
@testable import GPSLogger

/// S3-001 のユニットテスト: AppSettings の読み書き・デフォルト・不正データのフォールバック。
///
/// テスト用 UserDefaults はテストごとに独立スイートを作成し、本番設定を汚さない。
@MainActor
final class AppSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AppSettingsTests-\(UUID().uuidString)"
        // makeIfNeeded は不要。空 suite が自動生成される。
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults, "テスト用 UserDefaults スイートを作成できなかった")
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func test_defaults_areApplied_whenStorageIsEmpty() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.recordingMode, .continuous, "デフォルトは常時記録")
        XCTAssertNil(settings.homeLocation, "未登録時は nil")
        XCTAssertEqual(settings.homeRadiusMeters, AppSettings.defaultHomeRadiusMeters)
    }

    // MARK: - Read/Write Round-trip

    func test_writingValues_persistsAndCanBeReReadFromNewInstance() throws {
        let firstInstance = AppSettings(defaults: defaults)
        firstInstance.recordingMode = .trigger
        firstInstance.homeLocation = HomeLocation(latitude: 35.6812,
                                                  longitude: 139.7671,
                                                  address: "東京駅",
                                                  registeredAt: Date(timeIntervalSince1970: 1_700_000_000))
        firstInstance.homeRadiusMeters = 200

        // 別インスタンスで読み直す（永続化往復の検証）
        let secondInstance = AppSettings(defaults: defaults)
        XCTAssertEqual(secondInstance.recordingMode, .trigger)
        let restoredHome = try XCTUnwrap(secondInstance.homeLocation)
        XCTAssertEqual(restoredHome.latitude, 35.6812, accuracy: 0.0001)
        XCTAssertEqual(restoredHome.longitude, 139.7671, accuracy: 0.0001)
        XCTAssertEqual(restoredHome.address, "東京駅")
        XCTAssertEqual(secondInstance.homeRadiusMeters, 200)
    }

    func test_clearingHomeLocation_removesFromUserDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.homeLocation = HomeLocation(latitude: 35.0, longitude: 139.0)
        XCTAssertNotNil(defaults.data(forKey: AppSettings.Keys.homeLocation))

        settings.homeLocation = nil
        XCTAssertNil(defaults.data(forKey: AppSettings.Keys.homeLocation),
                     "nil 設定時は UserDefaults からキーが削除されるべき")
    }

    // MARK: - Fallback on invalid data

    func test_invalidRecordingMode_fallsBackToDefault() {
        defaults.set("not-a-valid-mode", forKey: AppSettings.Keys.recordingMode)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.recordingMode, AppSettings.defaultRecordingMode,
                       "不正な記録モード文字列はデフォルトに戻る")
    }

    func test_corruptedHomeLocationJSON_fallsBackToNil() {
        defaults.set("not a json".data(using: .utf8), forKey: AppSettings.Keys.homeLocation)
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.homeLocation, "破損 JSON は nil にフォールバック")
    }

    // MARK: - Radius clamping

    func test_radiusOutOfRange_isClampedOnInit() {
        defaults.set(20.0, forKey: AppSettings.Keys.homeRadiusMeters)
        let lowSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(lowSettings.homeRadiusMeters, AppSettings.homeRadiusMinMeters)

        defaults.set(500.0, forKey: AppSettings.Keys.homeRadiusMeters)
        let highSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(highSettings.homeRadiusMeters, AppSettings.homeRadiusMaxMeters)
    }

    func test_radiusBoundaries_acceptedAsIs() {
        let settings = AppSettings(defaults: defaults)
        settings.homeRadiusMeters = 50
        XCTAssertEqual(settings.homeRadiusMeters, 50)
        settings.homeRadiusMeters = 300
        XCTAssertEqual(settings.homeRadiusMeters, 300)
    }

    // MARK: - S5: クラウド保存先 / 自動同期

    /// (S5-001 / S5-004) デフォルトは未選択 / OFF。
    func test_cloudSettings_defaults_areNilAndOff() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.cloudProviderKind, "デフォルトは未選択")
        XCTAssertFalse(settings.cloudAutoSyncEnabled, "デフォルトは OFF")
    }

    /// (S5-001) cloudProviderKind の永続化往復。
    func test_cloudProviderKind_persistsAcrossInstances() {
        let first = AppSettings(defaults: defaults)
        first.cloudProviderKind = .googleDrive

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.cloudProviderKind, .googleDrive)
    }

    /// (S5-001) cloudProviderKind を nil に戻すと UserDefaults からキーが消える。
    func test_clearingCloudProviderKind_removesFromDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.cloudProviderKind = .googleDrive
        XCTAssertNotNil(defaults.string(forKey: AppSettings.Keys.cloudProviderKind))

        settings.cloudProviderKind = nil
        XCTAssertNil(defaults.string(forKey: AppSettings.Keys.cloudProviderKind))
    }

    /// (S5-004) cloudAutoSyncEnabled の永続化往復。
    func test_cloudAutoSyncEnabled_persistsAcrossInstances() {
        let first = AppSettings(defaults: defaults)
        first.cloudAutoSyncEnabled = true

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.cloudAutoSyncEnabled)
    }

    /// 不正な cloudProviderKind 文字列はデフォルト nil に倒す。
    func test_invalidCloudProviderKind_fallsBackToNil() {
        defaults.set("not-a-valid-provider", forKey: AppSettings.Keys.cloudProviderKind)
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.cloudProviderKind)
    }
}
