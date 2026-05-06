import Foundation
import CoreLocation
import Combine
import os

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

    private let manager: CLLocationManager

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

    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "LocationService")

    /// DB 書き込み判定のしきい値（m）。直前点との距離がこれ以上のときだけ永続化する。
    /// 受け入れ条件: 「5m 以上なら appendRoutePoint で永続化」。
    private static let dbWriteThresholdMeters: Double = 5.0

    init(manager: CLLocationManager = CLLocationManager(),
         repository: TripRepository? = nil,
         stayDetector: StayDetector = StayDetector(),
         placeProvider: (any PlaceProviderProtocol)? = nil) {
        self.manager = manager
        self.repository = repository
        self.stayDetector = stayDetector
        self.placeProvider = placeProvider
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
    }

    // MARK: - Test hooks

    /// テスト用に外部から位置情報をフィードできるエントリ。
    /// 本番コードからは呼ばない。
    func _ingestForTesting(_ locations: [CLLocation]) {
        handleNewLocations(locations)
    }

    // MARK: - Internal

    fileprivate func handleNewLocations(_ locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let previous = currentLocation
        currentLocation = last

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

    /// S3-007: 永続化済みの PinRecord に対し、PlaceLookupService を呼んで
    /// placeName / placeURL を埋める。ネットワーク失敗・レート制限・provider 未注入時は
    /// 何もせず PinRecord は元のまま（placeName/URL は nil のまま）。
    private func enrichPinWithPlaceInfo(_ pin: PinRecord, repository: TripRepository) {
        guard let provider = placeProvider else { return }
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let candidate = await provider.lookup(coordinate: coordinate)
            guard let candidate else { return }
            // POI ヒットがあれば name / url を、なければ住所のみ書く。
            pin.placeName = candidate.name ?? candidate.address
            pin.placeURL = candidate.url
            do {
                try repository.savePinUpdates()
            } catch {
                Self.logger.warning("PinRecord お店情報の保存失敗: \(error.localizedDescription)")
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
