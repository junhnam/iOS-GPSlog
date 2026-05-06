import SwiftUI
import GoogleMaps
import CoreLocation

/// 地図画面のメイン View。
/// `LocationService` を購読し、現在地（青ドット）と移動経路（青い polyline）を表示する。
///
/// Sprint 1 のスコープ:
///   - 現在地に追従するカメラ（初回のみ自動追従）
///   - 経路は `LocationService.route` の全点を polyline で描画
/// Sprint 2 拡張（S2-005）:
///   - `PersistenceController.shared` から `TripRepository` を生成し、
///     `LocationService` に注入することで座標を当日の TripRecord に永続化する
/// Sprint 2 拡張（S2-007）:
///   - `MapViewModel` を介して当日の TripRecord を起動時に読み込み、
///     経路 / ピン / 総移動距離を地図に復元表示する
struct MapView: View {
    /// アプリ全体で共有される LocationService。RootView 側で生成し、
    /// AppSettings / placeProvider を含めて DI 済みの状態で受け取る（QA-S3-001 修正）。
    /// `@ObservedObject` で受けることで MapView 単独の `@StateObject` 初期化時点で
    /// AppSettings が手元に無い問題を回避する。
    @ObservedObject var locationService: LocationService

    /// 起動時の TripRecord 復元と HUD 値の保持を担う ViewModel（S2-007）。
    @StateObject private var viewModel = MapViewModel()

    /// アプリ全体で共有される設定（S3-001）。RootView から `.environment` で注入される。
    @Environment(AppSettings.self) private var settings

    /// 自宅滞在中にトリガー記録開始した際の警告（S3-005）。
    /// 1 セッションで 1 度だけ表示するためフラグで制御する。
    @State private var didShowHomeWhileTriggerWarning: Bool = false
    @State private var homeWarningMessage: String?

    /// 起動時復元失敗の通知メッセージ（S3-008）。
    /// `viewModel.restoreError` を購読して赤い帯を表示する。
    @State private var dismissedRestoreError: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            GoogleMapContainer(locationService: locationService,
                               restoredRoute: viewModel.route,
                               restoredPins: viewModel.pins)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                // HUD: 総移動距離（km）を画面上部に表示（S2-007）。
                DistanceHUDLabel(kilometers: viewModel.totalDistanceKm)
                    .accessibilityIdentifier("distance_hud")

                // S3-008: 復元失敗時のエラー帯。
                if let error = viewModel.restoreError, !dismissedRestoreError {
                    RestoreErrorBanner(message: error) {
                        dismissedRestoreError = true
                    }
                }

                // S3-005: 自宅滞在中にトリガー記録を開始した際の警告。
                if let warning = homeWarningMessage {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.85), in: Capsule())
                        .accessibilityIdentifier("home_recording_warning")
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottomTrailing) {
            if settings.recordingMode == .trigger {
                RecordingToggleButton(isLogging: locationService.isUpdating) {
                    handleRecordingToggle()
                }
                .padding(.trailing, 16)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            // 復元はカメラ初期化等よりも先に走らせる（onAppear で十分高速）。
            viewModel.restoreTodayTrip()

            // 初回起動時に権限ダイアログを表示する（権限要求は記録モードに関係なく必要）。
            locationService.requestWhenInUseAuthorization()
            locationService.requestAlwaysAuthorization()

            // S3-004 / S3-005: トリガーモードでは自動 start しない（受け入れ条件:
            // 「アプリ再起動時、トリガーモードでは記録が自動再開されない」）。
            if settings.recordingMode == .continuous {
                locationService.startUpdatingLocation()
            }
        }
        .onDisappear {
            locationService.stopUpdatingLocation()
        }
    }

    // MARK: - S3-005 Trigger handling

    /// フローティングボタンタップ時のハンドラ。
    /// 現在 isUpdating でない場合は start、そうでない場合は stop する。
    /// 自宅滞在中かどうかの判定と HUD メッセージ生成は `HomeDetector` に集約し、
    /// MapView 側は HomeDetector の戻り値を表示するだけにする（S4-008）。
    private func handleRecordingToggle() {
        if locationService.isUpdating {
            locationService.stopUpdatingLocation()
        } else {
            locationService.startUpdatingLocation()
            // S4-008: 自宅判定ロジックは HomeDetector に統一。MapView は判定をしない。
            // 1 セッション 1 回だけ HUD を出す制御だけ MapView 側に残す。
            guard !didShowHomeWhileTriggerWarning,
                  let current = locationService.currentLocation,
                  let message = HomeDetector.bannerMessage(homeLocation: settings.homeLocation,
                                                           radius: settings.homeRadiusMeters,
                                                           currentLocation: current) else {
                return
            }
            homeWarningMessage = message
            didShowHomeWhileTriggerWarning = true
            // 5 秒後に消す
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                homeWarningMessage = nil
            }
        }
    }
}

/// 起動時復元失敗時に表示する赤い通知バー（S3-008）。
private struct RestoreErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("通知を閉じる")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("restore_error_banner")
    }
}

/// 総移動距離 HUD（S2-007）。
/// 半透明背景 + 太字で「総移動距離: X.XX km」と表示する最低限の表示。
/// Designer による HUD 改善は Sprint 3 以降の予定。
private struct DistanceHUDLabel: View {
    let kilometers: Double

    var body: some View {
        Text(String(format: "総移動距離: %.2f km", kilometers))
            .font(.callout.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityLabel("総移動距離 \(String(format: "%.2f", kilometers)) キロメートル")
    }
}

/// `GMSMapView` を SwiftUI に統合する `UIViewRepresentable`。
/// 現在地表示（S1-006）と Polyline 経路描画（S1-007）の責務を持つ。
/// S2-007 で復元データ（route / pins）を初期投入する受け口を追加。
private struct GoogleMapContainer: UIViewRepresentable {
    @ObservedObject var locationService: LocationService

    /// 起動時に SwiftData から復元された当日経路（S2-007）。
    /// Coordinator は最初に updateUIView が呼ばれた時に一括投入する。
    let restoredRoute: [CLLocationCoordinate2D]

    /// 起動時に SwiftData から復元された当日ピン（S2-007）。
    let restoredPins: [RestoredPin]

    /// 経路ラインの色（チケット S1-007: 青系 #1E88E5）
    private static let routeStrokeColor = UIColor(red: 0x1E / 255.0,
                                                  green: 0x88 / 255.0,
                                                  blue: 0xE5 / 255.0,
                                                  alpha: 1.0)
    /// 経路ラインの太さ（チケット S1-007: 5pt）
    private static let routeStrokeWidth: CGFloat = 5.0

    /// 初期カメラ位置（東京駅）。
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 35.681236,
                                                              longitude: 139.767125)
    private static let defaultZoom: Float = 12

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withTarget: Self.defaultCenter,
                                              zoom: Self.defaultZoom)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)

        // 青ドットで現在地表示（Google Maps 標準）。
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true

        context.coordinator.attach(to: mapView,
                                   strokeColor: Self.routeStrokeColor,
                                   strokeWidth: Self.routeStrokeWidth)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // 起動時に復元データ（経路・ピン）を一括投入する（S2-007）。
        // 内部フラグで多重投入を防止しているため、毎回呼び出しても安全。
        context.coordinator.applyRestoredRouteIfNeeded(restoredRoute)
        context.coordinator.applyRestoredPinsIfNeeded(restoredPins, on: mapView)

        // 現在地が更新されたらカメラを動かす（初回のみ自動追従）。
        if let current = locationService.currentLocation,
           !context.coordinator.didCenterOnFirstFix {
            let camera = GMSCameraPosition.camera(withTarget: current.coordinate,
                                                  zoom: 16)
            mapView.animate(to: camera)
            context.coordinator.didCenterOnFirstFix = true
        }

        // 経路の差分を polyline に append。
        // 復元済みの点に対しては「続きから」伸びるよう、Coordinator が
        // restoredRoute.count を起点にして LocationService.route の append 分を
        // path に追加する。
        context.coordinator.applyRoute(locationService.route)
    }

    /// 地図の状態を保持する Coordinator。
    /// `GMSMutablePath` を内部で持ち、新しい点だけ append することで描画を効率化する。
    ///
    /// S5-008: Swift 6 strict concurrency 対応で `@MainActor` 隔離化。
    /// SwiftUI は `UIViewRepresentable.Coordinator` を MainActor 上でしか触らないため、
    /// クラス全体を MainActor に閉じることで GMSMapView/GMSMutablePath/GMSPolyline 等の
    /// 非 Sendable プロパティアクセスが安全になる。GMSMapViewDelegate メソッドも UIKit
    /// 由来のため MainActor 上で呼ばれる前提と矛盾しない。
    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var didCenterOnFirstFix: Bool = false

        private weak var mapView: GMSMapView?
        private let path = GMSMutablePath()
        private var polyline: GMSPolyline?
        private var appliedCount: Int = 0

        // S2-007: 復元データの多重投入を防止するためのフラグ・キャッシュ。
        private var didApplyRestoredRoute: Bool = false
        /// 既に地図に置いたピンの重複判定キー（座標 + stayedFrom の組）。
        private var placedPinKeys: Set<String> = []

        func attach(to mapView: GMSMapView,
                    strokeColor: UIColor,
                    strokeWidth: CGFloat) {
            self.mapView = mapView
            mapView.delegate = self

            let polyline = GMSPolyline(path: path)
            polyline.strokeColor = strokeColor
            polyline.strokeWidth = strokeWidth
            polyline.geodesic = true
            polyline.map = mapView
            self.polyline = polyline
        }

        /// 起動時に復元された経路を polyline の初期 path に一括投入する（S2-007）。
        /// 二度目以降の updateUIView では何もしないようフラグでガードする。
        func applyRestoredRouteIfNeeded(_ coordinates: [CLLocationCoordinate2D]) {
            guard !didApplyRestoredRoute else { return }
            didApplyRestoredRoute = true
            guard !coordinates.isEmpty else { return }
            for c in coordinates {
                path.add(c)
            }
            // 復元分は appliedCount に含めない。これにより以降に来る
            // LocationService.route が「続きから」appliedCount==0 起点で append される。
            polyline?.path = path
        }

        /// 起動時に復元されたピンを地図上に GMSMarker として配置する（S2-007）。
        /// 重複（同座標 + 同 stayedFrom）は再生成しない。
        func applyRestoredPinsIfNeeded(_ pins: [RestoredPin], on mapView: GMSMapView) {
            guard !pins.isEmpty else { return }
            for pin in pins {
                let key = "\(pin.latitude)_\(pin.longitude)_\(pin.stayedFrom.timeIntervalSince1970)"
                guard !placedPinKeys.contains(key) else { continue }
                placedPinKeys.insert(key)

                let marker = GMSMarker(position: pin.coordinate)
                // タイトルは「滞留 約 N 分」（受け入れ条件）。お店情報は Sprint 3。
                marker.title = pin.stayedMinutesText
                if let placeName = pin.placeName {
                    marker.snippet = placeName
                }
                marker.map = mapView
            }
        }

        /// `LocationService.route` を polyline に反映する。
        /// 既に追加済みの点は触らず、未反映分のみ append することで再描画コストを抑える。
        /// route が空に戻った場合（Sprint 2 で route リセット機能が入る想定）はクリアする。
        func applyRoute(_ route: [CLLocation]) {
            if route.count < appliedCount {
                // 何らかの理由で route が縮んだ場合は path をクリアして再構築。
                // 復元済み点も一緒に消える点は仕様として許容（S2-007 受け入れ条件は通常運用での連続性のみ）。
                path.removeAllCoordinates()
                appliedCount = 0
                didApplyRestoredRoute = false
            }

            guard route.count > appliedCount else { return }

            for i in appliedCount..<route.count {
                path.add(route[i].coordinate)
            }
            appliedCount = route.count
            polyline?.path = path
        }
    }
}

#Preview {
    let context = PersistenceController.shared.container.mainContext
    let repository = TripRepository(modelContext: context)
    let settings = AppSettings()
    return MapView(locationService: LocationService(repository: repository, appSettings: settings))
        .environment(settings)
}
