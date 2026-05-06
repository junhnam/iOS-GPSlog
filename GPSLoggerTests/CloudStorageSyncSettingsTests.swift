import XCTest
@testable import GPSLogger

/// S5-004 のユニットテスト: 自動同期 Toggle の ON/OFF が AppSettings に永続化される /
/// プロバイダ未選択時は Toggle が disabled になる / 再起動後も状態が保持されるの 3 ケース以上。
@MainActor
final class CloudStorageSyncSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CloudStorageSyncSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - ヘルパー

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: defaults)
    }

    // MARK: - (1) プロバイダ未選択時に Toggle が disable（cloudProviderKind == nil）

    func test_autoSyncToggle_isDisabled_whenProviderKindIsNil() {
        let settings = makeSettings()
        XCTAssertNil(settings.cloudProviderKind, "初期値は未選択")

        // SettingsView.cloudSyncToggleEnabled の判定ロジックを直接検証
        let isEnabled = settings.cloudProviderKind != nil
        XCTAssertFalse(isEnabled, "プロバイダ未選択時は Toggle が disabled")
    }

    // MARK: - (2) プロバイダ選択済み時は Toggle が有効

    func test_autoSyncToggle_isEnabled_whenProviderKindIsSet() {
        let settings = makeSettings()
        settings.cloudProviderKind = .googleDrive

        let isEnabled = settings.cloudProviderKind != nil
        XCTAssertTrue(isEnabled, "プロバイダ選択済み時は Toggle が有効")
    }

    // MARK: - (3) Toggle ON/OFF が AppSettings に永続化される

    func test_cloudAutoSyncEnabled_persistsWhenTurnedOn() {
        let settings = makeSettings()
        XCTAssertFalse(settings.cloudAutoSyncEnabled, "デフォルトは OFF")

        settings.cloudAutoSyncEnabled = true

        XCTAssertTrue(settings.cloudAutoSyncEnabled, "ON に設定できる")
    }

    func test_cloudAutoSyncEnabled_persistsWhenTurnedOff() {
        let settings = makeSettings()
        settings.cloudAutoSyncEnabled = true
        settings.cloudAutoSyncEnabled = false

        XCTAssertFalse(settings.cloudAutoSyncEnabled, "OFF に設定できる")
    }

    // MARK: - (4) Toggle 状態が再起動後も保持される（UserDefaults 永続化確認）

    func test_cloudAutoSyncEnabled_persistsAcrossInstances() {
        let first = AppSettings(defaults: defaults)
        first.cloudAutoSyncEnabled = true

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.cloudAutoSyncEnabled,
                      "自動同期 ON の状態は再起動後も保持される")
    }

    func test_cloudAutoSyncEnabled_persistsOffAcrossInstances() {
        let first = AppSettings(defaults: defaults)
        first.cloudAutoSyncEnabled = true
        first.cloudAutoSyncEnabled = false

        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.cloudAutoSyncEnabled,
                       "自動同期 OFF の状態は再起動後も保持される")
    }

    // MARK: - (5) Toggle OFF 時はアップロード処理が走らない（CloudUploadCoordinator との連携）
    // CloudUploadCoordinator.uploadIfEnabled は cloudAutoSyncEnabled を参照するため、
    // settings.cloudAutoSyncEnabled == false なら .skipped を返すことを確認する。
    // （CloudUploadCoordinatorTests でも検証済みだが、S5-004 の受け入れ条件として明記）

    func test_autoSyncOff_preventsUpload() async throws {
        let settings = makeSettings()
        settings.cloudProviderKind = .googleDrive
        settings.cloudAutoSyncEnabled = false  // OFF

        let provider = FakeCloudProvider()
        let sut = CloudUploadCoordinator(
            providers: [.googleDrive: provider],
            appSettings: settings,
            csvExporter: FakeCSVExporter()
        )
        let trip = makeTripRecord()
        let outcome = await sut.uploadIfEnabled(for: trip)

        if case .skipped(let reason) = outcome {
            XCTAssertTrue(reason.contains("cloudAutoSyncEnabled"),
                          "自動同期 OFF 時は cloudAutoSyncEnabled の理由で skip される")
        } else {
            XCTFail("自動同期 OFF なら .skipped 期待、実際: \(outcome)")
        }
        let uploadedPaths = await provider.uploadedPaths
        XCTAssertEqual(uploadedPaths, [], "アップロードは実行されない")
    }

    // MARK: - ヘルパー

    private func makeTripRecord() -> TripRecord {
        let date = Date(timeIntervalSince1970: 1_762_300_800)
        return TripRecord(date: date, startedAt: date)
    }
}

// MARK: - Test doubles

/// CloudStorageProvider のフェイク実装（S5-004 テスト用）。
private actor FakeCloudProvider: CloudStorageProvider {
    nonisolated var kind: CloudProviderKind { .googleDrive }

    var uploadedPaths: [String] = []

    @MainActor
    func isAuthenticated() async -> Bool { true }

    @MainActor
    func authenticate() async throws {}

    @MainActor
    func signOut() {}

    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult {
        uploadedPaths.append(path)
        return CloudUploadResult(fileID: "fake-id", path: path, webViewLink: nil)
    }
}

/// CSVExporting のフェイク実装（S5-004 テスト用）。
@MainActor
private struct FakeCSVExporter: CSVExporting {
    func csvData(for trip: TripRecord) throws -> Data {
        Data("date\n2026-05-06\n".utf8)
    }
}
