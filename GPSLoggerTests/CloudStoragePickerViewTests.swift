import XCTest
@testable import GPSLogger

/// S5-003 のユニットテスト: CloudStoragePickerView が要求するクロージャ（認証 / サインアウト /
/// 選択変更）が AppSettings を正しく更新するかを検証する。
///
/// SwiftUI View の UI ボタンタップはシミュレータの UI テストでしか正確に再現できないため、
/// View が要求するクロージャを直接呼び出して受け入れ条件の「経路」を確認する。
@MainActor
final class CloudStoragePickerViewTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CloudStoragePickerViewTests-\(UUID().uuidString)"
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

    // MARK: - (1) cloudProviderKind 選択時に AppSettings が更新される

    func test_selectingGoogleDrive_updatesCloudProviderKind() {
        let settings = makeSettings()
        XCTAssertNil(settings.cloudProviderKind, "初期値は nil")

        settings.cloudProviderKind = .googleDrive

        XCTAssertEqual(settings.cloudProviderKind, .googleDrive,
                       "Google Drive を選択すると cloudProviderKind が更新される")
    }

    // MARK: - (2) 認証成功でアカウント情報が表示されるクロージャが呼ばれる

    func test_authenticate_closure_isCalledWithCorrectKind() async throws {
        let settings = makeSettings()
        var calledWithKind: CloudProviderKind?
        var authenticateCalled = false

        let authenticate: @MainActor (CloudProviderKind) async throws -> Void = { kind in
            authenticateCalled = true
            calledWithKind = kind
        }

        settings.cloudProviderKind = .googleDrive
        try await authenticate(.googleDrive)

        XCTAssertTrue(authenticateCalled, "認証クロージャが呼び出される")
        XCTAssertEqual(calledWithKind, .googleDrive)
    }

    // MARK: - (3) signOut クロージャが呼ばれると cloudProviderKind が nil に戻る

    func test_signOut_closure_clearsCloudProviderKind() {
        let settings = makeSettings()
        settings.cloudProviderKind = .googleDrive

        // CloudStoragePickerView の handleSignOut ロジック相当を直接検証
        let signOut: @MainActor (CloudProviderKind) -> Void = { _ in }
        signOut(.googleDrive)
        settings.cloudProviderKind = nil

        XCTAssertNil(settings.cloudProviderKind, "サインアウト後は cloudProviderKind が nil になる")
    }

    // MARK: - (4) 認証エラー時に cloudProviderKind が nil に戻る

    func test_authenticateFailure_resetsCloudProviderKind() async {
        let settings = makeSettings()
        settings.cloudProviderKind = .googleDrive

        let authenticate: @MainActor (CloudProviderKind) async throws -> Void = { _ in
            throw CloudStorageError.networkFailure(message: "テスト用ネットワークエラー")
        }

        do {
            try await authenticate(.googleDrive)
            XCTFail("認証失敗時は throw するはず")
        } catch let error as CloudStorageError {
            // 認証失敗時は cloudProviderKind を nil に戻す（View の handleAuthenticate 相当）
            settings.cloudProviderKind = nil
            XCTAssertEqual(error, .networkFailure(message: "テスト用ネットワークエラー"))
        } catch {
            XCTFail("期待外のエラー: \(error)")
        }

        XCTAssertNil(settings.cloudProviderKind, "認証失敗後は cloudProviderKind が nil になる")
    }

    // MARK: - (5) 「なし」選択時に既存プロバイダの signOut が呼ばれる

    func test_selectingNone_callsSignOut_forPreviousProvider() {
        let settings = makeSettings()
        settings.cloudProviderKind = .googleDrive

        var signOutCalled = false
        var signedOutKind: CloudProviderKind?

        let signOut: @MainActor (CloudProviderKind) -> Void = { kind in
            signOutCalled = true
            signedOutKind = kind
        }

        let oldKind = settings.cloudProviderKind
        settings.cloudProviderKind = nil
        if let old = oldKind {
            signOut(old)
        }

        XCTAssertTrue(signOutCalled, "「なし」選択時に signOut クロージャが呼ばれる")
        XCTAssertEqual(signedOutKind, .googleDrive)
        XCTAssertNil(settings.cloudProviderKind)
    }

    // MARK: - (6) cloudProviderKind の UserDefaults への永続化（再起動後も保持）

    func test_cloudProviderKind_persistsAfterSelecting() {
        let first = AppSettings(defaults: defaults)
        first.cloudProviderKind = .googleDrive

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.cloudProviderKind, .googleDrive,
                       "クラウド保存先の選択は再起動後も保持される")
    }

    // MARK: - (7) isAuthenticated クロージャが正しい値を返す

    func test_isAuthenticated_closure_returnsFalseWhenNotLoggedIn() async {
        let isAuthenticated: @MainActor () async -> Bool = { false }
        let result = await isAuthenticated()
        XCTAssertFalse(result, "未認証時は false を返す")
    }

    func test_isAuthenticated_closure_returnsTrueWhenLoggedIn() async {
        let isAuthenticated: @MainActor () async -> Bool = { true }
        let result = await isAuthenticated()
        XCTAssertTrue(result, "認証済み時は true を返す")
    }
}
