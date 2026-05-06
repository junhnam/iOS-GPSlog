import XCTest
@testable import GPSLogger

/// S5-001 のユニットテスト: GoogleDriveSyncService の OAuth フロー / トークンリフレッシュ /
/// アップロード / リトライ判定をフェイクで検証する。
///
/// 実 OAuth は jun さん側のシミュレータ確認で動作検証する（受け入れ条件）。
/// 本テストはネットワーク呼び出し / Web セッションをすべてフェイクに差し替える。
final class GoogleDriveSyncServiceTests: XCTestCase {

    // MARK: - (1) OAuth 成功

    func test_authenticate_succeeds_andSavesTokens_S5_001() async throws {
        let store = InMemoryTokenStore()
        let runner = FakeWebAuthRunner(result: .success(URL(string: "com.example:/oauth/callback?code=AUTH_CODE_001")!))
        let http = FakeHTTPClient(
            tokenResponse: .success(GoogleDriveTokens(accessToken: "access-1",
                                                      refreshToken: "refresh-1",
                                                      expiresAt: Date().addingTimeInterval(3600)))
        )
        let sut = GoogleDriveSyncService(
            httpClient: http,
            clientIDProvider: StaticClientIDProvider(),
            tokenStore: store,
            webAuthRunner: runner,
            pkceGenerator: FixedPKCEGenerator()
        )

        try await sut.authenticate()

        let saved = await store.snapshot()
        XCTAssertEqual(saved?.accessToken, "access-1")
        XCTAssertEqual(saved?.refreshToken, "refresh-1")
        let exchanged = await http.exchangedCode
        XCTAssertEqual(exchanged, "AUTH_CODE_001",
                       "Web セッションから取り出した authorization code が token 交換に渡される")
    }

    // MARK: - (2) OAuth ユーザー拒否

    func test_authenticate_throwsUserCancelled_whenSessionDeniedByUser_S5_001() async {
        let runner = FakeWebAuthRunner(result: .failure(CloudStorageError.userCancelled))
        let sut = GoogleDriveSyncService(
            httpClient: FakeHTTPClient(),
            clientIDProvider: StaticClientIDProvider(),
            tokenStore: InMemoryTokenStore(),
            webAuthRunner: runner,
            pkceGenerator: FixedPKCEGenerator()
        )

        do {
            try await sut.authenticate()
            XCTFail("拒否で throw するはず")
        } catch let error as CloudStorageError {
            XCTAssertEqual(error, .userCancelled)
        } catch {
            XCTFail("期待外の error: \(error)")
        }
    }

    // MARK: - (3) アップロード成功

    func test_uploadCSV_createsFolderHierarchy_andUploadsFile_S5_001() async throws {
        let tokens = GoogleDriveTokens(accessToken: "access-1",
                                       refreshToken: "refresh-1",
                                       expiresAt: Date().addingTimeInterval(3600))
        let store = InMemoryTokenStore()
        await store.preload(tokens)

        let http = FakeHTTPClient(
            findFolderHandler: { name, _ in
                // ルート GPSログ + 日付フォルダ ともに新規作成想定
                return nil
            },
            findFileHandler: { _, _ in
                return nil
            },
            createFolderHandler: { name, parent in
                return "folder-\(name)"
            },
            uploadNewFileHandler: { _, parent, _ in
                return GoogleDriveFileResponse(fileID: "new-file-001",
                                               webViewLink: URL(string: "https://drive.google.com/file/d/new-file-001/view"))
            }
        )

        let sut = GoogleDriveSyncService(
            httpClient: http,
            clientIDProvider: StaticClientIDProvider(),
            tokenStore: store,
            webAuthRunner: FakeWebAuthRunner(result: .failure(CloudStorageError.userCancelled)),
            pkceGenerator: FixedPKCEGenerator()
        )

        let data = "csv,data".data(using: .utf8)!
        let result = try await sut.uploadCSV(data, toPath: "GPSログ/2026-05-06/data.csv")

        XCTAssertEqual(result.fileID, "new-file-001")
        XCTAssertEqual(result.path, "GPSログ/2026-05-06/data.csv")

        let createdFolders = await http.createdFolders
        XCTAssertEqual(createdFolders, ["GPSログ", "2026-05-06"],
                       "ルート → 日付の順でフォルダが作成される")
    }

    // MARK: - (4) アップロード時のトークンリフレッシュ

    func test_uploadCSV_refreshesExpiredToken_S5_001() async throws {
        // 期限切れトークン（過去日時）
        let expired = GoogleDriveTokens(accessToken: "expired",
                                        refreshToken: "refresh-1",
                                        expiresAt: Date().addingTimeInterval(-100))
        let store = InMemoryTokenStore()
        await store.preload(expired)

        let http = FakeHTTPClient(
            tokenResponse: .success(GoogleDriveTokens(accessToken: "fresh-access",
                                                      refreshToken: "refresh-1",
                                                      expiresAt: Date().addingTimeInterval(3600))),
            findFolderHandler: { _, _ in "GPSログ-id" },
            findFileHandler: { _, _ in "data-csv-id" },
            updateFileContentsHandler: { fileID, _ in
                return GoogleDriveFileResponse(fileID: fileID, webViewLink: nil)
            }
        )

        let sut = GoogleDriveSyncService(
            httpClient: http,
            clientIDProvider: StaticClientIDProvider(),
            tokenStore: store,
            webAuthRunner: FakeWebAuthRunner(result: .failure(CloudStorageError.userCancelled)),
            pkceGenerator: FixedPKCEGenerator()
        )

        let data = "csv".data(using: .utf8)!
        let result = try await sut.uploadCSV(data, toPath: "GPSログ/2026-05-06/data.csv")

        XCTAssertEqual(result.fileID, "data-csv-id", "既存ファイルを上書き")
        let refreshes = await http.refreshCallCount
        XCTAssertEqual(refreshes, 1, "期限切れの場合 refresh が 1 回呼ばれる")
        let savedAfter = await store.snapshot()
        XCTAssertEqual(savedAfter?.accessToken, "fresh-access",
                       "新しい access_token が Keychain に保存される")
    }

    // MARK: - (5) ネットワーク失敗時の挙動

    func test_uploadCSV_throwsNetworkFailure_whenHTTPClientFails_S5_001() async {
        let tokens = GoogleDriveTokens(accessToken: "access-1",
                                       refreshToken: "refresh-1",
                                       expiresAt: Date().addingTimeInterval(3600))
        let store = InMemoryTokenStore()
        await store.preload(tokens)

        let http = FakeHTTPClient(
            findFolderHandler: { _, _ in
                throw CloudStorageError.networkFailure(message: "offline")
            }
        )

        let sut = GoogleDriveSyncService(
            httpClient: http,
            clientIDProvider: StaticClientIDProvider(),
            tokenStore: store,
            webAuthRunner: FakeWebAuthRunner(result: .failure(CloudStorageError.userCancelled)),
            pkceGenerator: FixedPKCEGenerator()
        )

        do {
            _ = try await sut.uploadCSV(Data(), toPath: "GPSログ/2026-05-06/data.csv")
            XCTFail("ネットワーク失敗で throw するはず")
        } catch let error as CloudStorageError {
            XCTAssertEqual(error, .networkFailure(message: "offline"))
            XCTAssertTrue(error.isRetryable, "ネットワーク失敗は retryable")
        } catch {
            XCTFail("予期せぬ error: \(error)")
        }
    }

    // MARK: - (6) リフレッシュ失敗で authenticationExpired

    func test_uploadCSV_throwsAuthenticationExpired_whenRefreshFailsWith401_S5_001() async {
        let expired = GoogleDriveTokens(accessToken: "expired",
                                        refreshToken: "refresh-1",
                                        expiresAt: Date().addingTimeInterval(-100))
        let store = InMemoryTokenStore()
        await store.preload(expired)

        let http = FakeHTTPClient(
            tokenResponse: .failure(CloudStorageError.apiError(statusCode: 401, message: "invalid_grant"))
        )

        let sut = GoogleDriveSyncService(
            httpClient: http,
            clientIDProvider: StaticClientIDProvider(),
            tokenStore: store,
            webAuthRunner: FakeWebAuthRunner(result: .failure(CloudStorageError.userCancelled)),
            pkceGenerator: FixedPKCEGenerator()
        )

        do {
            _ = try await sut.uploadCSV(Data(), toPath: "GPSログ/2026-05-06/data.csv")
            XCTFail("リフレッシュ失敗で throw するはず")
        } catch let error as CloudStorageError {
            XCTAssertEqual(error, .authenticationExpired)
            XCTAssertFalse(error.isRetryable, "認証期限切れはリトライ対象外")
        } catch {
            XCTFail("予期せぬ error: \(error)")
        }
    }

    // MARK: - (7) isRetryable の網羅

    func test_isRetryable_classification() {
        XCTAssertFalse(CloudStorageError.notAuthenticated.isRetryable)
        XCTAssertFalse(CloudStorageError.authenticationExpired.isRetryable)
        XCTAssertFalse(CloudStorageError.userCancelled.isRetryable)
        XCTAssertTrue(CloudStorageError.networkFailure(message: "x").isRetryable)
        XCTAssertTrue(CloudStorageError.apiError(statusCode: 503, message: "down").isRetryable)
        XCTAssertFalse(CloudStorageError.apiError(statusCode: 400, message: "bad").isRetryable)
        XCTAssertFalse(CloudStorageError.apiError(statusCode: 404, message: "not found").isRetryable)
        XCTAssertFalse(CloudStorageError.keychainFailure(message: "x").isRetryable)
        XCTAssertFalse(CloudStorageError.unknown(message: "x").isRetryable)
    }

    // MARK: - (8) URL 組み立て

    func test_buildAuthorizationURL_includesPKCEParameters() {
        let url = GoogleDriveSyncService.buildAuthorizationURL(
            clientID: "test-client.apps.googleusercontent.com",
            redirectURI: "com.example:/oauth/callback",
            codeChallenge: "abc123"
        )
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.host, "accounts.google.com")
        let q = comps.queryItems ?? []
        XCTAssertEqual(q.first { $0.name == "code_challenge" }?.value, "abc123")
        XCTAssertEqual(q.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(q.first { $0.name == "access_type" }?.value, "offline")
        XCTAssertEqual(q.first { $0.name == "scope" }?.value, "https://www.googleapis.com/auth/drive.file")
    }

    func test_extractCode_returnsCodeQueryItem() {
        let url = URL(string: "com.example:/oauth/callback?code=ABC123&state=xyz")!
        XCTAssertEqual(GoogleDriveSyncService.extractCode(from: url), "ABC123")

        let none = URL(string: "com.example:/oauth/callback?error=access_denied")!
        XCTAssertNil(GoogleDriveSyncService.extractCode(from: none))
    }
}

// MARK: - Test doubles

private struct StaticClientIDProvider: GoogleDriveClientIDProviding {
    func clientID() -> String? { "test-client.apps.googleusercontent.com" }
    func redirectURI() -> String { "com.googleusercontent.apps.test-client:/oauth/callback" }
    func callbackScheme() -> String { "com.googleusercontent.apps.test-client" }
}

private struct FixedPKCEGenerator: GoogleDrivePKCEGenerating {
    func generate() -> GoogleDrivePKCEPair {
        GoogleDrivePKCEPair(codeVerifier: "fixed-verifier-12345",
                            codeChallenge: "fixed-challenge-abcde")
    }
}

/// `GoogleDriveTokenStoring` のインメモリ実装。テスト用。
private actor InMemoryTokenStore: GoogleDriveTokenStoring {
    private var tokens: GoogleDriveTokens?

    func loadTokens() async throws -> GoogleDriveTokens? {
        return tokens
    }

    func saveTokens(_ tokens: GoogleDriveTokens) async throws {
        self.tokens = tokens
    }

    func clearTokens() async throws {
        self.tokens = nil
    }

    func preload(_ tokens: GoogleDriveTokens) {
        self.tokens = tokens
    }

    func snapshot() -> GoogleDriveTokens? { tokens }
}

private struct FakeWebAuthRunner: GoogleDriveWebAuthRunning {
    enum Outcome: Sendable {
        case success(URL)
        case failure(Error)
    }
    let result: Outcome

    @MainActor
    func start(authURL: URL, callbackURLScheme: String) async throws -> URL {
        switch result {
        case .success(let url): return url
        case .failure(let error): throw error
        }
    }
}

/// `GoogleDriveHTTPClient` のフェイク。テストごとに挙動を differ する。
private final class FakeHTTPClient: GoogleDriveHTTPClient, @unchecked Sendable {
    enum TokenOutcome {
        case success(GoogleDriveTokens)
        case failure(Error)
    }

    private let tokenResponse: TokenOutcome
    private let findFolderHandler: (@Sendable (String, String?) async throws -> String?)?
    private let findFileHandler: (@Sendable (String, String) async throws -> String?)?
    private let createFolderHandler: (@Sendable (String, String?) async throws -> String)?
    private let uploadNewFileHandler: (@Sendable (String, String, Data) async throws -> GoogleDriveFileResponse)?
    private let updateFileContentsHandler: (@Sendable (String, Data) async throws -> GoogleDriveFileResponse)?

    private let stateLock = NSLock()
    private var _exchangedCode: String?
    private var _refreshCallCount: Int = 0
    private var _createdFolders: [String] = []

    init(
        tokenResponse: TokenOutcome = .success(GoogleDriveTokens(accessToken: "default-access",
                                                                  refreshToken: "default-refresh",
                                                                  expiresAt: Date().addingTimeInterval(3600))),
        findFolderHandler: (@Sendable (String, String?) async throws -> String?)? = nil,
        findFileHandler: (@Sendable (String, String) async throws -> String?)? = nil,
        createFolderHandler: (@Sendable (String, String?) async throws -> String)? = nil,
        uploadNewFileHandler: (@Sendable (String, String, Data) async throws -> GoogleDriveFileResponse)? = nil,
        updateFileContentsHandler: (@Sendable (String, Data) async throws -> GoogleDriveFileResponse)? = nil
    ) {
        self.tokenResponse = tokenResponse
        self.findFolderHandler = findFolderHandler
        self.findFileHandler = findFileHandler
        self.createFolderHandler = createFolderHandler
        self.uploadNewFileHandler = uploadNewFileHandler
        self.updateFileContentsHandler = updateFileContentsHandler
    }

    var exchangedCode: String? {
        get async {
            stateLock.withLock { _exchangedCode }
        }
    }

    var refreshCallCount: Int {
        get async {
            stateLock.withLock { _refreshCallCount }
        }
    }

    var createdFolders: [String] {
        get async {
            stateLock.withLock { _createdFolders }
        }
    }

    func exchangeCodeForTokens(code: String,
                               codeVerifier: String,
                               clientID: String,
                               redirectURI: String) async throws -> GoogleDriveTokens {
        stateLock.withLock { _exchangedCode = code }
        switch tokenResponse {
        case .success(let tokens): return tokens
        case .failure(let err): throw err
        }
    }

    func refreshTokens(refreshToken: String, clientID: String) async throws -> GoogleDriveTokens {
        stateLock.withLock { _refreshCallCount += 1 }
        switch tokenResponse {
        case .success(let tokens): return tokens
        case .failure(let err): throw err
        }
    }

    func findFolder(name: String, parent: String?, accessToken: String) async throws -> String? {
        if let h = findFolderHandler {
            return try await h(name, parent)
        }
        return nil
    }

    func findFile(name: String, parent: String, accessToken: String) async throws -> String? {
        if let h = findFileHandler {
            return try await h(name, parent)
        }
        return nil
    }

    func createFolder(name: String, parent: String?, accessToken: String) async throws -> String {
        stateLock.withLock { _createdFolders.append(name) }
        if let h = createFolderHandler {
            return try await h(name, parent)
        }
        return "folder-\(name)"
    }

    func uploadNewFile(name: String, parent: String, data: Data, accessToken: String) async throws -> GoogleDriveFileResponse {
        if let h = uploadNewFileHandler {
            return try await h(name, parent, data)
        }
        return GoogleDriveFileResponse(fileID: "new-\(name)", webViewLink: nil)
    }

    func updateFileContents(fileID: String, data: Data, accessToken: String) async throws -> GoogleDriveFileResponse {
        if let h = updateFileContentsHandler {
            return try await h(fileID, data)
        }
        return GoogleDriveFileResponse(fileID: fileID, webViewLink: nil)
    }
}
