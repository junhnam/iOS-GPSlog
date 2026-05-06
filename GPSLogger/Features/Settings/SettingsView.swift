import SwiftUI

/// 設定画面（S3-001 / S3-002 / S3-004 / S4-004 / S4-007 / S5-003 / S5-004）。
///
/// 構造:
///   - 「自宅」セクション: 登録済みの自宅情報表示 + 登録/解除ボタン（S3-002）
///   - 「記録モード」セクション: 常時 / トリガーの Picker（S3-004）
///   - 「カレンダー同期」セクション: 同期 ON/OFF + 対象カレンダー選択（S4-004）
///   - 「データ」セクション: クラウド同期先 + 自動同期 ON/OFF + エクスポート（S5-003/S5-004/S4-007）
///
/// アーキテクチャ:
///   - `AppSettings` を `@Bindable` で受け取り、UI 操作で直接プロパティを更新
///     → AppSettings 内の didSet が UserDefaults に書き戻す
///   - 自宅登録 UI は `HomeRegistrationView` をシート表示（S3-002 で詳細実装）
///   - カレンダー選択 UI は `CalendarPickerView` を NavigationLink で開く（S4-004）
///   - クラウド同期先 UI は `CloudStoragePickerView` を NavigationLink で開く（S5-003）
///   - エクスポート UI は `ExportView` を NavigationLink で開く（S4-007）
struct SettingsView: View {
    /// アプリ全体で共有される `AppSettings`。RootView から `@Environment` 経由で受け取る。
    @Bindable var settings: AppSettings

    /// CalendarSyncService を `@MainActor` プロパティとして注入（S4-004）。
    /// テスト時は CalendarProviderProtocol のフェイクを内包したサービスを差し込む。
    let calendarService: CalendarSyncService

    /// Google Drive 認証状態確認クロージャ（S5-003）。
    /// CloudStoragePickerView へ橋渡しする。テスト時はフェイクに差し替え可能。
    let isCloudProviderAuthenticated: @MainActor () async -> Bool

    /// クラウド認証フロー起動クロージャ（S5-003）。
    let authenticateCloudProvider: @MainActor (_ kind: CloudProviderKind) async throws -> Void

    /// クラウドサインアウトクロージャ（S5-003）。
    let signOutCloudProvider: @MainActor (_ kind: CloudProviderKind) -> Void

    /// 認証済みラベル取得クロージャ（S5-003）。
    let cloudAuthenticatedLabel: @MainActor (_ kind: CloudProviderKind) async -> String?

    /// 今日の TripRecord を CSV に書き出して URL を返すクロージャ（S4-007）。
    /// ExportView へ橋渡しする。
    let exportTodayTrip: @MainActor () async throws -> URL?

    /// 全期間の TripRecord を CSV に書き出して URL を返すクロージャ（S4-007）。
    let exportAllTrips: @MainActor () async throws -> URL?

    /// 永続化されている TripRecord の件数（S4-007: disabled 制御用）。
    let tripCount: @MainActor () -> Int

    /// 自宅登録シートの開閉状態。
    @State private var showingHomeRegistration: Bool = false

    /// カレンダー権限拒否時のアラート文言（S4-004）。nil = 表示しない。
    @State private var calendarPermissionAlert: String?

    /// 権限要求中の二重起動防止フラグ（S4-004）。
    @State private var isRequestingCalendarPermission: Bool = false

    var body: some View {
        Form {
            homeSection
            recordingModeSection
            calendarSyncSection
            dataSection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingHomeRegistration) {
            NavigationStack {
                HomeRegistrationView(settings: settings) {
                    showingHomeRegistration = false
                }
            }
        }
        .alert("カレンダー権限が必要です",
               isPresented: Binding(
                   get: { calendarPermissionAlert != nil },
                   set: { if !$0 { calendarPermissionAlert = nil } }
               ),
               actions: {
                   Button("OK", role: .cancel) { calendarPermissionAlert = nil }
               },
               message: {
                   if let message = calendarPermissionAlert {
                       Text(message)
                   }
               })
    }

    // MARK: - 自宅セクション（S3-002）

    @ViewBuilder
    private var homeSection: some View {
        Section {
            if let home = settings.homeLocation {
                // 登録済み: 住所 / 緯度経度 / 半径を表示
                if let address = home.address, !address.isEmpty {
                    LabeledContent("住所", value: address)
                } else {
                    LabeledContent("住所", value: "（未取得）")
                }
                LabeledContent("緯度経度",
                               value: String(format: "%.5f, %.5f", home.latitude, home.longitude))
                LabeledContent("半径",
                               value: String(format: "%.0f m", settings.homeRadiusMeters))

                Button("自宅を変更") {
                    showingHomeRegistration = true
                }
                Button("自宅を解除", role: .destructive) {
                    settings.homeLocation = nil
                }
            } else {
                // 未登録: 説明 + 登録ボタン
                Text("自宅を登録すると、自宅にいる間は GPS 記録を停止して電池を節約できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("自宅を登録") {
                    showingHomeRegistration = true
                }
            }
        } header: {
            Text("自宅")
        } footer: {
            Text("自宅判定の詳細は今後のスプリントで拡張されます。")
                .font(.footnote)
        }
    }

    // MARK: - 記録モードセクション（S3-004）

    @ViewBuilder
    private var recordingModeSection: some View {
        Section {
            Picker("記録モード", selection: $settings.recordingMode) {
                ForEach(RecordingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch settings.recordingMode {
                case .continuous:
                    Text("常にバックグラウンドで GPS を記録します。自宅にいる間は自動で停止します。")
                case .trigger:
                    Text("地図画面のフローティングボタンで開始/停止を切り替えます。")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("記録モード")
        }
    }

    // MARK: - カレンダー同期セクション（S4-004）

    @ViewBuilder
    private var calendarSyncSection: some View {
        Section {
            Toggle("カレンダー同期", isOn: $settings.calendarSyncEnabled)
                .accessibilityIdentifier("calendar_sync_toggle")
                .onChange(of: settings.calendarSyncEnabled) { _, newValue in
                    handleCalendarSyncToggle(turnedOn: newValue)
                }

            NavigationLink {
                CalendarPickerView(settings: settings,
                                   calendarService: calendarService)
            } label: {
                HStack {
                    Text("対象カレンダー")
                    Spacer()
                    Text(currentCalendarTitle)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .disabled(!settings.calendarSyncEnabled)
            .accessibilityIdentifier("calendar_picker_link")
        } header: {
            Text("カレンダー同期")
        } footer: {
            Text("ON にすると、滞留地点が自動で iOS のカレンダーに予定として記録されます。")
                .font(.footnote)
        }
    }

    /// `settings.calendarIdentifier` に対応する EKCalendar のタイトルを返す。
    /// 一覧から見つからない場合は「未選択」を返す。
    private var currentCalendarTitle: String {
        guard let identifier = settings.calendarIdentifier,
              !identifier.isEmpty else {
            return "未選択"
        }
        let calendars = calendarService.availableCalendars()
        if let match = calendars.first(where: { $0.calendarIdentifier == identifier }) {
            return match.title
        }
        return "未選択"
    }

    /// Toggle の onChange ハンドラ（S4-004）。
    /// ON 時は権限要求 → 拒否なら OFF に戻してアラート表示。
    /// OFF 時は何もしない（識別子は破棄しない）。
    private func handleCalendarSyncToggle(turnedOn: Bool) {
        guard turnedOn else { return }
        guard !isRequestingCalendarPermission else { return }
        isRequestingCalendarPermission = true
        Task { @MainActor in
            let granted = await calendarService.requestFullAccessIfNeeded()
            isRequestingCalendarPermission = false
            if !granted {
                // 拒否時は Toggle を OFF に戻し、アラートで設定アプリへ誘導する
                settings.calendarSyncEnabled = false
                calendarPermissionAlert =
                    "カレンダー権限が必要です。iOS の「設定」アプリから許可してください。"
            }
        }
    }

    // MARK: - データセクション（S4-007 / S5-003 / S5-004）

    @ViewBuilder
    private var dataSection: some View {
        Section {
            // S5-003: クラウド同期先選択（NavigationLink で CloudStoragePickerView を開く）
            NavigationLink {
                CloudStoragePickerView(
                    settings: settings,
                    isAuthenticated: isCloudProviderAuthenticated,
                    authenticate: authenticateCloudProvider,
                    signOut: signOutCloudProvider,
                    authenticatedLabel: cloudAuthenticatedLabel
                )
            } label: {
                HStack {
                    Text("クラウド同期先")
                    Spacer()
                    Text(settings.cloudProviderKind?.displayName ?? "なし")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .accessibilityIdentifier("cloud_provider_link")

            // S5-004: 自動同期 ON/OFF Toggle
            VStack(alignment: .leading, spacing: 4) {
                Toggle("自動同期", isOn: $settings.cloudAutoSyncEnabled)
                    .disabled(!cloudSyncToggleEnabled)
                    .accessibilityIdentifier("cloud_auto_sync_toggle")

                if !cloudSyncToggleEnabled {
                    Text("保存先を選択して認証してください")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cloud_auto_sync_help_text")
                }
            }

            // S4-007: エクスポート
            NavigationLink {
                ExportView(exportTodayTrip: exportTodayTrip,
                           exportAllTrips: exportAllTrips,
                           tripCount: tripCount)
            } label: {
                HStack {
                    Text("エクスポート")
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("export_link")
        } header: {
            Text("データ")
        } footer: {
            Text("CSV ファイルとして書き出し、iCloud Drive 等に保存できます。")
                .font(.footnote)
        }
    }

    /// 自動同期 Toggle が有効かどうかの判定。
    /// cloudProviderKind が選択されていることを条件とする（認証状態は CloudStoragePickerView 側で管理）。
    /// S5-004: 「プロバイダ未選択時は Toggle を disable」の受け入れ条件に対応。
    private var cloudSyncToggleEnabled: Bool {
        settings.cloudProviderKind != nil
    }
}

#Preview {
    let settings = AppSettings()
    return NavigationStack {
        SettingsView(
            settings: settings,
            calendarService: CalendarSyncService(appSettings: settings),
            isCloudProviderAuthenticated: { false },
            authenticateCloudProvider: { _ in },
            signOutCloudProvider: { _ in },
            cloudAuthenticatedLabel: { _ in nil },
            exportTodayTrip: { nil },
            exportAllTrips: { nil },
            tripCount: { 0 }
        )
    }
}
