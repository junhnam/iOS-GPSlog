import SwiftUI

/// クラウド保存先の選択と認証を行う画面（S5-003）。
///
/// 役割:
///   - 「なし」「Google Drive」の選択肢を Picker で提供（Sprint 5。Dropbox は Sprint 6）
///   - Google Drive を選択すると `authenticate` クロージャを起動
///   - 認証済みの場合はアカウント情報（サインイン済み表示）を表示
///   - 「なし」を選択すると `signOut` クロージャでトークンを破棄
///   - 認証中は ProgressView で操作を disable
///
/// 設計判断（S4-007 ExportView と同パターン）:
///   - 依存を `@MainActor` クロージャとして注入しテスタビリティを確保
///   - `AppSettings` は `@Bindable` で受け取り、Picker の変更で `cloudProviderKind` を更新
///   - 認証フローは注入された `authenticate` クロージャに委譲し、View は状態表示に徹する
struct CloudStoragePickerView: View {
    /// アプリ全体の設定（S5-003）。クラウド保存先を読み書きする。
    @Bindable var settings: AppSettings

    /// Google Drive の認証状態を確認するクロージャ（テスト時にフェイクに差し替え可能）。
    let isAuthenticated: @MainActor () async -> Bool

    /// 認証フローを起動するクロージャ。認証成功なら true, キャンセル / 失敗なら false。
    let authenticate: @MainActor (_ kind: CloudProviderKind) async throws -> Void

    /// サインアウト処理クロージャ。Keychain のトークンを破棄する。
    let signOut: @MainActor (_ kind: CloudProviderKind) -> Void

    /// 認証済みアカウント情報の表示文字列（サービス名のみ、Sprint 5 ではメール非表示）。
    let authenticatedLabel: @MainActor (_ kind: CloudProviderKind) async -> String?

    /// 認証中フラグ（ProgressView + disable 制御）。
    @State private var isAuthenticating: Bool = false

    /// 認証エラーのアラート文言。nil = 表示しない。
    @State private var authErrorMessage: String?

    /// 認証済み状態のキャッシュ（onAppear / onChange で更新）。
    @State private var isCurrentlyAuthenticated: Bool = false

    /// 認証済みアカウントラベルのキャッシュ。
    @State private var currentAuthLabel: String?

    var body: some View {
        Form {
            Section {
                // Sprint 5: Google Drive のみ（Dropbox は Sprint 6）
                Picker("クラウド同期先", selection: cloudProviderBinding) {
                    Text("なし").tag(Optional<CloudProviderKind>.none)
                    Text(CloudProviderKind.googleDrive.displayName)
                        .tag(Optional<CloudProviderKind>.some(.googleDrive))
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("cloud_provider_picker")

                // 認証状態の表示
                if let kind = settings.cloudProviderKind {
                    if isAuthenticating {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("認証中...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if isCurrentlyAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(currentAuthLabel ?? "\(kind.displayName) にサインイン済み")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("cloud_auth_status_label")

                        Button("サインアウト", role: .destructive) {
                            handleSignOut(kind: kind)
                        }
                        .accessibilityIdentifier("cloud_sign_out_button")
                    } else {
                        Button("\(kind.displayName) にサインイン") {
                            handleAuthenticate(kind: kind)
                        }
                        .disabled(isAuthenticating)
                        .accessibilityIdentifier("cloud_sign_in_button")
                    }
                }
            } header: {
                Text("クラウド同期先")
            } footer: {
                if settings.cloudProviderKind == nil {
                    Text("クラウドへの自動同期を行う場合は保存先を選択して認証してください。")
                        .font(.footnote)
                } else if !isCurrentlyAuthenticated && !isAuthenticating {
                    Text("「サインイン」ボタンを押して認証を完了してください。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("クラウド同期先")
        .navigationBarTitleDisplayMode(.inline)
        .alert("認証エラー",
               isPresented: Binding(
                   get: { authErrorMessage != nil },
                   set: { if !$0 { authErrorMessage = nil } }
               ),
               actions: {
                   Button("OK", role: .cancel) { authErrorMessage = nil }
               },
               message: {
                   if let message = authErrorMessage {
                       Text(message)
                   }
               })
        .onAppear {
            refreshAuthState()
        }
        .onChange(of: settings.cloudProviderKind) { _, _ in
            refreshAuthState()
        }
    }

    // MARK: - Picker binding（Optional<CloudProviderKind>）

    /// `Picker` は `Optional<CloudProviderKind>` でバインドするが、`@Bindable var settings` の
    /// `cloudProviderKind` は `CloudProviderKind?` なので直接バインドできる。
    /// ただし変更時に認証処理を発火させる必要があるため、カスタム Binding を定義する。
    private var cloudProviderBinding: Binding<CloudProviderKind?> {
        Binding(
            get: { settings.cloudProviderKind },
            set: { newKind in
                let oldKind = settings.cloudProviderKind
                settings.cloudProviderKind = newKind

                if let newKind {
                    // 新しいプロバイダが選ばれた場合 → 未認証なら認証開始
                    if oldKind != newKind {
                        handleAuthenticate(kind: newKind)
                    }
                } else {
                    // 「なし」が選ばれた場合 → サインアウト
                    if let oldKind {
                        handleSignOut(kind: oldKind)
                    }
                }
            }
        )
    }

    // MARK: - Handlers

    private func handleAuthenticate(kind: CloudProviderKind) {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                try await authenticate(kind)
                await refreshAuthStateAsync()
            } catch let error as CloudStorageError {
                // ユーザーがキャンセルした場合はエラーアラートを出さない
                if error != .userCancelled {
                    authErrorMessage = errorMessage(for: error)
                }
                // 認証失敗時は保存先を nil に戻す
                settings.cloudProviderKind = nil
                isCurrentlyAuthenticated = false
            } catch {
                authErrorMessage = "認証に失敗しました: \(error.localizedDescription)"
                settings.cloudProviderKind = nil
                isCurrentlyAuthenticated = false
            }
        }
    }

    private func handleSignOut(kind: CloudProviderKind) {
        signOut(kind)
        isCurrentlyAuthenticated = false
        currentAuthLabel = nil
    }

    private func refreshAuthState() {
        Task { @MainActor in
            await refreshAuthStateAsync()
        }
    }

    private func refreshAuthStateAsync() async {
        guard let kind = settings.cloudProviderKind else {
            isCurrentlyAuthenticated = false
            currentAuthLabel = nil
            return
        }
        isCurrentlyAuthenticated = await isAuthenticated()
        if isCurrentlyAuthenticated {
            currentAuthLabel = await authenticatedLabel(kind)
        } else {
            currentAuthLabel = nil
        }
    }

    // MARK: - Error messages

    private func errorMessage(for error: CloudStorageError) -> String {
        switch error {
        case .notAuthenticated:
            return "認証情報がありません。再度サインインしてください。"
        case .authenticationExpired:
            return "認証の有効期限が切れました。再度サインインしてください。"
        case .userCancelled:
            return "認証がキャンセルされました。"
        case .networkFailure(let message):
            return "ネットワークエラー: \(message)"
        case .apiError(let code, let message):
            return "API エラー (\(code)): \(message)"
        case .keychainFailure(let message):
            return "Keychain エラー: \(message)"
        case .unknown(let message):
            return "エラー: \(message)"
        }
    }
}

#Preview {
    let settings = AppSettings()
    return NavigationStack {
        CloudStoragePickerView(
            settings: settings,
            isAuthenticated: { false },
            authenticate: { _ in },
            signOut: { _ in },
            authenticatedLabel: { kind in "\(kind.displayName) アカウント" }
        )
    }
}
