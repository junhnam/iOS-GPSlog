import Foundation

/// クラウドストレージへの CSV アップロードを表す共通プロトコル（S5-001 / S5-002 / S5-005）。
///
/// Sprint 5 では Google Drive のみ実装する（jun さん承認 2026-05-06、Dropbox は Sprint 6 へ繰越）。
/// Sprint 6 で Dropbox を追加する際、本プロトコルを実装した `DropboxSyncService` を追加するだけで
/// CloudUploadCoordinator から差し替え可能になる設計（戦略パターン）。
///
/// 設計判断:
///   - actor / Sendable 構造体で実装することを推奨（バックグラウンド I/O 前提）
///   - 認証トークンの永続化は実装側で Keychain を使う
///   - 認証フローの起動は MainActor 必須なので `authenticate()` だけ MainActor isolation 不要
///     になるよう本プロトコルは `Sendable` ベースに保ち、UI は呼び出し側で `await MainActor.run { }` で吸収する
///
/// ファイルパス（toPath:）の規約:
///   - `GPSログ/{YYYY-MM-DD}/data.csv` のような階層パスを `/` 区切りで指定する
///   - フォルダが存在しない場合は実装側で作成すること（Drive / Dropbox とも API がある）
///   - 同一パスに既にファイルがある場合は上書きすること（同日内で複数回記録停止する想定）
protocol CloudStorageProvider: Sendable {
    /// プロバイダ識別子（CloudProviderKind との対応）。
    var kind: CloudProviderKind { get }

    /// 現在認証済みかどうか。Keychain にトークンが保存されている状態を指す。
    /// UI 表示（「Google Drive にサインイン中」「サインアウト」ボタン制御）に使う。
    @MainActor
    func isAuthenticated() async -> Bool

    /// OAuth 認証フローを開始し、成功すればトークンを Keychain に保存する。
    /// 失敗時は `CloudStorageError` を throw する。
    /// UI から `.fullScreenCover` などで起動する想定のため MainActor isolation。
    @MainActor
    func authenticate() async throws

    /// 認証情報を破棄する（Keychain クリア）。
    /// 通信は伴わない（OAuth サーバ側のトークン取り消しは Sprint 6 で検討）。
    @MainActor
    func signOut()

    /// 指定パスに CSV データをアップロードする。
    /// - 認証期限切れの場合は実装側でリフレッシュを試み、失敗したら
    ///   `.authenticationExpired` を throw（呼び出し側で再認証を促す）
    /// - ネットワーク失敗・API エラーは `.networkFailure` / `.apiError` を throw
    /// - 成功時は `CloudUploadResult`（ファイル ID / パス）を返す
    func uploadCSV(_ data: Data, toPath path: String) async throws -> CloudUploadResult
}

/// クラウドアップロード結果（S5-001 / S5-005）。
///
/// 実装側（Google Drive / Dropbox）で取得できる識別子・URL を共通形に詰めて返す。
/// Sprint 5 では返り値を直接使う箇所はないが、ログ出力 / 将来の「アップロード先を開く」UI で
/// `webViewLink` を使う想定。
struct CloudUploadResult: Sendable, Equatable {
    /// プロバイダ側のファイル ID（Drive: fileId / Dropbox: id）
    let fileID: String
    /// プロバイダ側のフルパス（`GPSログ/2026-05-06/data.csv` 等）
    let path: String
    /// Web で開くための URL（オプション。Drive の `webViewLink` 等）
    let webViewLink: URL?

    init(fileID: String, path: String, webViewLink: URL?) {
        self.fileID = fileID
        self.path = path
        self.webViewLink = webViewLink
    }
}

/// クラウドアップロード時のエラー（S5-001 / S5-005 / S5-006）。
///
/// `Sendable` で値型として伝搬。CloudUploadCoordinator (S5-005) と
/// CloudUploadRetryQueue (S5-006) が本 enum をハンドルしてリトライ判定に使う。
enum CloudStorageError: Error, Sendable, Equatable {
    /// 未認証（authenticate を呼んでいない、Keychain クリア済み）。
    case notAuthenticated
    /// 認証期限切れ。リフレッシュも失敗（再認証が必要）。
    case authenticationExpired
    /// ユーザーが OAuth 画面で拒否した。
    case userCancelled
    /// ネットワーク到達不可（オフライン等）。リトライ対象。
    case networkFailure(message: String)
    /// プロバイダ API エラー（HTTP 4xx / 5xx）。
    case apiError(statusCode: Int, message: String)
    /// 認証情報の Keychain 保存・読み出し失敗。
    case keychainFailure(message: String)
    /// 想定外のエラー（パース失敗等）。
    case unknown(message: String)

    static func == (lhs: CloudStorageError, rhs: CloudStorageError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated): return true
        case (.authenticationExpired, .authenticationExpired): return true
        case (.userCancelled, .userCancelled): return true
        case (.networkFailure(let l), .networkFailure(let r)): return l == r
        case (.apiError(let lc, let lm), .apiError(let rc, let rm)): return lc == rc && lm == rm
        case (.keychainFailure(let l), .keychainFailure(let r)): return l == r
        case (.unknown(let l), .unknown(let r)): return l == r
        default: return false
        }
    }

    /// リトライキュー（S5-006）でリトライ対象とすべきエラーかを判定する。
    /// ネットワーク失敗 / 5xx は再試行で回復する可能性があるため true。
    /// ユーザー操作（拒否）や認証エラーは再試行不要のため false。
    var isRetryable: Bool {
        switch self {
        case .networkFailure: return true
        case .apiError(let statusCode, _): return statusCode >= 500
        case .notAuthenticated, .authenticationExpired, .userCancelled,
             .keychainFailure, .unknown:
            return false
        }
    }
}
