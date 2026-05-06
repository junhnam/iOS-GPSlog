import SwiftUI

/// アプリ起動直後に表示されるルート画面。
///
/// 「地図 / 履歴 / 設定」の 3 タブ構成のナビゲーション骨格を提供する。
/// 各タブの中身は順次差し替えていく:
///   - 地図タブ: Sprint 1 で Dev-2 が `MapView`（Google Maps 経路表示）を実装済み
///   - 履歴タブ: Sprint 2（S2-008）で `HistoryListView` に差し替え済み
///   - 設定タブ: Sprint 3（S3-001 / S3-002 / S3-004）で `SettingsView` に差し替え済み
struct RootView: View {
    /// `TabView` の選択状態。デフォルトは「地図」タブ（受け入れ条件: 起動時に地図タブが選択）。
    @State private var selectedTab: Tab = .map

    /// アプリ全体で共有される設定オブジェクト（S3-001）。
    /// 子ビュー（MapView / SettingsView 等）から `@Environment(AppSettings.self)`
    /// で参照して挙動切り替えに使う。
    @State private var appSettings: AppSettings = AppSettings()

    var body: some View {
        TabView(selection: $selectedTab) {
            // 地図タブ: Dev-2 の MapView を埋め込む（Sprint 1 中に S1-006 / S1-007 で実装）。
            // 地図は SafeArea を含む全画面表示にしたいため、NavigationStack は使わず直接置く。
            MapView()
                .tabItem {
                    Label("地図", systemImage: "map")
                }
                .tag(Tab.map)
                .accessibilityLabel("地図タブ")

            NavigationStack {
                HistoryListView()
            }
            .tabItem {
                Label("履歴", systemImage: "clock")
            }
            .tag(Tab.history)
            .accessibilityLabel("履歴タブ")

            NavigationStack {
                SettingsView(settings: appSettings)
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
            .tag(Tab.settings)
            .accessibilityLabel("設定タブ")
        }
        .environment(appSettings)
    }

    /// タブ識別子。`@State` での選択状態保持と将来のディープリンク用。
    enum Tab: Hashable {
        case map
        case history
        case settings
    }
}

#Preview {
    RootView()
}
