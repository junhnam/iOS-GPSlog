import SwiftUI
import GoogleMaps
import CoreLocation
import MapKit

/// 自宅位置の登録 UI（S3-002 / S4-001）。
///
/// 機能:
///   - 地図上にピンを置き、ドラッグで自宅候補座標を変更
///   - 「現在地に合わせる」ボタンで CLLocationManager の位置にピンを移動
///   - 逆ジオコーディング（MKReverseGeocodingRequest, iOS 26+）で住所文字列を取得
///   - 住所候補が複数返る場合は List で 3 件まで表示し、jun さんが選択
///   - 「半径」スライダー（50〜300m, デフォルト 100m）
///   - 「保存」で `AppSettings.homeLocation` / `homeRadiusMeters` に書き込む
///
/// 注意:
///   - S4-001 で `CLGeocoder` から `MKReverseGeocodingRequest` に移行。
///     連続呼び出しキャンセルは旧 `CLGeocoder.cancelGeocode()` ではなく
///     `Task.cancel()` で実現する（async/await ベースのキャンセル機構）。
///   - ネットワークエラー時は「住所取得に失敗しました」を表示し、座標のみで保存可能
struct HomeRegistrationView: View {
    @Bindable var settings: AppSettings

    /// 完了時に呼ばれるクロージャ（保存 / キャンセル両方）。
    /// 親（SettingsView）でシートを閉じるために使う。
    let onDismiss: () -> Void

    /// 編集中の候補座標（保存ボタンを押すまで AppSettings に反映しない）。
    @State private var selectedCoordinate: CLLocationCoordinate2D = HomeRegistrationView.defaultCenter

    /// 編集中の半径（保存ボタンを押すまで AppSettings に反映しない）。
    /// S6-014: 旧実装は init で `_radius = State(initialValue: settings.homeRadiusMeters)` していたが、
    ///   save() で settings.homeLocation を書いた瞬間に親 SettingsView が再描画され、
    ///   sheet content closure 経由で HomeRegistrationView の init が再評価されると
    ///   initialValue が再適用される SwiftUI 既知問題があり、ドラッグ後の値が
    ///   保存前の値（または東京駅の defaultCenter）に戻るバグがあった。
    ///   解消のため、@State はリテラル既定値で初期化し、settings からの復元は .onAppear で行う。
    @State private var radius: Double = AppSettings.defaultHomeRadiusMeters

    /// 逆ジオコーディング結果の候補（最大 3 件）。
    @State private var addressCandidates: [String] = []

    /// 選択中の住所候補。nil の場合は座標のみ保存される。
    @State private var selectedAddress: String?

    /// settings からの初回ロード済みフラグ（S6-014 / 二重ロード防止）。
    @State private var didLoadFromSettings: Bool = false

    /// 逆ジオコーディング失敗時のエラーメッセージ（UI 上の警告表示用）。
    @State private var geocodeErrorMessage: String?

    /// 逆ジオコーディング進行中フラグ。
    @State private var isGeocoding: Bool = false

    /// 進行中の逆ジオコーディング Task（S4-001）。
    /// 連続呼び出し時は前回の Task を `cancel()` してから新規 Task を起動する。
    /// （旧 `CLGeocoder.cancelGeocode()` の置き換え）
    @State private var geocodingTask: Task<Void, Never>?

    /// 現在地取得用の CLLocationManager（軽量。HomeRegistrationView の寿命中だけ生きる）。
    @State private var oneShotLocationManager: CLLocationManager = CLLocationManager()
    @State private var oneShotDelegate: OneShotLocationDelegate?

    /// 初期表示の中心座標（東京駅）。権限が無い場合のフォールバック。
    static let defaultCenter = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss
        // S6-014: @State の初期値は宣言時のリテラルに固定（init での外部値設定は廃止）。
        // settings からの復元は .onAppear で `didLoadFromSettings` ガード付きで行う。
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
            // S6-014: 初回 onAppear のみ settings から既存値を復元する。
            // 二回目以降（再描画後の onAppear）は復元しない（ドラッグ後の値を破壊しないため）。
            if !didLoadFromSettings {
                didLoadFromSettings = true
                if let existing = settings.homeLocation {
                    selectedCoordinate = existing.coordinate
                    selectedAddress = existing.address
                }
                radius = settings.homeRadiusMeters
            }
            triggerReverseGeocode(coordinate: selectedCoordinate)
        }
        .onDisappear {
            // S6-022 (タスク B / P7 修正): シートが閉じた時に didLoadFromSettings をリセットする。
            // .sheet(isPresented:) では同じ View インスタンスが再利用される場合があり、
            // リセットしないと 2 回目以降の .onAppear で settings.homeLocation の最新値が
            // 反映されない問題が残る（QA P7）。
            //
            // 注意: .sheet の .onDisappear はシート閉じ時のみ発火し、タブ切替では発火しない。
            // そのため MapView の .onDisappear 問題（S6-016 / stopUpdatingLocation の誤発火）
            // とは異なる経路であり、安全にリセットできる。
            didLoadFromSettings = false
        }
    }

    // MARK: - Geocoding

    private func triggerReverseGeocode(coordinate: CLLocationCoordinate2D) {
        // S4-001: 短時間に何度も発火する（地図ドラッグ中の didChange）ため、
        // 進行中の Task をキャンセルしてから新規 Task を起動する。
        geocodingTask?.cancel()
        isGeocoding = true
        geocodeErrorMessage = nil

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocodingTask = Task { @MainActor in
            defer { isGeocoding = false }
            do {
                // iOS 26 の MKReverseGeocodingRequest は init?(location:) のみで
                // preferredLocale 引数を受け取らない。住所表記は端末のロケール
                // （jun さんの環境では ja_JP）に従う。
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    geocodeErrorMessage = "住所取得に失敗しました（位置のみ保存します）"
                    return
                }
                let mapItems = try await request.mapItems
                if Task.isCancelled { return }
                // QA-S4-001: 旧 `$0.placemark` は iOS 26 で deprecated。
                // 新 API `MKMapItem.address: MKAddress?` の `fullAddress` を使う。
                let formatted = mapItems.prefix(3).compactMap { $0.address?.fullAddress }
                addressCandidates = formatted
                if let first = formatted.first, selectedAddress == nil {
                    selectedAddress = first
                }
            } catch {
                if Task.isCancelled { return }
                if error is CancellationError { return }
                geocodeErrorMessage = "住所取得に失敗しました（位置のみ保存します）"
            }
        }
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
