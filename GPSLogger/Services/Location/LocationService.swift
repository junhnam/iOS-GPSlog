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

    init(manager: any LocationProviderProtocol = CLLocationManager(),
         repository: TripRepository? = nil,
         stayDetector: StayDetector = StayDetector(),
         placeProvider: (any PlaceProviderProtocol)? = nil,
         appSettings: AppSettings? = nil,
         calendarSync: CalendarSyncService? = nil,
         cloudUploadCoordinator: CloudUploadCoordinator? = nil) {
        self.manager = manager
        self.repository = repository
        self.stayDetector = stayDetector
        self.placeProvider = placeProvider
        self.appSettings = appSettings
        self.calendarSync = calendarSync
        self.cloudUploadCoordinator = cloudUploadCoordinator
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
    }

    func stopUpdatingLocation() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
        // S5-005: 記録停止時にクラウド自動アップロードをトリガー。
        // 自動同期 OFF / プロバイダ未選択時は CloudUploadCoordinator が no-op に倒すため
        // ここでは設定をチェックせず、Coordinator に判断を委ねる。
        triggerCloudUploadIfNeeded()
    }

    /// 現在の TripRecord に対してクラウド自動アップロードを試みる（S5-005）。
    /// CloudUploadCoordinator 未注入 / currentTrip 未確定時は no-op。
    /// 失敗してもログのみで UI は止めない。
    private func triggerCloudUploadIfNeeded() {
        guard let coordinator = cloudUploadCoordinator else { return }
        guard let trip = currentTrip else { return }
        Task { [weak self] in
            _ = await coordinator.uploadIfEnabled(for: trip)
            _ = self // weak 警告抑止
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
