import SwiftUI
import GoogleMaps
import CoreLocation

/// 自宅位置の登録 UI（S3-002）。
///
/// 機能:
///   - 地図上にピンを置き、ドラッグで自宅候補座標を変更
///   - 「現在地に合わせる」ボタンで CLLocationManager の位置にピンを移動
///   - 逆ジオコーディング（CLGeocoder）で住所文字列を取得
///   - 住所候補が複数返る場合は List で 3 件まで表示し、jun さんが選択
///   - 「半径」スライダー（50〜300m, デフォルト 100m）
///   - 「保存」で `AppSettings.homeLocation` / `homeRadiusMeters` に書き込む
///
/// 注意:
///   - CLGeocoder は MainActor 隔離不要だが、コールバックは Main で扱う
///   - ネットワークエラー時は「住所取得に失敗しました」を表示し、座標のみで保存可能
struct HomeRegistrationView: View {
    @Bindable var settings: AppSettings

    /// 完了時に呼ばれるクロージャ（保存 / キャンセル両方）。
    /// 親（SettingsView）でシートを閉じるために使う。
    let onDismiss: () -> Void

    /// 編集中の候補座標（保存ボタンを押すまで AppSettings に反映しない）。
    @State private var selectedCoordinate: CLLocationCoordinate2D = HomeRegistrationView.defaultCenter

    /// 編集中の半径（保存ボタンを押すまで AppSettings に反映しない）。
    @State private var radius: Double

    /// 逆ジオコーディング結果の候補（最大 3 件）。
    @State private var addressCandidates: [String] = []

    /// 選択中の住所候補。nil の場合は座標のみ保存される。
    @State private var selectedAddress: String?

    /// 逆ジオコーディング失敗時のエラーメッセージ（UI 上の警告表示用）。
    @State private var geocodeErrorMessage: String?

    /// 逆ジオコーディング進行中フラグ。
    @State private var isGeocoding: Bool = false

    /// 逆ジオコーディング用の CLGeocoder。
    private let geocoder = CLGeocoder()

    /// 現在地取得用の CLLocationManager（軽量。HomeRegistrationView の寿命中だけ生きる）。
    @State private var oneShotLocationManager: CLLocationManager = CLLocationManager()
    @State private var oneShotDelegate: OneShotLocationDelegate?

    /// 初期表示の中心座標（東京駅）。権限が無い場合のフォールバック。
    static let defaultCenter = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss

        // 既存の自宅位置があればそれを初期値に。
        if let existing = settings.homeLocation {
            _selectedCoordinate = State(initialValue: existing.coordinate)
            _selectedAddress = State(initialValue: existing.address)
        }
        _radius = State(initialValue: settings.homeRadiusMeters)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 地図（上半分）
            HomeRegistrationMap(coordinate: $selectedCoordinate,
                                radius: radius)
                .frame(maxHeight: .infinity)
                .onChange(of: selectedCoordinate.latitude) { _, _ in
                    triggerReverseGeocode(coordinate: selectedCoordinate)
                }
                .onChange(of: selectedCoordinate.longitude) { _, _ in
                    triggerReverseGeocode(coordinate: selectedCoordinate)
                }

            // フォーム部分（下半分）
            Form {
                Section {
                    Button {
                        moveToCurrentLocation()
                    } label: {
                        Label("現在地に合わせる", systemImage: "location.fill")
                    }

                    LabeledContent("緯度") {
                        Text(String(format: "%.5f", selectedCoordinate.latitude))
                            .monospacedDigit()
                    }
                    LabeledContent("経度") {
                        Text(String(format: "%.5f", selectedCoordinate.longitude))
                            .monospacedDigit()
                    }
                } header: {
                    Text("位置")
                }

                Section {
                    if isGeocoding {
                        HStack {
                            ProgressView()
                            Text("住所を取得中...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let geocodeErrorMessage {
                        Text(geocodeErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if addressCandidates.isEmpty {
                        if !isGeocoding && geocodeErrorMessage == nil {
                            Text("住所はまだ取得できていません。地図を動かすと自動で取得します。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(addressCandidates, id: \.self) { candidate in
                            HStack {
                                Text(candidate)
                                    .font(.callout)
                                Spacer()
                                if selectedAddress == candidate {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAddress = candidate
                            }
                        }
                    }
                } header: {
                    Text("住所候補")
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("半径")
                            Spacer()
                            Text(String(format: "%.0f m", radius))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $radius,
                               in: AppSettings.homeRadiusMinMeters...AppSettings.homeRadiusMaxMeters,
                               step: 10)
                    }
                } header: {
                    Text("半径")
                }
            }
        }
        .navigationTitle("自宅を登録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { onDismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                    onDismiss()
                }
            }
        }
        .onAppear {
            triggerReverseGeocode(coordinate: selectedCoordinate)
        }
    }

    // MARK: - Geocoding

    private func triggerReverseGeocode(coordinate: CLLocationCoordinate2D) {
        // 短時間に何度も発火する（地図ドラッグ中の didChange）ため、進行中の geocode をキャンセル。
        geocoder.cancelGeocode()
        isGeocoding = true
        geocodeErrorMessage = nil

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja_JP")) { placemarks, error in
            // CLGeocoder のコールバックは main queue で来るので Task は不要だが、
            // Swift 6 strict concurrency に合わせて MainActor で囲む。
            Task { @MainActor in
                isGeocoding = false
                if let error {
                    // キャンセルは無視（連続移動時のキャンセルはエラーではない）
                    let nsError = error as NSError
                    if nsError.domain == kCLErrorDomain && nsError.code == CLError.geocodeCanceled.rawValue {
                        return
                    }
                    geocodeErrorMessage = "住所取得に失敗しました（位置のみ保存します）"
                    return
                }
                let formatted = (placemarks ?? []).prefix(3).compactMap(formatPlacemark(_:))
                addressCandidates = formatted
                if let first = formatted.first, selectedAddress == nil {
                    selectedAddress = first
                }
            }
        }
    }

    /// CLPlacemark から日本住所表記を組み立てる。空要素は除外。
    private func formatPlacemark(_ placemark: CLPlacemark) -> String? {
        let parts: [String?] = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare,
            placemark.name
        ]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Current Location

    private func moveToCurrentLocation() {
        // ワンショット権限要求 + 単発 fetch。HomeRegistrationView を出ている間だけ生きる。
        let manager = oneShotLocationManager
        let delegate = OneShotLocationDelegate { result in
            Task { @MainActor in
                switch result {
                case .success(let coord):
                    selectedCoordinate = coord
                case .failure:
                    // 失敗は静かに無視（既存の地図位置を保持）
                    break
                }
                oneShotDelegate = nil
            }
        }
        oneShotDelegate = delegate
        manager.delegate = delegate
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    // MARK: - Save

    private func save() {
        let home = HomeLocation(latitude: selectedCoordinate.latitude,
                                longitude: selectedCoordinate.longitude,
                                address: selectedAddress,
                                registeredAt: Date())
        settings.homeLocation = home
        settings.homeRadiusMeters = radius
    }
}

// MARK: - GoogleMap Container for HomeRegistration

/// 自宅候補座標を 1 個のマーカー + 半径の円で表示する `UIViewRepresentable`。
/// マーカーはドラッグ可能で、ドロップ時に `coordinate` をバインディング更新する。
private struct HomeRegistrationMap: UIViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D
    let radius: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinate: $coordinate)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 16)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = false
        mapView.delegate = context.coordinator

        let marker = GMSMarker(position: coordinate)
        marker.isDraggable = true
        marker.title = "自宅"
        marker.map = mapView
        context.coordinator.marker = marker

        let circle = GMSCircle(position: coordinate, radius: radius)
        circle.fillColor = UIColor.systemBlue.withAlphaComponent(0.15)
        circle.strokeColor = .systemBlue
        circle.strokeWidth = 2
        circle.map = mapView
        context.coordinator.circle = circle

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.marker?.position = coordinate
        context.coordinator.circle?.position = coordinate
        context.coordinator.circle?.radius = radius
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        @Binding var coordinate: CLLocationCoordinate2D
        var marker: GMSMarker?
        var circle: GMSCircle?

        init(coordinate: Binding<CLLocationCoordinate2D>) {
            self._coordinate = coordinate
        }

        func mapView(_ mapView: GMSMapView, didEndDragging marker: GMSMarker) {
            coordinate = marker.position
        }

        func mapView(_ mapView: GMSMapView, didTapAt c: CLLocationCoordinate2D) {
            // タップ位置にマーカーを移動できるようにする（ドラッグの代替操作）
            coordinate = c
        }
    }
}

// MARK: - One-shot Location Delegate

/// 「現在地に合わせる」ボタン用の単発 CLLocationManagerDelegate。
/// HomeRegistrationView から保持され、結果を 1 度だけ完了ハンドラに通知する。
private final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    typealias Completion = (Result<CLLocationCoordinate2D, Error>) -> Void
    private let completion: Completion
    private var didFire: Bool = false

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didFire, let last = locations.last else { return }
        didFire = true
        completion(.success(last.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !didFire else { return }
        didFire = true
        completion(.failure(error))
    }
}
