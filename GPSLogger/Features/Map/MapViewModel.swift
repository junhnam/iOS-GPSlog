import Foundation
import CoreLocation
import SwiftData

/// 地図画面の ViewModel（S2-007）。
///
/// アプリ起動時に SwiftData から「当日の TripRecord」を読み出し、
/// `route` / `pins` / `totalDistanceKm` を View 層に公開する。
/// View（MapView / Coordinator）はこのプロパティを購読し、復元データを polyline と
/// マーカーとして地図に流し込む。
///
/// 設計判断:
///   - LocationService（Dev-2 が S2-005 で拡張中）には依存させず、純粋に DB → 表示の
///     片方向データフローにする。これにより Dev-1 / Dev-2 のコード競合を避ける。
///   - 当日分の RoutePoint だけを fetch する（限定的なデータ量で起動遅延を抑える）。
///
/// 後続スプリント拡張ポイント:
///   - Sprint 3 でピンの種類分け（自宅 / その他）が入る → `RestoredPin` に種別フィールドを追加
@MainActor
final class MapViewModel: ObservableObject {
    /// 復元された経路（時系列順）。Coordinator 側で polyline に流し込む。
    @Published private(set) var route: [CLLocationCoordinate2D] = []

    /// 復元されたピン。Coordinator 側で GMSMarker に変換する。
    @Published private(set) var pins: [RestoredPin] = []

    /// 総移動距離（km、小数点第 2 位）。HUD ラベルで表示する。
    @Published private(set) var totalDistanceKm: Double = 0

    /// 復元処理が走ったかを示すフラグ。`onAppear` の重複防止に利用。
    @Published private(set) var didRestore: Bool = false

    /// 起動時の TripRecord 復元失敗時にユーザー向けに表示するエラーメッセージ（S3-008）。
    /// 通常時は nil。catch 節で `今日の記録の復元に失敗しました（{error}）` がセットされる。
    /// View 側はこの値を購読して赤い帯を表示し、× ボタンで閉じる。
    @Published var restoreError: String?

    /// DI 用の TripRepository。本番では `PersistenceController.shared.container.mainContext`
    /// で構築されたものを、テストではインメモリリポジトリを注入する。
    private let repository: TripRepository

    /// 本番用の便利イニシャライザ。
    /// SwiftData の共有 mainContext から TripRepository を生成する。
    convenience init() {
        let context = PersistenceController.shared.container.mainContext
        self.init(repository: TripRepository(modelContext: context))
    }

    /// テスト用 / DI 用の指定イニシャライザ。
    init(repository: TripRepository) {
        self.repository = repository
    }

    /// 起動時に呼び出す復元エントリポイント。
    ///
    /// - 当日の TripRecord が無ければ何もしない（初回起動・新しい日付の最初の起動）。
    /// - ある場合は RoutePoint を時系列順に並べて `route` に流し込み、
    ///   PinRecord をすべて `pins` に流し込み、`totalDistanceKm` を反映する。
    /// - 失敗時はログのみ出して silent failure（UI を阻害しない）。
    func restoreTodayTrip() {
        guard !didRestore else { return }
        didRestore = true

        do {
            guard let trip = try repository.todayTrip(creatingIfMissing: false) else {
                // 当日のレコード無し（初回起動 or まだ走っていない）。何もしない。
                return
            }

            // 経路点を時系列順に並べる。SwiftData のリレーションは順序保証されないため、
            // 取り出し時にここで明示的にソートする。
            let sortedPoints = trip.routePoints.sorted(by: { $0.timestamp < $1.timestamp })
            self.route = sortedPoints.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }

            // ピンを stayedFrom 順に並べる。重複判定（座標 + stayedFrom）は
            // S2-006 で StayDetector 側が担保する想定で、ここでは取得結果をそのまま反映。
            let sortedPins = trip.pins.sorted(by: { $0.stayedFrom < $1.stayedFrom })
            self.pins = sortedPins.map {
                RestoredPin(latitude: $0.latitude,
                            longitude: $0.longitude,
                            stayedFrom: $0.stayedFrom,
                            stayedDurationSeconds: $0.stayedDurationSeconds,
                            placeName: $0.placeName)
            }

            // 表示用 km 値（モデル側で四捨五入済み）。
            self.totalDistanceKm = trip.totalDistanceKm
        } catch {
            // S3-008: silent failure を解消。ログに加えて UI 通知用の文言を設定する。
            // View 側（MapView）がこの restoreError を購読して赤い帯で表示する。
            print("[MapViewModel] WARNING: Failed to restore today's trip: \(error.localizedDescription)")
            self.restoreError = "今日の記録の復元に失敗しました（\(error.localizedDescription)）"
        }
    }
}

/// 復元したピンを View 層へ受け渡すための値型。
/// SwiftData の `@Model` を直接 View に渡すと再描画コスト・スレッド境界面で扱いにくいため、
/// 必要なフィールドだけを持つ Sendable な struct に変換する。
struct RestoredPin: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let stayedFrom: Date
    let stayedDurationSeconds: Double
    let placeName: String?

    /// 表示用に「約 N 分」を返す。N は秒数を 60 で割って整数化。
    var stayedMinutesText: String {
        let minutes = max(1, Int(stayedDurationSeconds / 60))
        return "滞留 約\(minutes)分"
    }

    /// 緯度経度の同値判定用。重複判定（座標 + stayedFrom）に利用。
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
