import Foundation
import CoreLocation
import Combine
import os

/// CLLocationManager の最小限のインタフェース（S3-006）。
///
/// SLC（Significant Location Changes）切替・desiredAccuracy 動的調整をテスト可能にするため、
/// 利用するメソッド・プロパティだけを抽出してプロトコル化する。
///
/// 本物の CLLocationManager はこのプロトコルにそのまま適合する（拡張で実装）。
/// テストではモッククラスを差し替え、SLC のオン/オフや desiredAccuracy の変化を検証する。
protocol LocationProviderProtocol: AnyObject {
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var activityType: CLActivityType { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var showsBackgroundLocationIndicator: Bool { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var delegate: CLLocationManagerDelegate? { get set }

    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
}

extension CLLocationManager: LocationProviderProtocol {}

/// アプリ全体で共有される位置情報サービス。
///
/// Core Location を SwiftUI から扱いやすいよう `ObservableObject` でラップする。
/// 現在地表示（S1-006）と経路描画（S1-007）から購読される。
///
/// Sprint 2 拡張（S2-005）:
///   - `TripRepository` を DI で受け取り、新規座標を当日の TripRecord に永続化する
///   - 直前点との距離を `TripDistanceCalculator` で算出し、5m 以上のときだけ DB に書き込む
///   - 距離は `TripRepository.updateTotalDistance` で TripRecord に加算
///   - 日付またぎ時は新しい TripRecord に切り替える
///   - `repository` 未注入時はメモリのみで従来通り動作（後方互換）
///
/// バッテリー消費対策（CLAUDE.md の懸念に対応する Sprint 1 時点の措置）:
///   - `distanceFilter = 10`（10m 以内の動きは無視）
///   - `pausesLocationUpdatesAutomatically = true`（停止検知時に OS が自動で更新を一時停止）
///   - `activityType = .automotiveNavigation`（車移動主体のため）
///   - 高度な動的精度調整・Significant Location Changes API 併用は Sprint 6 で実施
@MainActor
final class LocationService: NSObject, ObservableObject {
    /// 直近の位置情報。地図カメラ追従などに使う。
    @Published private(set) var currentLocation: CLLocation?

    /// 経路描画用の位置情報配列。S1-007 から購読される。
    /// アプリ再起動時にリセットされる（DB 永続化は Sprint 2 で別途 RestoreService が担当）。
    @Published private(set) var route: [CLLocation] = []

    /// OS の権限状態。UI 側で「設定アプリへ誘導」等の判断に使う。
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    /// 位置情報更新が現在オンかどうか（外部から状態確認用）。
    @Published private(set) var isUpdating: Bool = false

    private let manager: any LocationProviderProtocol

    /// SLC（Significant Location Changes）が現在オンかどうか（S3-006）。
    /// テストや UI から状態確認できるよう公開しているが書き込みは内部のみ。
    @Published private(set) var isMonitoringSignificantChanges: Bool = false

    /// 走行 / 停止判定のために直近 RoutePoint 履歴を保持する（S3-006）。
    /// 受け入れ条件: 「走行中（5 秒以内に 10m 超移動）= Best」「停止/低速（20 秒以上ほぼ動かず）= HundredMeters」
    /// 履歴は最大 5 件まで保持（メモリ圧縮）。
    private var recentLocationHistory: [CLLocation] = []

    /// バッテリー適応ポリシー（S6-005）。
    /// ステートレスな Sendable 構造体のため LocationService 内部で生成する。
    private let batteryPolicy = BatteryAdaptiveLocationPolicy()

    /// バッテリーポリシー評価用の直近位置履歴（S6-005）。
    /// Sprint 3 の recentLocationHistory（最大 5 件）とは別に保持する。
    /// 5 分ウィンドウをカバーするため最大 60 件（概ね 5 秒間隔で 5 分分）まで保持する。
    private var batteryPolicyLocationHistory: [CLLocation] = []

    /// バッテリーポリシー履歴の最大保持件数。
    private static let batteryPolicyHistoryLimit: Int = 60

    /// 直近のバッテリーポリシー決定（distanceFilter 切替の重複適用を防ぐ）。
    /// 初期値は .driving として、configureManager() の distanceFilter=10 と整合させる。
    /// 最初に停車判定が来たとき必ず distanceFilter=100 への切替が発火するよう、
    /// 停車状態の決定値は初期値に使わない。
    private var lastBatteryPolicyDecision: BatteryAdaptiveLocationPolicy.Decision = .driving(
        accuracy: BatteryAdaptiveLocationPolicy.drivingAccuracy,
        distanceFilter: BatteryAdaptiveLocationPolicy.drivingDistanceFilter
    )

    /// 直近の動的 desiredAccuracy 値（テスト用に観測可能にする）。
    /// 本来は manager.desiredAccuracy を直接読めば良いが、CLLocationAccuracy は
    /// Double 型のため `==` 比較で精度問題が出ないよう、内部で抽象的な enum で保持する。
    enum DynamicAccuracy: String, Sendable {
        case best
        case hundredMeters
    }
    @Published private(set) var dynamicAccuracy: DynamicAccuracy = .best

    /// DB 永続化用リポジトリ（DI 可能、デフォルト nil）。
    /// nil の場合はメモリのみで動作（テスト・後方互換）。
    private let repository: TripRepository?

    /// 現在書き込み対象になっている TripRecord（当日のレコード）。
    /// 日付がまたいだら appendRoutePoint 前に切り替える。
    private var currentTrip: TripRecord?

    /// 滞留検出器（S2-006）。10 分以上同じ場所に居たら PinRecord を作成する。
    /// テスト互換のため外部から差し替え可能（DI）にしておく。
    private let stayDetector: StayDetector

    /// お店情報取得サービス（S3-007）。PinRecord 確定直後に MKLocalSearch を呼び、
    /// placeName / placeURL を書き戻す。nil のときは取得処理をスキップ（後方互換）。
    private let placeProvider: (any PlaceProviderProtocol)?

    /// アプリ設定（S3-003）。自宅判定 / 半径の参照に使う。
    /// nil のときは自宅機能を無効化（後方互換）。
    private let appSettings: AppSettings?

    /// カレンダー同期サービス（S4-003）。
    /// PinRecord 作成後（PlaceLookupService の placeName 書き戻し完了後）に
    /// `createEvent(for:)` を呼んでカレンダーイベントを作成する。
    /// nil のときはカレンダー連携を無効化（後方互換）。
    private let calendarSync: CalendarSyncService?

    /// クラウドアップロード Coordinator（S5-005）。
    /// 記録停止時に CSV をクラウドへ自動アップロードする。
    /// nil のときはクラウド連携を無効化（後方互換）。
    private let cloudUploadCoordinator: CloudUploadCoordinator?

    /// DB 自動消去サービス（S6-004）。
    /// 記録停止時に容量をチェックし、しきい値超過で古い TripRecord を削除する。
    /// nil のときは自動消去を無効化（後方互換 / テスト時は nil 可）。
    private let databaseAutoCleanup: DatabaseAutoCleanupService?

    /// 直近の自宅判定状態（S3-003）。状態遷移時のみログを出すため保持。
    /// 初期値は `.unknown`（自宅未登録または最初の点が未到着）。
    private var lastHomeState: HomeState = .unknown

    /// 自宅滞在中に記録をスキップしている件数（テスト用観測値）。
    /// 本番ロジックには影響しないが、QA・テストで「自宅で何点スキップしたか」を確認するために公開する。
    @Published private(set) var atHomeSkipCount: Int = 0

    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "LocationService")

    /// DB 書き込み判定のしきい値（m）。直前点との距離がこれ以上のときだけ永続化する。
    /// 受け入れ条件: 「5m 以上なら appendRoutePoint で永続化」。
    private static let dbWriteThresholdMeters: Double = 5.0

    /// 後追い滞留検知サービス（S6-010 B 案）。
    /// アプリ起動時 / SLC 起床時 / scenePhase 復帰時に過去の RoutePoint を走査して
    /// 滞留区間を後追いで検知し、PinRecord を生成する。
    /// nil のときは後追い検知を無効化（テスト・後方互換）。
    private let retroactiveStayDetector: RetroactiveStayDetector?

    init(manager: any LocationProviderProtocol = CLLocationManager(),
         repository: TripRepository? = nil,
         stayDetector: StayDetector = StayDetector(),
         retroactiveStayDetector: RetroactiveStayDetector? = RetroactiveStayDetector(),
         placeProvider: (any PlaceProviderProtocol)? = nil,
         appSettings: AppSettings? = nil,
         calendarSync: CalendarSyncService? = nil,
         cloudUploadCoordinator: CloudUploadCoordinator? = nil,
         databaseAutoCleanup: DatabaseAutoCleanupService? = nil) {
        self.manager = manager
        self.repository = repository
        self.stayDetector = stayDetector
        self.retroactiveStayDetector = retroactiveStayDetector
        self.placeProvider = placeProvider
        self.appSettings = appSettings
        self.calendarSync = calendarSync
        self.cloudUploadCoordinator = cloudUploadCoordinator
        self.databaseAutoCleanup = databaseAutoCleanup
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        configureManager()
    }

    private func configureManager() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        // バックグラウンド更新は Info.plist の UIBackgroundModes と整合済み（S1-003）
        manager.allowsBackgroundLocationUpdates = true
        // 起動直後にバックグラウンドで止まらないよう、初期は false。
        // 実運用で start するタイミングで OS が判断する。
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Authorization

    /// アプリ使用中のみ許可をリクエストする（最初のダイアログ）。
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// 常時許可をリクエストする。
    /// iOS の仕様上、まず WhenInUse を取得してから Always を求める二段階になる。
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Updates

    func startUpdatingLocation() {
        guard !isUpdating else { return }
        manager.startUpdatingLocation()
        isUpdating = true
        // S6-006: 記録開始時に wasTracking を true に書き込む（kill 後の復帰判定用）。
        appSettings?.wasTracking = true
    }

    func stopUpdatingLocation() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
        // S6-006: 意図的な記録停止なので wasTracking を false にリセットする。
        // kill 後の SLC 起床時にこの false を見て自動再開しないよう制御する。
        appSettings?.wasTracking = false
        // S5-005: 記録停止時にクラウド自動アップロードをトリガー。
        // 自動同期 OFF / プロバイダ未選択時は CloudUploadCoordinator が no-op に倒すため
        // ここでは設定をチェックせず、Coordinator に判断を委ねる。
        triggerCloudUploadIfNeeded()
        // S6-004: 記録停止時に DB 自動消去をチェック。
        // Toggle OFF / サービス未注入時は DatabaseAutoCleanupService 内部で no-op に倒す。
        triggerDatabaseAutoCleanupIfNeeded()
    }

    /// 現在の TripRecord に対してクラウド自動アップロードを試みる（S5-005）。
    /// CloudUploadCoordinator 未注入 / currentTrip 未確定時は no-op。
    /// 失敗してもログのみで UI は止めない。
    private func triggerCloudUploadIfNeeded() {
        guard let coordinator = cloudUploadCoordinator else { return }
        guard let trip = currentTrip else { return }
        // SwiftData の @Model（TripRecord）は MainActor 隔離のため、
        // Task の継承された isolation（@MainActor）を維持する。
        Task { @MainActor [weak self] in
            _ = await coordinator.uploadIfEnabled(for: trip)
            _ = self
        }
    }

    /// DB 自動消去をトリガーする（S6-004）。
    /// DatabaseAutoCleanupService 未注入時は no-op。
    /// Toggle OFF 時は DatabaseAutoCleanupService 内部で即 return するため、
    /// ここではサービスの存在チェックのみ行う。
    /// 失敗してもログのみで UI は止めない（バッテリー対策の一環として非同期 Task で実行）。
    private func triggerDatabaseAutoCleanupIfNeeded() {
        guard let cleanup = databaseAutoCleanup else { return }
        Task { @MainActor [weak self] in
            do {
                try cleanup.cleanup()
            } catch {
                Self.logger.warning("DB 自動消去失敗: \(error.localizedDescription)")
            }
            _ = self
        }
    }

    // MARK: - Significant Location Changes（S3-006）

    /// SLC（Significant Location Changes）モニタリングを開始する。
    /// 自宅滞在中はこちらに切り替え、通常の startUpdatingLocation を停止する（電池節約）。
    /// 自宅未登録（appSettings.homeLocation == nil）の場合は何もしない。
    func startSignificantChangesIfHome() {
        guard let settings = appSettings, settings.homeLocation != nil else { return }
        guard !isMonitoringSignificantChanges else { return }
        // 通常 GPS は停止
        if isUpdating {
            manager.stopUpdatingLocation()
            isUpdating = false
        }
        manager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = true
        Self.logger.info("SLC 開始（自宅滞在中の省電力モード）")
    }

    /// SLC モニタリングを停止する。
    /// 自宅退出時に呼ばれ、通常 GPS の startUpdatingLocation に戻すフローで使う。
    func stopSignificantChanges() {
        guard isMonitoringSignificantChanges else { return }
        manager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = false
        Self.logger.info("SLC 停止")
    }

    // MARK: - Background Resume（S6-006）

    /// SLC デリゲートから呼ぶ専用経路（S6-006）。
    ///
    /// OS がアプリを kill した後、SLC（Significant Location Changes）で起床した際に
    /// `CLLocationManagerDelegate.locationManager(_:didUpdateLocations:)` が呼ばれる。
    /// そのデリゲートハンドラから本メソッドを呼び、位置情報を処理させる。
    ///
    /// 通常の `handleNewLocations` との違い:
    ///   - SLC 起床直後は isMonitoringSignificantChanges が false になっている場合があるため
    ///     フラグを立て直す
    ///   - 自宅判定は通常フローと同様に `handleNewLocations` 内で行われる
    ///
    /// 実装注: 現時点では `handleNewLocations` を呼ぶだけだが、
    /// 将来的に SLC 専用の処理（ログ分類等）を挟む拡張点として独立させておく。
    func startTrackingFromSLC() {
        // SLC で起床した場合、isMonitoringSignificantChanges を true に同期し直す。
        // （kill 後の再起動では状態がリセットされているため）
        if !isMonitoringSignificantChanges {
            isMonitoringSignificantChanges = true
            Self.logger.info("SLC 起床: isMonitoringSignificantChanges を true に同期")
        }
        // 通常 GPS 更新の状態はそのまま。wasTracking 評価は resumeTrackingAfterRelaunch で行う。
    }

    /// バックグラウンド復帰時に前回の記録状態を復元する（S6-006）。
    ///
    /// `scenePhase == .active`（applicationDidBecomeActive 相当）時と
    /// SLC 起床時の両方から呼ばれることを想定する。
    ///
    /// 挙動:
    ///   1. `appSettings.wasTracking == false` なら何もしない（意図的な停止 / 初回起動）
    ///   2. 自宅判定が有効で `.atHome` なら記録を再開しない
    ///   3. 上記に該当しない場合、日付またぎを処理したうえで `startUpdatingLocation()` を呼ぶ
    ///
    /// 日付またぎ処理:
    ///   - `currentTrip` が前日（または未設定）なら、`TripRepository.todayTrip()` で
    ///     当日の TripRecord を確保し直す。これは `persistLocation` の needsTripSwitch と
    ///     同じ判定だが、「復帰直後に trip を確保する」ために明示的に呼ぶ。
    func resumeTrackingAfterRelaunch() {
        // 1. wasTracking が false なら復帰不要
        guard let settings = appSettings, settings.wasTracking else {
            Self.logger.info("resumeTrackingAfterRelaunch: wasTracking=false のため再開しない")
            return
        }

        // 2. 自宅判定: currentLocation が自宅内なら再開しない
        if let location = currentLocation {
            let homeState = HomeDetector.detect(
                homeLocation: settings.homeLocation,
                radius: settings.homeRadiusMeters,
                currentLocation: location
            )
            if homeState == .atHome {
                Self.logger.info("resumeTrackingAfterRelaunch: 自宅滞在中のため再開しない")
                return
            }
        }

        // 3. 日付またぎ: currentTrip が前日ならリセット（次の persistLocation 呼び出しで新規 trip を確保）
        if let repository, let current = currentTrip {
            let cal = Calendar.current
            if cal.startOfDay(for: current.date) != cal.startOfDay(for: Date()) {
                // 前日 trip の endedAt を確定させておく
                try? repository.updateEnd(of: current, at: current.endedAt ?? Date())
                currentTrip = nil
                Self.logger.info("resumeTrackingAfterRelaunch: 日付またぎを検出、currentTrip をリセット")
            }
        }

        // 4. 記録再開
        Self.logger.info("resumeTrackingAfterRelaunch: wasTracking=true かつ自宅外 → 記録再開")
        startUpdatingLocation()

        // 5. S6-010 B 案: 後追い滞留検知を実行（タスクキル / iOS 自動停止で抜け落ちたピンを救う）
        runRetroactiveStayDetectionIfNeeded()
    }

    // MARK: - Test hooks

    /// テスト用に外部から位置情報をフィードできるエントリ。
    /// 本番コードからは呼ばない。
    func _ingestForTesting(_ locations: [CLLocation]) {
        handleNewLocations(locations)
    }

    /// テスト用に直近の自宅判定状態を読む（S3-003）。
    var _lastHomeStateForTesting: HomeState { lastHomeState }

    // MARK: - Internal

    fileprivate func handleNewLocations(_ locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let previous = currentLocation
        currentLocation = last

        // S3-003: 自宅判定。.atHome なら RoutePoint 永続化と距離加算をスキップする。
        // - homeLocation 未登録（settings.homeLocation == nil）の場合は .unknown が返り、通常記録。
        // - 状態遷移（atHome → away など）はログに残し、デバッグの可視性を確保。
        let homeState: HomeState = {
            guard let settings = appSettings else { return .unknown }
            return HomeDetector.detect(homeLocation: settings.homeLocation,
                                       radius: settings.homeRadiusMeters,
                                       currentLocation: last)
        }()
        let previousHomeState = lastHomeState
        if homeState != previousHomeState {
            Self.logger.info("HomeState 遷移: \(String(describing: previousHomeState)) -> \(String(describing: homeState))")
            lastHomeState = homeState
            // S3-006: 状態遷移に応じて SLC / 通常 GPS を切替。
            handleHomeStateTransition(from: previousHomeState, to: homeState)
        }
        if homeState == .atHome {
            // 自宅滞在中: route 描画も DB 書き込みも行わない（バッテリー対策）。
            // 受け入れ条件: 「履歴には自宅状態でスキップした座標は記録しない」。
            atHomeSkipCount += 1
            return
        }

        // S3-006: 走行 / 停止判定を行い、desiredAccuracy を動的に切替。
        updateDynamicAccuracy(adding: last)

        // S6-005: バッテリー適応ポリシーを評価し、distanceFilter を動的に切替。
        // desiredAccuracy は Sprint 3 の updateDynamicAccuracy が引き続き管理する。
        // Policy は distanceFilter の切替と、5 分/100m 単位の走行/停車判定を担う。
        updateBatteryPolicy(adding: last)

        // S2-006: 滞留検出。half-circle: 半径外で滞留終了 -> PinRecord 作成。
        let stayEvent = stayDetector.ingest(location: last)

        // チケット S1-007 のメモに従い、直前点との距離が 5m 未満なら経路に積まない（描画間引き）。
        // S2-006 追加ルール: 滞留中の点は経路には積むが、DB 書き込みは間引く。
        // ただし polyline 描画用 route には足しておく（地図上で同じ場所に点が密集して見えるが性能問題はない）。
        if let prev = route.last {
            if last.distance(from: prev) >= 5 {
                route.append(last)
            }
        } else {
            route.append(last)
        }

        // S2-005: DB 永続化処理。repository 未注入時は何もしない（後方互換）。
        if let repository {
            // 滞留中で .skipped が返った場合は RoutePoint の DB 書き込みを丸ごとスキップ
            // （受け入れ条件: 滞留中の RoutePoint は間引かれる）。
            if stayEvent != .skipped {
                persistLocation(last, previousLocation: previous, repository: repository)
            }

            // 滞留終了時: PinRecord を永続化。
            if case .stayEnded(let pin) = stayEvent,
               let trip = currentTrip {
                do {
                    try repository.appendPin(pin, to: trip)
                    // S3-007: お店情報を非同期で取得し PinRecord に書き戻す。
                    // 取得失敗（ネットワーク・レート制限）でも UI と DB の整合は保たれる。
                    enrichPinWithPlaceInfo(pin, repository: repository)
                } catch {
                    Self.logger.warning("PinRecord 永続化失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 新規座標を当日の TripRecord に永続化する。
    /// - 直前点との距離が 5m 未満ならスキップ（揺らぎ排除）
    /// - 5m 以上なら appendRoutePoint で点を追加し、距離を totalDistance に加算
    /// - 日付がまたがった場合は新しい TripRecord に切り替える
    private func persistLocation(_ location: CLLocation,
                                 previousLocation: CLLocation?,
                                 repository: TripRepository) {
        do {
            // 日付またぎ判定: 直前点と現在点の startOfDay が違えば新しい trip に切り替える。
            // 直前点が無い（記録開始直後）も todayTrip() で取得・新規作成。
            let cal = Calendar.current
            let needsTripSwitch: Bool = {
                if let cur = currentTrip {
                    return cal.startOfDay(for: cur.date) != cal.startOfDay(for: location.timestamp)
                }
                return true
            }()
            if needsTripSwitch {
                // 直前の trip があれば endedAt を打ってから切り替える。
                if let cur = currentTrip {
                    try repository.updateEnd(of: cur, at: cur.endedAt ?? Date())
                }
                currentTrip = try repository.todayTrip()
            }
            guard let trip = currentTrip else { return }

            // 直前点との距離を計算。5m 未満ならスキップ（受け入れ条件）。
            // ただし「最初の1点（previousLocation == nil）」は必ず記録する。
            if let prev = previousLocation {
                let segment = TripDistanceCalculator.distance(from: prev, to: location)
                guard segment >= Self.dbWriteThresholdMeters else { return }

                try repository.appendRoutePoint(location, to: trip)
                try repository.updateTotalDistance(of: trip, addingMeters: segment)
                try repository.updateEnd(of: trip, at: location.timestamp)
            } else {
                // 初回点: distance なしで append のみ
                try repository.appendRoutePoint(location, to: trip)
                try repository.updateEnd(of: trip, at: location.timestamp)
            }
        } catch {
            // DB 書き込み失敗はクラッシュさせず、ログのみ出して UI は動かし続ける。
            // Sprint 6 でユーザー向けエラー通知に拡張予定。
            Self.logger.warning("DB 書き込み失敗: \(error.localizedDescription)")
        }
    }

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
    }

    /// 自宅状態遷移時に SLC / 通常 GPS を切替（S3-006）。
    /// - .atHome に入ったとき: 通常 GPS を停止し、SLC を開始
    /// - .away に出たとき: SLC を停止し、通常 GPS を再開
    private func handleHomeStateTransition(from previous: HomeState, to current: HomeState) {
        if current == .atHome {
            startSignificantChangesIfHome()
        } else if previous == .atHome {
            // atHome から離脱した瞬間、SLC を停止して通常 GPS を再開する
            stopSignificantChanges()
            // 既に updating 中ならそのまま、停止中なら再開する。
            // 現実装では isUpdating フラグで二重起動を防いでいるためそのまま start を呼べる。
            if !isUpdating {
                manager.startUpdatingLocation()
                isUpdating = true
            }
        }
    }

    /// 動的精度調整（S3-006）。
    ///
    /// 受け入れ条件:
    ///   - 走行中（5 秒以内に 10m 超移動）= `kCLLocationAccuracyBest`
    ///   - 停止/低速（20 秒以上ほぼ動かず）= `kCLLocationAccuracyHundredMeters`
    ///
    /// 内部実装:
    ///   - `recentLocationHistory` に直近最大 5 件保持
    ///   - 直近 5 秒の差分が 10m 超なら走行 → Best
    ///   - 直近 20 秒の差分が 5m 未満なら停止 → HundredMeters
    ///   - どちらでもなければ現状維持
    private func updateDynamicAccuracy(adding location: CLLocation) {
        recentLocationHistory.append(location)
        // メモリ抑制: 最新 5 件まで
        if recentLocationHistory.count > 5 {
            recentLocationHistory.removeFirst(recentLocationHistory.count - 5)
        }

        // 走行判定: 5 秒以内に 10m 超移動
        let movingThresholdMeters: Double = 10
        let movingTimeWindow: TimeInterval = 5
        let stoppedTimeWindow: TimeInterval = 20
        let stoppedThresholdMeters: Double = 5

        // 直近 5 秒のうちの最古点と現在点の距離
        if let movingAnchor = recentLocationHistory.first(where: {
            location.timestamp.timeIntervalSince($0.timestamp) <= movingTimeWindow
        }), movingAnchor !== location {
            let distance = location.distance(from: movingAnchor)
            if distance > movingThresholdMeters {
                applyDynamicAccuracy(.best)
                return
            }
        }

        // 直近 20 秒のうちの最古点と現在点の距離
        if let stoppedAnchor = recentLocationHistory.first(where: {
            location.timestamp.timeIntervalSince($0.timestamp) <= stoppedTimeWindow
        }), stoppedAnchor !== location {
            let elapsed = location.timestamp.timeIntervalSince(stoppedAnchor.timestamp)
            let distance = location.distance(from: stoppedAnchor)
            if elapsed >= stoppedTimeWindow && distance < stoppedThresholdMeters {
                applyDynamicAccuracy(.hundredMeters)
                return
            }
        }
        // どちらの条件にも該当しなければ現状維持
    }

    /// desiredAccuracy を実際に切り替える。
    private func applyDynamicAccuracy(_ accuracy: DynamicAccuracy) {
        guard accuracy != dynamicAccuracy else { return }
        dynamicAccuracy = accuracy
        switch accuracy {
        case .best:
            manager.desiredAccuracy = kCLLocationAccuracyBest
        case .hundredMeters:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        Self.logger.info("desiredAccuracy 切替: \(accuracy.rawValue)")
    }

    // MARK: - Battery Adaptive Policy（S6-005）

    /// バッテリー適応ポリシーを評価し、distanceFilter を動的に切り替える（S6-005）。
    ///
    /// desiredAccuracy は Sprint 3 の `updateDynamicAccuracy` が引き続き担うため、
    /// ここでは distanceFilter のみを Policy 判定に基づいて更新する。
    /// 判定が変化した場合のみ manager に書き込み、ログを出す（重複適用を防ぐ）。
    private func updateBatteryPolicy(adding location: CLLocation) {
        batteryPolicyLocationHistory.append(location)
        if batteryPolicyLocationHistory.count > Self.batteryPolicyHistoryLimit {
            batteryPolicyLocationHistory.removeFirst(
                batteryPolicyLocationHistory.count - Self.batteryPolicyHistoryLimit
            )
        }

        let decision = batteryPolicy.evaluate(
            recentLocations: batteryPolicyLocationHistory,
            homeLocation: appSettings?.homeLocation,
            homeRadiusMeters: appSettings?.homeRadiusMeters ?? 100,
            now: location.timestamp
        )

        // 前回と同じ決定なら manager への書き込みをスキップ
        guard decision != lastBatteryPolicyDecision else { return }
        lastBatteryPolicyDecision = decision

        switch decision {
        case .stopRecording:
            // 自宅判定は handleNewLocations の HomeDetector で既に処理済みのため、
            // ここでは distanceFilter の変更のみ行う（記録停止は上位ロジックが担う）。
            break
        case .driving(_, let filter):
            manager.distanceFilter = filter
            Self.logger.info("BatteryPolicy: driving → distanceFilter=\(filter)")
        case .stopped(_, let filter):
            manager.distanceFilter = filter
            Self.logger.info("BatteryPolicy: stopped → distanceFilter=\(filter)")
        }
    }

    /// テスト用: バッテリーポリシー履歴をリセットする。
    /// リセット後の初期状態は .driving（configureManager の distanceFilter=10 と整合）。
    func _resetBatteryPolicyHistoryForTesting() {
        batteryPolicyLocationHistory.removeAll()
        lastBatteryPolicyDecision = .driving(
            accuracy: BatteryAdaptiveLocationPolicy.drivingAccuracy,
            distanceFilter: BatteryAdaptiveLocationPolicy.drivingDistanceFilter
        )
    }

    /// テスト用: 直近のバッテリーポリシー決定を読む（S6-005）。
    var _lastBatteryPolicyDecisionForTesting: BatteryAdaptiveLocationPolicy.Decision {
        lastBatteryPolicyDecision
    }

    // MARK: - S6-010 B 案: 後追い滞留検知

    /// 後追い滞留検知を実行し、新たに検知されたピンを永続化する（S6-010 B 案）。
    ///
    /// 発火タイミング:
    ///   - `resumeTrackingAfterRelaunch()` 末尾（SLC 起床 / scenePhase 復帰）
    ///   - `runRetroactiveStayDetectionOnLaunch()` 経由でアプリ起動時（手動 kill → 再起動）
    ///
    /// 処理内容:
    ///   1. 直近 2 日分の RoutePoint を取得
    ///   2. RetroactiveStayDetector で滞留候補を検出
    ///   3. 既存ピンと重複しないものだけ appendPin で永続化
    ///   4. enrichPinWithPlaceInfo でお店情報も取得
    ///
    /// 冪等性: RetroactiveStayDetector.isDuplicate() で重複チェック済みのため、
    /// 複数回発火しても同じピンが二重作成されない。
    func runRetroactiveStayDetectionIfNeeded() {
        guard let repository, let detector = retroactiveStayDetector else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                // 1. 直近 2 日分の RoutePoint を取得（日付またぎシナリオを救うため 2 日）
                let points = try repository.recentRoutePoints(days: 2)
                guard points.count >= 2 else { return }

                // 2. 既存ピンを取得（冪等性チェック用）
                let existingPins = try repository.recentPins(days: 2)

                // 3. 後追い検知を実行（純粋関数: 副作用なし）
                let newPins = detector.detectStays(from: points, excluding: existingPins)
                guard !newPins.isEmpty else {
                    Self.logger.info("RetroactiveStayDetector: 新規ピンなし（点数=\(points.count)）")
                    return
                }

                Self.logger.info("RetroactiveStayDetector: \(newPins.count) 件の新規ピンを検出")

                // 4. 新規ピンを currentTrip に紐付けて永続化
                // 各ピンの stayedFrom 日付に対応する TripRecord に紐付ける
                for pin in newPins {
                    do {
                        let pinDate = pin.stayedFrom
                        // 日付に対応する TripRecord を探す（見つからなければスキップ）
                        if let trip = try? repository.trip(on: pinDate) {
                            try repository.appendPin(pin, to: trip)
                            Self.logger.info("RetroactiveStayDetector: ピン永続化成功 lat=\(pin.latitude) lon=\(pin.longitude)")
                            // お店情報取得もトリガー（既存リアルタイム検知ルートと同じ経路）
                            enrichPinWithPlaceInfo(pin, repository: repository)
                        } else {
                            Self.logger.info("RetroactiveStayDetector: TripRecord 未存在のためスキップ date=\(pinDate)")
                        }
                    } catch {
                        Self.logger.warning("RetroactiveStayDetector: ピン永続化失敗 \(error.localizedDescription)")
                    }
                }
            } catch {
                Self.logger.warning("RetroactiveStayDetector: データ取得失敗 \(error.localizedDescription)")
            }
        }
    }

    /// アプリ起動時に後追い滞留検知を一度実行するエントリポイント（S6-010 B 案）。
    ///
    /// `RootView.task` または `AppDependencyContainer` 初期化直後に呼ぶ。
    /// タスクキル → 手動再起動のシナリオで、SLC 起床を経ずに起動した場合の救済経路。
    ///
    /// `resumeTrackingAfterRelaunch()` とは独立して呼ばれるが、
    /// 冪等性ガード（RetroactiveStayDetector.isDuplicate）により重複ピンは作られない。
    func runRetroactiveStayDetectionOnLaunch() {
        // 同期経路は resumeTrackingAfterRelaunch と共通
        runRetroactiveStayDetectionIfNeeded()
    }

    /// S3-007: 永続化済みの PinRecord に対し、PlaceLookupService を呼んで
    /// placeName / placeURL を埋める。ネットワーク失敗・レート制限・provider 未注入時は
    /// 何もせず PinRecord は元のまま（placeName/URL は nil のまま）。
    /// S4-003: PlaceLookup 完了後、CalendarSyncService が注入されていれば
    /// `createEvent(for:)` を呼び出してカレンダーイベントを作成する。失敗しても
    /// UI は止めず PinRecord 自体は維持される。
    private func enrichPinWithPlaceInfo(_ pin: PinRecord, repository: TripRepository) {
        let provider = placeProvider
        let calendarSync = self.calendarSync
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 1. PlaceLookup（注入されていれば）
            if let provider {
                if let candidate = await provider.lookup(coordinate: coordinate) {
                    // S5-007: address は常に書き戻す（CalendarSync の 3 段 fallback で参照）。
                    // placeName は POI ヒット時のみ name、それ以外は address にフォールバック
                    // （Sprint 3 以前と同じ挙動を維持）。
                    pin.placeName = candidate.name ?? candidate.address
                    pin.placeURL = candidate.url
                    pin.address = candidate.address
                    do {
                        try repository.savePinUpdates()
                    } catch {
                        Self.logger.warning("PinRecord お店情報の保存失敗: \(error.localizedDescription)")
                    }
                }
            }
            // 2. カレンダーイベント作成（S4-003 / 注入されていれば）
            if let calendarSync {
                let result = await calendarSync.createEvent(for: pin)
                switch result {
                case .success:
                    do {
                        try repository.savePinUpdates()
                    } catch {
                        Self.logger.warning("PinRecord calendarEventIdentifier 保存失敗: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    // disabled / permissionDenied / calendarNotFound / saveFailed のいずれも
                    // ログのみ出して PinRecord は保持する（UI は停止しない）。
                    Self.logger.info("カレンダー同期スキップ: \(String(describing: error))")
                }
            }
            _ = self // 警告抑制（この行で MainActor を保持）
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.handleNewLocations(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // 権限拒否などはここで通知される。Sprint 1 ではログのみ。
        // UI への通知は Sprint 2 以降で `@Published var lastError` を追加して対応予定。
        print("[LocationService] didFailWithError: \(error.localizedDescription)")
    }
}
