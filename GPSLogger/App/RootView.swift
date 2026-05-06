import SwiftUI
import SwiftData

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
    /// init で LocationService と同じインスタンスを共有させるため、宣言時の初期値は付けず
    /// `init()` 内で `State(initialValue:)` を使って生成する。
    @State private var appSettings: AppSettings

    /// アプリ全体で共有される位置情報サービス（S3-003 / S3-006 / S3-007 統合点）。
    /// MapView 内で生成すると、`@StateObject` のクロージャ初期化時点で
    /// `@Environment(AppSettings.self)` が利用できないため AppSettings / placeProvider が
    /// 注入できず、自宅判定 / SLC / お店情報取得が無効化される問題があった（QA-S3-001）。
    /// RootView 側でまとめて生成し、MapView へは引数で受け渡すことで本番経路でも
    /// 自宅判定・SLC・MKLocalSearch が機能するようにしている。
    @StateObject private var locationService: LocationService

    /// アプリ全体で共有される CalendarSyncService（S4-002 / S4-004）。
    /// SettingsView の「カレンダー同期」セクションと、S4-003 の滞留ピン → カレンダー
    /// イベント自動作成で同じインスタンスを共有する。
    @State private var calendarService: CalendarSyncService

    init() {
        let context = PersistenceController.shared.container.mainContext
        let repository = TripRepository(modelContext: context)
        // appSettings は @State の初期値と同じ値を別インスタンスで生成し LocationService へ DI。
        // ※ View の init で `_appSettings.wrappedValue` を直接読むのは保証されないため、
        //    RootView 用の AppSettings インスタンスを 1 つだけ作って両方に渡す。
        let settings = AppSettings()
        let calendar = CalendarSyncService(appSettings: settings)
        self._appSettings = State(initialValue: settings)
        self._calendarService = State(initialValue: calendar)
        self._locationService = StateObject(wrappedValue: LocationService(
            repository: repository,
            placeProvider: PlaceLookupService(),
            appSettings: settings,
            calendarSync: calendar
        ))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // 地図タブ: Dev-2 の MapView を埋め込む（Sprint 1 中に S1-006 / S1-007 で実装）。
            // 地図は SafeArea を含む全画面表示にしたいため、NavigationStack は使わず直接置く。
            MapView(locationService: locationService)
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
                SettingsView(
                    settings: appSettings,
                    calendarService: calendarService,
                    exportTodayTrip: { try await Self.exportTodayTrip() },
                    exportAllTrips: { try await Self.exportAllTrips() },
                    tripCount: { Self.persistedTripCount() }
                )
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

    // MARK: - Export hooks (S4-007 / 本番接続: S4-005 CSVExportService)

    /// 当日の TripRecord を CSV に書き出して URL を返す。
    /// 当日 trip が無ければ nil を返す（ExportView 側で「記録がまだありません」と通知）。
    @MainActor
    static func exportTodayTrip() async throws -> URL? {
        let context = PersistenceController.shared.container.mainContext
        let repository = TripRepository(modelContext: context)
        guard let trip = try repository.todayTrip(creatingIfMissing: false) else {
            return nil
        }
        return try CSVExportService().exportTripRecord(trip)
    }

    /// 永続化されている全 TripRecord を 1 ファイルにまとめて書き出して URL を返す。
    /// 0 件なら nil を返す。
    @MainActor
    static func exportAllTrips() async throws -> URL? {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<TripRecord>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let trips = (try? context.fetch(descriptor)) ?? []
        guard !trips.isEmpty else { return nil }
        return try CSVExportService().exportAllTrips(trips)
    }

    /// 永続化されている TripRecord 件数を返す（disabled 制御用）。
    @MainActor
    static func persistedTripCount() -> Int {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<TripRecord>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}

#Preview {
    RootView()
}
