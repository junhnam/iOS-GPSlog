import SwiftUI
import SwiftData

/// アプリ起動直後に表示されるルート画面。
///
/// 「地図 / 履歴 / 設定」の 3 タブ構成のナビゲーション骨格を提供する。
/// 各タブの中身は順次差し替えていく:
///   - 地図タブ: Sprint 1 で Dev-2 が `MapView`（Google Maps 経路表示）を実装済み
///   - 履歴タブ: Sprint 2（S2-008）で `HistoryListView` に差し替え済み
///   - 設定タブ: Sprint 3（S3-001 / S3-002 / S3-004）で `SettingsView` に差し替え済み
///   - クラウド同期先 / 自動同期 UI: Sprint 5（S5-003 / S5-004）で `CloudStoragePickerView` に差し替え済み
///
/// S6-002: 依存の組立は `AppDependencyContainer` に委譲する。
/// RootView は Container を `let` で保持し、各サービスへのアクセスを Container 経由に統一する。
struct RootView: View {
    /// `TabView` の選択状態。デフォルトは「地図」タブ（受け入れ条件: 起動時に地図タブが選択）。
    @State private var selectedTab: Tab = .map

    /// scenePhase: アプリがフォアグラウンドに復帰したとき（.active）にバックグラウンド
    /// 復帰経路（resumeTrackingAfterRelaunch）を発火させるために監視する（S6-006）。
    @Environment(\.scenePhase) private var scenePhase

    /// アプリ全体の依存を保持する DIコンテナ（S6-002）。
    /// 組立処理は AppDependencyContainer に集約し、RootView は取り出すだけにする。
    private let dependencies: AppDependencyContainer

    /// アプリ全体で共有される設定オブジェクト。
    /// Container から取り出して @State で保持し、SwiftUI の環境に流す。
    @State private var appSettings: AppSettings

    /// アプリ全体で共有される位置情報サービス（S3-003 / S3-006 / S3-007 統合点）。
    @StateObject private var locationService: LocationService

    /// アプリ全体で共有される CalendarSyncService（S4-002 / S4-004）。
    @State private var calendarService: CalendarSyncService

    // MARK: - Init

    /// テスト / プレビュー用イニシャライザ。任意の Container を差し込める（S6-002）。
    ///
    /// 本番経路は `GPSLoggerApp` が `AppDependencyContainer()` を `@State` で保持して渡す。
    /// `#Preview` 等で引数なしで使う場合は `@MainActor` が保証されたコンテキストで呼ぶこと。
    init(dependencies: AppDependencyContainer) {
        self.dependencies = dependencies
        self._appSettings = State(initialValue: dependencies.appSettings)
        self._calendarService = State(initialValue: dependencies.calendarService)
        self._locationService = StateObject(wrappedValue: dependencies.locationService)
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
                    // S5-003: Google Drive の認証クロージャ群を注入。
                    // googleDriveService は actor なので await で呼び出す。
                    isCloudProviderAuthenticated: { [googleDriveService = dependencies.googleDriveService] in
                        await googleDriveService.isAuthenticated()
                    },
                    authenticateCloudProvider: { [googleDriveService = dependencies.googleDriveService] _ in
                        try await googleDriveService.authenticate()
                    },
                    signOutCloudProvider: { [googleDriveService = dependencies.googleDriveService] _ in
                        googleDriveService.signOut()
                    },
                    cloudAuthenticatedLabel: { kind in
                        kind.displayName + " にサインイン済み"
                    },
                    exportTodayTrip: { try await Self.exportTodayTrip() },
                    exportAllTrips: { try await Self.exportAllTrips() },
                    tripCount: { Self.persistedTripCount() },
                    // S6-003: DB クリア画面で使用する TripRepository を注入。
                    tripRepository: dependencies.repository
                )
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
            .tag(Tab.settings)
            .accessibilityLabel("設定タブ")
        }
        .environment(appSettings)
        // QA-S5-001: クラウドリトライキューの自動処理 + ネットワーク回復監視を起動。
        // - 起動時に未送信分（前回起動時に失敗したもの）を 1 度処理
        // - ネットワーク回復イベントで自動再試行
        // task は MainActor で実行されるため、CloudUploadRetryQueue の MainActor 隔離と整合する。
        .task { [retryQueue = dependencies.cloudUploadRetryQueue] in
            _ = try? await retryQueue.processOnAppLaunch()
            retryQueue.startObservingNetwork()
        }
        // S6-010 B 案: アプリ起動時に後追い滞留検知を一度実行する。
        // タスクキル → 手動再起動のシナリオで、SLC 起床を経ずに起動した場合でも
        // DB に記録済みの RoutePoint からピン化漏れを救える。
        // resumeTrackingAfterRelaunch でも発火するが、冪等性ガードにより重複ピンは作られない。
        .task { [locationService] in
            locationService.runRetroactiveStayDetectionOnLaunch()
        }
        // S6-006: scenePhase が .active になったとき（フォアグラウンド復帰 /
        // SLC 起床後の applicationDidBecomeActive 相当）に前回の記録状態を復元する。
        // kill 後の SLC 起床でも ScenePhase.active が発火するため、
        // applicationDidBecomeActive 通知を個別に購読する必要はない。
        // .onChange クロージャは @MainActor で実行されるため、
        // @MainActor 隔離の LocationService を直接参照できる。
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                locationService.resumeTrackingAfterRelaunch()
            }
        }
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
    // #Preview マクロは @MainActor コンテキストで評価されるため、
    // AppDependencyContainer() の生成（@MainActor 必須）が安全に呼べる。
    RootView(dependencies: AppDependencyContainer())
}
