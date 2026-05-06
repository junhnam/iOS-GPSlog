import SwiftUI

/// 設定画面（S3-001 / S3-002 / S3-004）。
///
/// 構造:
///   - 「自宅」セクション: 登録済みの自宅情報表示 + 登録/解除ボタン（S3-002）
///   - 「記録モード」セクション: 常時 / トリガーの Picker（S3-004）
///
/// アーキテクチャ:
///   - `AppSettings` を `@Bindable` で受け取り、UI 操作で直接プロパティを更新
///     → AppSettings 内の didSet が UserDefaults に書き戻す
///   - 自宅登録 UI は `HomeRegistrationView` をシート表示（S3-002 で詳細実装）
struct SettingsView: View {
    /// アプリ全体で共有される `AppSettings`。RootView から `@Environment` 経由で受け取る。
    @Bindable var settings: AppSettings

    /// 自宅登録シートの開閉状態。
    @State private var showingHomeRegistration: Bool = false

    var body: some View {
        Form {
            homeSection
            recordingModeSection
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
}

#Preview {
    NavigationStack {
        SettingsView(settings: AppSettings())
    }
}
