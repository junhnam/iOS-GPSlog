import SwiftUI

/// アプリ起動直後に表示されるルート画面。
///
/// 「地図 / 履歴 / 設定」の 3 タブ構成のナビゲーション骨格を提供する。
/// 各タブの中身は順次差し替えていく:
///   - 地図タブ: Sprint 1 で Dev-2 が `MapView`（Google Maps 経路表示）を実装済み
///   - 履歴タブ: Sprint 2 以降で本実装に差し替える
///   - 設定タブ: Sprint 3 以降で本実装に差し替える
struct RootView: View {
    /// `TabView` の選択状態。デフォルトは「地図」タブ（受け入れ条件: 起動時に地図タブが選択）。
    @State private var selectedTab: Tab = .map

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
                HistoryPlaceholderView()
                    .navigationTitle("履歴")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("履歴", systemImage: "clock")
            }
            .tag(Tab.history)
            .accessibilityLabel("履歴タブ")

            NavigationStack {
                SettingsPlaceholderView()
                    .navigationTitle("設定")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
            .tag(Tab.settings)
            .accessibilityLabel("設定タブ")
        }
    }

    /// タブ識別子。`@State` での選択状態保持と将来のディープリンク用。
    enum Tab: Hashable {
        case map
        case history
        case settings
    }
}

// MARK: - Tab Placeholders

/// 履歴タブのプレースホルダ。Sprint 2 以降で本実装する。
struct HistoryPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
            Text("履歴画面（Sprint 2 以降実装予定）")
                .font(.headline)
            Text("日付ごとの移動履歴・滞在ピンをここで一覧します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("履歴画面のプレースホルダ。Sprint 2 以降で実装予定。")
    }
}

/// 設定タブのプレースホルダ。Sprint 3 以降で本実装する。
struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
            Text("設定画面（Sprint 3 以降実装予定）")
                .font(.headline)
            Text("自宅登録 / 同期モード / クラウド連携などをここで設定します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("設定画面のプレースホルダ。Sprint 3 以降で実装予定。")
    }
}

#Preview {
    RootView()
}
