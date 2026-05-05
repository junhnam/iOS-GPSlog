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
struct MapView: View {
    @StateObject private var locationService: LocationService = {
        // PersistenceController.shared.container.mainContext から TripRepository を生成。
        // mainContext は @MainActor 上でのみ安全。MapView は @MainActor 前提で問題ない。
        let context = PersistenceController.shared.container.mainContext
        let repository = TripRepository(modelContext: context)
        return LocationService(repository: repository)
    }()

    var body: some View {
        GoogleMapContainer(locationService: locationService)
            .ignoresSafeArea()
            .onAppear {
                // 初回起動時に権限ダイアログを表示し、更新を開始する。
                // Always 権限はバックグラウンド記録のために要求する（Sprint 2 以降で本番動作）。
                locationService.requestWhenInUseAuthorization()
                locationService.requestAlwaysAuthorization()
                locationService.startUpdatingLocation()
            }
            .onDisappear {
                locationService.stopUpdatingLocation()
            }
    }
}

/// `GMSMapView` を SwiftUI に統合する `UIViewRepresentable`。
/// 現在地表示（S1-006）と Polyline 経路描画（S1-007）の責務を持つ。
private struct GoogleMapContainer: UIViewRepresentable {
    @ObservedObject var locationService: LocationService

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
        // 現在地が更新されたらカメラを動かす（初回のみ自動追従）。
        if let current = locationService.currentLocation,
           !context.coordinator.didCenterOnFirstFix {
            let camera = GMSCameraPosition.camera(withTarget: current.coordinate,
                                                  zoom: 16)
            mapView.animate(to: camera)
            context.coordinator.didCenterOnFirstFix = true
        }

        // 経路の差分を polyline に append。
        context.coordinator.applyRoute(locationService.route)
    }

    /// 地図の状態を保持する Coordinator。
    /// `GMSMutablePath` を内部で持ち、新しい点だけ append することで描画を効率化する。
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var didCenterOnFirstFix: Bool = false

        private weak var mapView: GMSMapView?
        private let path = GMSMutablePath()
        private var polyline: GMSPolyline?
        private var appliedCount: Int = 0

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

        /// `LocationService.route` を polyline に反映する。
        /// 既に追加済みの点は触らず、未反映分のみ append することで再描画コストを抑える。
        /// route が空に戻った場合（Sprint 2 で route リセット機能が入る想定）はクリアする。
        func applyRoute(_ route: [CLLocation]) {
            if route.count < appliedCount {
                // 何らかの理由で route が縮んだ場合は path をクリアして再構築。
                path.removeAllCoordinates()
                appliedCount = 0
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
    MapView()
}
