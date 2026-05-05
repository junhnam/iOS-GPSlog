import Foundation
import CoreLocation
import Combine

/// アプリ全体で共有される位置情報サービス。
///
/// Core Location を SwiftUI から扱いやすいよう `ObservableObject` でラップする。
/// 現在地表示（S1-006）と経路描画（S1-007）から購読される。
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
    /// アプリ再起動時にリセットされる（DB 永続化は Sprint 2）。
    @Published private(set) var route: [CLLocation] = []

    /// OS の権限状態。UI 側で「設定アプリへ誘導」等の判断に使う。
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    /// 位置情報更新が現在オンかどうか（外部から状態確認用）。
    @Published private(set) var isUpdating: Bool = false

    private let manager: CLLocationManager

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
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
        currentLocation = last
        // チケット S1-007 のメモに従い、直前点との距離が 5m 未満なら経路に積まない（描画間引き）。
        if let previous = route.last {
            if last.distance(from: previous) >= 5 {
                route.append(last)
            }
        } else {
            route.append(last)
        }
    }

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
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
