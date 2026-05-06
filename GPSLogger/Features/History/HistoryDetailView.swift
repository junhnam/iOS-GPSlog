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
struct HistoryDetailView: View {
    let trip: TripRecord

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HistoryDetailMapContainer(trip: trip)
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
private struct HistoryDetailMapContainer: UIViewRepresentable {
    let trip: TripRecord

    /// 経路ラインの色（メイン地図と統一: 青系 #1E88E5）。
    private static let routeStrokeColor = UIColor(red: 0x1E / 255.0,
                                                  green: 0x88 / 255.0,
                                                  blue: 0xE5 / 255.0,
                                                  alpha: 1.0)

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
        // タイトル: お店名があればお店名、なければ「滞留 約 N 分」（S3-007）。
        // Snippet: お店名がある場合は「滞留 約 N 分」を Snippet に回し、両方見えるようにする。
        for pin in trip.pins.sorted(by: { $0.stayedFrom < $1.stayedFrom }) {
            let coord = CLLocationCoordinate2D(latitude: pin.latitude,
                                               longitude: pin.longitude)
            let marker = GMSMarker(position: coord)
            let minutes = max(1, Int(pin.stayedDurationSeconds / 60))
            let stayLabel = "滞留 約\(minutes)分"
            if let placeName = pin.placeName, !placeName.isEmpty {
                marker.title = placeName
                marker.snippet = stayLabel
                // S3-007: タップ時に Apple Maps URL を開けるよう、userData に URL を保持。
                // 実際の openURL は Sprint 4 のカレンダー連携と合わせて UI から扱う。
                marker.userData = pin.placeURL
            } else {
                marker.title = stayLabel
            }
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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 多重描画防止のためのフラグ保持。
    /// SwiftUI の updateUIView は条件次第で複数回呼ばれる可能性があるため、
    /// 1 度だけ描画させる。
    final class Coordinator {
        var didRender: Bool = false
    }
}
