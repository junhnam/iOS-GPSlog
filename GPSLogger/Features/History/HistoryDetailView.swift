import SwiftUI
import GoogleMaps
import CoreLocation

/// 履歴詳細画面（S2-008）。
///
/// 選択された 1 日分の TripRecord について、経路（polyline）・ピン（GMSMarker）・
/// 総移動距離・滞留情報をまとめて表示する読み取り専用画面。
/// 編集や記録開始は行わない（記録は地図タブの MapView でのみ）。
///
/// 地図初期表示は経路全体が収まる範囲（fitBounds 相当）。
/// データが空のときは中央付近のダミーカメラ位置のまま、何も描かない。
///
/// S6-013: ピンタップ → 詳細シート（PinDetailView）を表示するように拡張。
/// 地図タブ（MapView）と同一の UX を履歴タブでも提供する。
struct HistoryDetailView: View {
    let trip: TripRecord

    /// タップされた滞留ピン（S6-013）。nil → シート非表示、値あり → シート表示。
    @State private var selectedPin: RestoredPin?

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HistoryDetailMapContainer(trip: trip) { pin in
                selectedPin = pin
            }
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("history_detail_map")

            VStack(spacing: 8) {
                HistoryDetailSummary(trip: trip)
                // S3-007: お店情報があるピンは「お店名 + マップで開く」リンクを縦に並べる。
                if trip.pins.contains(where: { $0.placeName?.isEmpty == false }) {
                    Divider()
                    HistoryDetailPlaceList(pins: trip.pins)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .navigationTitle(Self.titleFormatter.string(from: trip.date))
        .navigationBarTitleDisplayMode(.inline)
        // S6-013: ピンタップ時に詳細シートを表示する（地図タブと同じ UX）。
        .sheet(item: $selectedPin) { pin in
            PinDetailView(model: PinDetailModel(pin: pin)) {
                selectedPin = nil
            }
        }
    }
}

/// 滞留ピンに紐付く「お店情報」を縦リストで表示する（S3-007）。
/// `placeName` が入っているピンのみ最大 5 件表示。`placeURL` があれば「マップで開く」リンクを並べる。
private struct HistoryDetailPlaceList: View {
    let pins: [PinRecord]

    private var displayedPins: [PinRecord] {
        let withName = pins
            .filter { ($0.placeName?.isEmpty == false) }
            .sorted(by: { $0.stayedFrom < $1.stayedFrom })
        return Array(withName.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("お店情報")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(displayedPins.enumerated()), id: \.offset) { _, pin in
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    Text(pin.placeName ?? "")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if let url = pin.placeURL {
                        Link("マップで開く", destination: url)
                            .font(.caption)
                            .accessibilityIdentifier("history_pin_link_open")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("お店 \(pin.placeName ?? "")")
            }
        }
        .accessibilityIdentifier("history_pin_place_list")
    }
}

/// 詳細画面下部のサマリ HUD。総移動距離・滞留件数・滞留合計時間を表示。
private struct HistoryDetailSummary: View {
    let trip: TripRecord

    /// 滞留時間の合計（分）。各 PinRecord.stayedDurationSeconds の総和を分換算。
    private var totalStayMinutes: Int {
        let totalSec = trip.pins.reduce(0.0) { $0 + $1.stayedDurationSeconds }
        return Int(totalSec / 60)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("総移動距離")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f km", trip.totalDistanceKm))
                    .font(.title3.bold())
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("総移動距離 \(String(format: "%.2f", trip.totalDistanceKm)) キロメートル")

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("滞留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(trip.pins.count) 件 / 合計 \(totalStayMinutes) 分")
                    .font(.subheadline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("滞留 \(trip.pins.count) 件、合計 \(totalStayMinutes) 分")

            Spacer()
        }
    }
}

/// 詳細画面の地図部。GMSMapView を SwiftUI に統合し、経路と滞留ピンを 1 度だけ描画する。
/// 読み取り専用なので、座標更新の購読は不要。
///
/// S6-013: `onPinTap` closure を受け取り、Coordinator が GMSMapViewDelegate を実装して
/// ピンタップイベントを SwiftUI 側に通知する。テストから Coordinator にアクセスできるよう
/// `internal` アクセスレベルに変更（`private struct` から `struct` に変更）。
struct HistoryDetailMapContainer: UIViewRepresentable {
    let trip: TripRecord

    /// ピンタップ時に呼び出されるコールバック（S6-013）。
    /// 地図タブと同じ UX: タップされた RestoredPin を引数として渡す。
    let onPinTap: (RestoredPin) -> Void

    /// 経路ラインの色（メイン地図と統一: 青系 #1E88E5）。
    private static let routeStrokeColor = UIColor(red: 0x1E / 255.0,
                                                  green: 0x88 / 255.0,
                                                  blue: 0xE5 / 255.0,
                                                  alpha: 1.0)

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinTap: onPinTap)
    }

    func makeUIView(context: Context) -> GMSMapView {
        // 初期カメラ: データが空でも見栄えが崩れないよう、東京駅近辺をデフォルトに。
        // データがある場合は updateUIView で fitBounds で上書きされる。
        let camera = GMSCameraPosition(latitude: 35.6812,
                                       longitude: 139.7671,
                                       zoom: 12)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        // 詳細画面では現在地ボタンは不要（読み取り専用なので）。
        mapView.isMyLocationEnabled = false
        // S6-013: デリゲートを設定してピンタップイベントを受け取る。
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // 一度だけ描画する（再描画でマーカーが重複しないように）。
        guard !context.coordinator.didRender else { return }
        context.coordinator.didRender = true

        let sortedPoints = trip.routePoints.sorted { $0.timestamp < $1.timestamp }
        let path = GMSMutablePath()
        var bounds = GMSCoordinateBounds()
        var hasAnyCoordinate = false

        for point in sortedPoints {
            let coord = CLLocationCoordinate2D(latitude: point.latitude,
                                               longitude: point.longitude)
            path.add(coord)
            bounds = bounds.includingCoordinate(coord)
            hasAnyCoordinate = true
        }

        if path.count() > 0 {
            let polyline = GMSPolyline(path: path)
            polyline.strokeColor = Self.routeStrokeColor
            polyline.strokeWidth = 5.0
            polyline.map = mapView
        }

        // 滞留ピンを GMSMarker として配置。
        // S6-013: marker.userData を RestoredPin インスタンスに変更し、
        //   タップ時に mapView(_:didTap marker:) で取り出せるようにする。
        //   （旧実装: marker.userData = pin.placeURL → 未使用だったため完全置き換え）
        for pin in trip.pins.sorted(by: { $0.stayedFrom < $1.stayedFrom }) {
            let coord = CLLocationCoordinate2D(latitude: pin.latitude,
                                               longitude: pin.longitude)
            let marker = GMSMarker(position: coord)
            let minutes = max(1, Int(pin.stayedDurationSeconds / 60))
            let stayLabel = "滞留 約\(minutes)分"
            // マーカーのタイトル/スニペット（InfoWindow は didTap で return true して抑制するが、
            // ユーザーが標準ビューに触れた際の見栄えとして念のため設定する）。
            if let placeName = pin.placeName, !placeName.isEmpty {
                marker.title = placeName
                marker.snippet = stayLabel
            } else {
                marker.title = stayLabel
            }
            // S6-013: PinRecord → RestoredPin に変換して userData に格納。
            // RestoredPin は Sendable な値型なので Sendable 境界を越えても安全。
            let restoredPin = RestoredPin(
                latitude: pin.latitude,
                longitude: pin.longitude,
                stayedFrom: pin.stayedFrom,
                stayedDurationSeconds: pin.stayedDurationSeconds,
                placeName: pin.placeName,
                address: pin.address
            )
            marker.userData = restoredPin
            marker.map = mapView
            bounds = bounds.includingCoordinate(coord)
            hasAnyCoordinate = true
        }

        // 経路全体が収まる範囲にカメラを移動（fitBounds 相当）。
        // 60pt のパディングは画面端に張り付かないようにするための余白。
        if hasAnyCoordinate {
            let update = GMSCameraUpdate.fit(bounds, withPadding: 60)
            mapView.animate(with: update)
        }
    }

    /// 多重描画防止 + GMSMapViewDelegate 実装を担う Coordinator（S6-013 拡張）。
    ///
    /// Swift 6 strict concurrency 対応:
    ///   - `@MainActor` でクラス全体を MainActor に隔離する。
    ///   - `@preconcurrency GMSMapViewDelegate` により、GMSMapViewDelegate のアイソレーション
    ///     境界チェックを緩和する（S6-011 の MapView.Coordinator と同じパターン）。
    @MainActor
    final class Coordinator: NSObject, @preconcurrency GMSMapViewDelegate {
        /// 多重描画防止フラグ。
        var didRender: Bool = false

        /// ピンタップ時に呼び出すコールバック。
        private let onPinTap: (RestoredPin) -> Void

        init(onPinTap: @escaping (RestoredPin) -> Void) {
            self.onPinTap = onPinTap
        }

        // MARK: - GMSMapViewDelegate (S6-013)

        /// マーカータップ時に詳細シートを表示する（S6-013）。
        ///
        /// - Returns: `true` を返すことで GMSMapView 標準の InfoWindow 表示を抑制し、
        ///   カスタムシート（PinDetailView）に統一する（地図タブと同じ UX）。
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            handleMarkerTap(pin: marker.userData as? RestoredPin)
            return true
        }

        /// マーカータップのロジック部分。テストから直接呼び出せるよう internal メソッドとして分離（S6-013）。
        ///
        /// - Parameter pin: `marker.userData` から取り出した `RestoredPin`。
        ///   nil の場合（userData 未設定 / 型ミスマッチ）は何もしない。
        func handleMarkerTap(pin: RestoredPin?) {
            guard let pin else { return }
            onPinTap(pin)
        }
    }
}
