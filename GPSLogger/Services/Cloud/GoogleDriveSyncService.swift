import Foundation
@preconcurrency import AuthenticationServices
import CryptoKit
import UIKit
import os

/// Google Drive へのファイルアップロードを担う `CloudStorageProvider` の実装（S5-001）。
///
/// 設計判断（jun さん承認 2026-05-06「具体的な SDK 選定は Dev-2 の判断で進めて OK」を受けて）:
///   - 公式 SDK（GoogleSignIn-iOS / google-api-objectivec-client-for-rest）は導入せず、
///     Apple 純正 `ASWebAuthenticationSession` + `URLSession` で軽量実装する
///   - 理由 1: バイナリサイズ増を回避（公式 SDK は +10〜15MB）
///   - 理由 2: iOS 26 / Swift 6 strict concurrency と素直に整合（公式 SDK は Objective-C ベース）
///   - 理由 3: OAuth PKCE フローと Drive REST v3 の multipart upload は仕様が単純で自前実装可能
///   - トレードオフ: トークンリフレッシュの実装責任を持つ（公式 SDK なら自動）
///
/// セキュリティ（CLAUDE.md / autonomous-rules.md）:
///   - OAuth クライアント ID は Info.plist に保存（公開して問題ない値・PKCE フロー前提でクライアントシークレットなし）
///   - **アクセストークン / リフレッシュトークン / コードベリファイアは Keychain に保存**
///   - UserDefaults / plist には絶対に書かない
///
/// 認証フロー:
///   1. PKCE: code_verifier (Keychain 保存) + code_challenge を生成
///   2. ASWebAuthenticationSession で認可エンドポイントを開く
///   3. リダイレクト URL から authorization code を取得
///   4. token エンドポイントへ POST → access_token / refresh_token を取得
///   5. Keychain に保存
///
/// アップロードフロー:
///   1. 親フォルダ（GPSログ）を Drive 内で検索 / なければ作成
///   2. 日付フォルダ（YYYY-MM-DD）を上記内で検索 / なければ作成
///   3. 既存 data.csv があれば PATCH で上書き、無ければ multipart upload
actor GoogleDriveSyncService: CloudStorageProvider {
    nonisolated var kind: CloudProviderKind { .googleDrive }

    /// HTTP クライアント。テスト時に差し替え可能。
    private let httpClient: any GoogleDriveHTTPClient

    /// OAuth クライアント ID プロバイダ。Info.plist から読む（テスト時は固定値）。
    private let clientIDProvider: any GoogleDriveClientIDProviding

    /// Keychain ラッパー。テスト時はインメモリ実装に差し替え可能。
    private let tokenStore: any GoogleDriveTokenStoring

    /// OAuth Web セッション起動。テスト時はフェイクで「成功 / 拒否」を選ぶ。
    private let webAuthRunner: any GoogleDriveWebAuthRunning

    /// PKCE 用のランダム値生成（テスト時に差し替えで決定論にする）。
    private let pkceGenerator: any GoogleDrivePKCEGenerating

    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "GoogleDriveSyncService")

    /// Drive 上のルートフォルダ名（「GPSログ」）。S5-005 の階層仕様に対応。
    static let rootFolderName: String = "GPSログ"

    init(
        httpClient: any GoogleDriveHTTPClient = LiveGoogleDriveHTTPClient(),
        clientIDProvider: any GoogleDriveClientIDProviding = InfoPlistGoogleDriveClientIDProvider(),
        tokenStore: any GoogleDriveTokenStoring = KeychainGoogleDriveTokenStore(),
        webAuthRunner: any GoogleDriveWebAuthRunning = ASWebAuthGoogleDriveWebAuthRunner(),
        pkceGenerator: any GoogleDrivePKCEGenerating = LiveGoogleDrivePKCEGenerator()
    ) {
        self.httpClient = httpClient
        self.clientIDProvider = clientIDProvider
        self.tokenStore = tokenStore
        self.webAuthRunner = webAuthRunner
        self.pkceGenerator = pkceGenerator
    }

    // MARK: - CloudStorageProvider

    @MainActor
    func isAuthenticated() async -> Bool {
        return (try? await self.hasValidTokens()) ?? false
    }

    @MainActor
    func authenticate() async throws {
        // 1. クライアント ID / PKCE / リダイレクト URI を取得（actor 越しの読み取り）
        let clientID: String? = self.clientIDProvider.clientID()
        guard let clientID, !clientID.isEmpty else {
            throw CloudStorageError.unknown(message: "OAuth クライアント ID 未設定（Info.plist の GoogleDriveOAuthClientID を確認してください）")
        }
        let pkce: GoogleDrivePKCEPair = self.pkceGenerator.generate()
        let redirectURI: String = self.clientIDProvider.redirectURI()
        let callbackScheme: String = self.clientIDProvider.callbackScheme()
        let authURL = Self.buildAuthorizationURL(
            clientID: clientID,
            redirectURI: redirectURI,
            codeChallenge: pkce.codeChallenge
        )

        // 2. WebAuth 起動（MainActor 必須）
        let callbackURL: URL
        do {
            callbackURL = try await webAuthRunner.start(authURL: authURL,
                                                        callbackURLScheme: callbackScheme)
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.unknown(message: "OAuth Web セッション失敗: \(error.localizedDescription)")
        }

        guard let code = Self.extractCode(from: callbackURL) else {
            throw CloudStorageError.unknown(message: "認可コードの取得に失敗しました")
        }

        // 3. actor 隔離部分でトークン交換 + Keychain 保存
        try await self.completeAuthentication(
            authorizationCode: code,
            codeVerifier: pkce.codeVerifier,
            clientID: clientID,
            redirectURI: redirectURI
        )
    }

    /// Authorization code をトークンに交換し、Keychain に保存する（actor 隔離）。
    private func completeAuthentication(authorizationCode: String,
                                        codeVerifier: String,
                                        clientID: String,
                                        redirectURI: String) async throws {
        let tokens = try await httpClient.exchangeCodeForTokens(
            code: authorizationCode,
            codeVerifier: codeVerifier,
            clientID: clientID,
            redirectURI: redirectURI
        )
        do {
            try await tokenStore.saveTokens(tokens)
        } catch {
            throw CloudStorageError.keychainFailure(message: error.localizedDescription)
        }
    }

    @MainActor
    func signOut() {
        // fire-and-forget。actor 上で Keychain クリアを実行する。
        // 失敗時はログのみ（UI に影響しない）。
        Task { [weak self] in
            await self?.clearTokens()
        }
    }

    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult {
        // 1. トークン確認 / 期限切れならリフレッシュ
        let accessToken = try await acquireValidAccessToken()

        // 2. パスをパース（GPSログ/2026-05-06/data.csv）
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else {
            throw CloudStorageError.unknown(message: "アップロードパスが不正: \(path)")
        }
        let fileName = components.last ?? "data.csv"
        let folderComponents = Array(components.dropLast())

        // 3. 親フォルダを再帰的に取得 / 作成
        var parentID: String? = nil
        for folder in folderComponents {
            parentID = try await ensureFolder(named: folder, parent: parentID, accessToken: accessToken)
        }
        guard let finalParentID = parentID else {
            throw CloudStorageError.unknown(message: "親フォルダ ID 解決失敗")
        }

        // 4. 既存ファイルの検索（同じパスに既にあれば PATCH で上書き）
        if let existingID = try await findFile(named: fileName, parent: finalParentID, accessToken: accessToken) {
            return try await updateFile(fileID: existingID, data: data, accessToken: accessToken, path: path)
        }
        return try await createFile(name: fileName, parent: finalParentID, data: data, accessToken: accessToken, path: path)
    }

    // MARK: - Authentication

    /// Keychain にトークンが保存されており、リフレッシュトークンが残っていれば認証済み扱い。
    private func hasValidTokens() async throws -> Bool {
        do {
            let tokens = try await tokenStore.loadTokens()
            return tokens?.refreshToken.isEmpty == false
        } catch {
            return false
        }
    }

    private func clearTokens() async {
        do {
            try await tokenStore.clearTokens()
        } catch {
            Self.logger.warning("Keychain クリア失敗: \(error.localizedDescription)")
        }
    }

    /// 認証フローの URL 組み立て（PKCE）。
    static func buildAuthorizationURL(clientID: String,
                                      redirectURI: String,
                                      codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }

    /// コールバック URL（gpsl ogger://oauth?code=...）から code を取り出す。
    static func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }

    /// 有効な access_token を返す。期限切れならリフレッシュを試みる。
    private func acquireValidAccessToken() async throws -> String {
        guard let tokens = try? await tokenStore.loadTokens() else {
            throw CloudStorageError.notAuthenticated
        }
        // 期限の 60 秒前を判定境界にする（時計ずれ対策）。
        let now = Date()
        if let expiresAt = tokens.expiresAt, expiresAt.timeIntervalSince(now) > 60 {
            return tokens.accessToken
        }
        // リフレッシュ
        guard let clientID = clientIDProvider.clientID() else {
            throw CloudStorageError.notAuthenticated
        }
        do {
            let refreshed = try await httpClient.refreshTokens(refreshToken: tokens.refreshToken,
                                                               clientID: clientID)
            try await tokenStore.saveTokens(refreshed)
            return refreshed.accessToken
        } catch let error as CloudStorageError {
            // リフレッシュに失敗した場合は認証期限切れとして扱う
            if case .apiError(let code, _) = error, code == 400 || code == 401 {
                throw CloudStorageError.authenticationExpired
            }
            throw error
        }
    }

    // MARK: - Drive operations

    /// フォルダを名前で検索 / 無ければ作成して fileId を返す。
    private func ensureFolder(named name: String,
                              parent: String?,
                              accessToken: String) async throws -> String {
        if let existing = try await findFolder(named: name, parent: parent, accessToken: accessToken) {
            return existing
        }
        return try await httpClient.createFolder(name: name, parent: parent, accessToken: accessToken)
    }

    private func findFolder(named name: String,
                            parent: String?,
                            accessToken: String) async throws -> String? {
        try await httpClient.findFolder(name: name, parent: parent, accessToken: accessToken)
    }

    private func findFile(named name: String,
                          parent: String,
                          accessToken: String) async throws -> String? {
        try await httpClient.findFile(name: name, parent: parent, accessToken: accessToken)
    }

    private func createFile(name: String,
                            parent: String,
                            data: Data,
                            accessToken: String,
                            path: String) async throws -> CloudUploadResult {
        let response = try await httpClient.uploadNewFile(name: name,
                                                          parent: parent,
                                                          data: data,
                                                          accessToken: accessToken)
        return CloudUploadResult(fileID: response.fileID,
                                 path: path,
                                 webViewLink: response.webViewLink)
    }

    private func updateFile(fileID: String,
                            data: Data,
                            accessToken: String,
                            path: String) async throws -> CloudUploadResult {
        let response = try await httpClient.updateFileContents(fileID: fileID,
                                                               data: data,
                                                               accessToken: accessToken)
        return CloudUploadResult(fileID: response.fileID,
                                 path: path,
                                 webViewLink: response.webViewLink)
    }
}

// MARK: - Tokens

/// Google Drive の OAuth トークンセット（S5-001）。
/// Keychain に保存され、Sendable で actor 越しに渡せる値型。
struct GoogleDriveTokens: Sendable, Equatable, Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?

    init(accessToken: String, refreshToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Drive ファイル / フォルダ作成・更新の戻り値。
struct GoogleDriveFileResponse: Sendable, Equatable {
    let fileID: String
    let webViewLink: URL?

    init(fileID: String, webViewLink: URL?) {
        self.fileID = fileID
        self.webViewLink = webViewLink
    }
}

// MARK: - Test seam protocols

/// HTTP 通信の最小限のインタフェース（S5-001）。
/// 本番では URLSession で Drive REST v3 / OAuth エンドポイントを叩く `LiveGoogleDriveHTTPClient`、
/// テストでは決定論的なフェイクを差し込む。
protocol GoogleDriveHTTPClient: Sendable {
    func exchangeCodeForTokens(code: String,
                               codeVerifier: String,
                               clientID: String,
                               redirectURI: String) async throws -> GoogleDriveTokens

    func refreshTokens(refreshToken: String,
                       clientID: String) async throws -> GoogleDriveTokens

    func findFolder(name: String,
                    parent: String?,
                    accessToken: String) async throws -> String?

    func findFile(name: String,
                  parent: String,
                  accessToken: String) async throws -> String?

    func createFolder(name: String,
                      parent: String?,
                      accessToken: String) async throws -> String

    func uploadNewFile(name: String,
                       parent: String,
                       data: Data,
                       accessToken: String) async throws -> GoogleDriveFileResponse

    func updateFileContents(fileID: String,
                            data: Data,
                            accessToken: String) async throws -> GoogleDriveFileResponse
}

/// OAuth クライアント ID / リダイレクト URI / コールバックスキームの提供。
protocol GoogleDriveClientIDProviding: Sendable {
    func clientID() -> String?
    func redirectURI() -> String
    func callbackScheme() -> String
}

/// Keychain ラッパー（テスト時はインメモリ実装に差し替え）。
protocol GoogleDriveTokenStoring: Sendable {
    func loadTokens() async throws -> GoogleDriveTokens?
    func saveTokens(_ tokens: GoogleDriveTokens) async throws
    func clearTokens() async throws
}

/// OAuth Web セッション起動。
protocol GoogleDriveWebAuthRunning: Sendable {
    @MainActor
    func start(authURL: URL, callbackURLScheme: String) async throws -> URL
}

/// PKCE 用ランダム値生成。
protocol GoogleDrivePKCEGenerating: Sendable {
    func generate() -> GoogleDrivePKCEPair
}

struct GoogleDrivePKCEPair: Sendable, Equatable {
    let codeVerifier: String
    let codeChallenge: String

    init(codeVerifier: String, codeChallenge: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
    }
}

// MARK: - Live implementations

/// 本番用 HTTP クライアント。URLSession で Google API を叩く。
/// Sprint 5 ではユニットテストでは触らず、jun さん側のシミュレータ実 OAuth 確認で動作検証する。
struct LiveGoogleDriveHTTPClient: GoogleDriveHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchangeCodeForTokens(code: String,
                                      codeVerifier: String,
                                      clientID: String,
                                      redirectURI: String) async throws -> GoogleDriveTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        let body = [
            "code": code,
            "code_verifier": codeVerifier,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        request.httpBody = Self.formURLEncoded(body).data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return try await Self.parseTokenResponse(session: session, request: request)
    }

    func refreshTokens(refreshToken: String,
                              clientID: String) async throws -> GoogleDriveTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token"
        ]
        request.httpBody = Self.formURLEncoded(body).data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let refreshed = try await Self.parseTokenResponse(session: session,
                                                          request: request,
                                                          fallbackRefreshToken: refreshToken)
        return refreshed
    }

    func findFolder(name: String,
                           parent: String?,
                           accessToken: String) async throws -> String? {
        try await findItem(name: name,
                           parent: parent,
                           mimeType: "application/vnd.google-apps.folder",
                           accessToken: accessToken)
    }

    func findFile(name: String,
                         parent: String,
                         accessToken: String) async throws -> String? {
        try await findItem(name: name, parent: parent, mimeType: nil, accessToken: accessToken)
    }

    func createFolder(name: String,
                             parent: String?,
                             accessToken: String) async throws -> String {
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let parent {
            metadata["parents"] = [parent]
        }
        let body = try JSONSerialization.data(withJSONObject: metadata)
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.assertStatus(response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else {
            throw CloudStorageError.unknown(message: "createFolder: id not found")
        }
        return id
    }

    func uploadNewFile(name: String,
                              parent: String,
                              data: Data,
                              accessToken: String) async throws -> GoogleDriveFileResponse {
        let boundary = "GPSLoggerBoundary-\(UUID().uuidString)"
        let metadata: [String: Any] = [
            "name": name,
            "parents": [parent]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let body = Self.multipartBody(boundary: boundary, metadata: metadataData, fileData: data)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (responseData, response) = try await session.data(for: request)
        try Self.assertStatus(response: response, data: responseData)
        return try Self.parseFileResponse(responseData)
    }

    func updateFileContents(fileID: String,
                                   data: Data,
                                   accessToken: String) async throws -> GoogleDriveFileResponse {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media&fields=id,webViewLink")!)
        request.httpMethod = "PATCH"
        request.httpBody = data
        request.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (responseData, response) = try await session.data(for: request)
        try Self.assertStatus(response: response, data: responseData)
        return try Self.parseFileResponse(responseData)
    }

    // MARK: - Helpers

    private func findItem(name: String,
                          parent: String?,
                          mimeType: String?,
                          accessToken: String) async throws -> String? {
        var queryParts = [
            "name='\(name.replacingOccurrences(of: "'", with: "\\'"))'",
            "trashed=false"
        ]
        if let parent {
            queryParts.append("'\(parent)' in parents")
        }
        if let mimeType {
            queryParts.append("mimeType='\(mimeType)'")
        }
        let q = queryParts.joined(separator: " and ")
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.assertStatus(response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]]
        return (files?.first?["id"] as? String)
    }

    static func assertStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CloudStorageError.unknown(message: "HTTP レスポンスでない")
        }
        if (200..<300).contains(http.statusCode) { return }
        let message = String(data: data, encoding: .utf8) ?? "(no body)"
        throw CloudStorageError.apiError(statusCode: http.statusCode, message: message)
    }

    static func parseTokenResponse(session: URLSession,
                                   request: URLRequest,
                                   fallbackRefreshToken: String? = nil) async throws -> GoogleDriveTokens {
        let (data, response) = try await session.data(for: request)
        try assertStatus(response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String else {
            throw CloudStorageError.unknown(message: "access_token がレスポンスに無い")
        }
        let refresh = (json?["refresh_token"] as? String) ?? fallbackRefreshToken ?? ""
        let expiresIn = (json?["expires_in"] as? Double) ?? 0
        let expiresAt = Date().addingTimeInterval(expiresIn)
        return GoogleDriveTokens(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    static func parseFileResponse(_ data: Data) throws -> GoogleDriveFileResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else {
            throw CloudStorageError.unknown(message: "file id がレスポンスに無い")
        }
        let link = (json?["webViewLink"] as? String).flatMap(URL.init(string:))
        return GoogleDriveFileResponse(fileID: id, webViewLink: link)
    }

    static func multipartBody(boundary: String, metadata: Data, fileData: Data) -> Data {
        var body = Data()
        let crlf = "\r\n".data(using: .utf8)!
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadata)
        body.append(crlf)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append(crlf)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func formURLEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}

/// Info.plist から OAuth クライアント ID を読む実装。
struct InfoPlistGoogleDriveClientIDProvider: GoogleDriveClientIDProviding {
    init() {}

    func clientID() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "GoogleDriveOAuthClientID") as? String
    }

    func redirectURI() -> String {
        // Google iOS OAuth の慣例: <reversed-client-id>:/oauth/callback
        let id = clientID() ?? ""
        let reversed = id.split(separator: ".").reversed().joined(separator: ".")
        return "\(reversed):/oauth/callback"
    }

    func callbackScheme() -> String {
        let id = clientID() ?? ""
        return id.split(separator: ".").reversed().joined(separator: ".")
    }
}

/// Keychain にトークンを保存する実装（Sprint 5 では最小実装）。
/// Sprint 6 で SecKey ベースの暗号化を強化する余地を残す。
actor KeychainGoogleDriveTokenStore: GoogleDriveTokenStoring {
    private let service: String
    private let account: String

    init(service: String = "com.junhnam.gpslogger.googledrive",
                account: String = "tokens.v1") {
        self.service = service
        self.account = account
    }

    func loadTokens() async throws -> GoogleDriveTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CloudStorageError.keychainFailure(message: "Keychain 読み出し失敗 (status=\(status))")
        }
        return try JSONDecoder().decode(GoogleDriveTokens.self, from: data)
    }

    func saveTokens(_ tokens: GoogleDriveTokens) async throws {
        let data = try JSONEncoder().encode(tokens)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CloudStorageError.keychainFailure(message: "Keychain 書き込み失敗 (status=\(status))")
        }
    }

    func clearTokens() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudStorageError.keychainFailure(message: "Keychain 削除失敗 (status=\(status))")
        }
    }
}

/// `ASWebAuthenticationSession` を MainActor で起動する実装。
/// Sprint 5 ユニットテストでは触らない（jun さん側の実 OAuth 確認で動作検証）。
final class ASWebAuthGoogleDriveWebAuthRunner: NSObject, GoogleDriveWebAuthRunning, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    nonisolated override init() { super.init() }

    @MainActor
    func start(authURL: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                if let nsError = error as? NSError,
                   nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    continuation.resume(throwing: CloudStorageError.userCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: CloudStorageError.unknown(message: error.localizedDescription))
                    return
                }
                if let url = callbackURL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: CloudStorageError.unknown(message: "コールバック URL が空"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationPresentationContextProviding の要件は nonisolated。
        // ただし ASWebAuthenticationSession は本クラスを MainActor 上から `start` するため、
        // 実行時には常に MainActor 上で呼ばれる。MainActor.assumeIsolated で安全に
        // UIApplication.shared にアクセスする（Sprint 4 で確立したパターン）。
        MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else {
                preconditionFailure("OAuth フロー起動時に UIWindowScene が取得できない")
            }
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            // iOS 26: ASPresentationAnchor.init() / init(frame:) が deprecated のため
            // windowScene 経由で生成する。
            return ASPresentationAnchor(windowScene: scene)
        }
    }
}

/// PKCE ランダム値の本番実装（CryptoKit）。
struct LiveGoogleDrivePKCEGenerator: GoogleDrivePKCEGenerating {
    init() {}

    func generate() -> GoogleDrivePKCEPair {
        let verifier = Self.makeRandomString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        return GoogleDrivePKCEPair(codeVerifier: verifier, codeChallenge: challenge)
    }

    static func makeRandomString(length: Int) -> String {
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            allowed.randomElement(using: &generator)!
        })
    }

    static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
