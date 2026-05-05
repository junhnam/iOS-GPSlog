import SwiftUI
import SwiftData

/// 履歴一覧画面（S2-008）。
///
/// 直近 30 日分の TripRecord を日付降順で List 表示する。
/// 各行から HistoryDetailView へ遷移。
///
/// データ取得は SwiftData の `@Query` を使い、画面が開かれている間
/// DB の変更が自動反映されるようにする。30 日制限はビューモデル側で
/// `prefix(30)` する（`@Query` では fetchLimit を直接指定できないため）。
///
/// Sprint 2 では「直近 30 日固定」とし、全期間表示・日付フィルタは
/// Sprint 5 以降の別チケットで対応する。
struct HistoryListView: View {
    /// SwiftData から日付降順で取得した全 TripRecord。
    /// 表示時に `prefix(30)` でクライアント側スライスする。
    @Query(sort: \TripRecord.date, order: .reverse) private var allTrips: [TripRecord]

    private var displayedTrips: [TripRecord] {
        Array(allTrips.prefix(30))
    }

    var body: some View {
        Group {
            if displayedTrips.isEmpty {
                emptyState
            } else {
                List(displayedTrips) { trip in
                    NavigationLink(value: trip) {
                        HistoryRowView(trip: trip)
                    }
                    .accessibilityIdentifier("history_row_\(Int(trip.date.timeIntervalSince1970))")
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: TripRecord.self) { trip in
            HistoryDetailView(trip: trip)
        }
    }

    /// 0 件のときに表示する空状態。Sprint 1 の retro で「初回起動時に何が見えるか」が
    /// 重要との指摘があったため、案内文も添える。
    private var emptyState: some View {
        ContentUnavailableView {
            Label("まだ記録がありません", systemImage: "map")
        } description: {
            Text("移動を始めると、日付ごとの履歴がここに表示されます。")
        }
        .accessibilityIdentifier("history_empty_state")
    }
}

/// 履歴一覧の 1 行分。日付・時刻範囲・距離・ピン件数を 1 行で表示。
private struct HistoryRowView: View {
    let trip: TripRecord

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: trip.date))
                    .font(.headline)

                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f km", trip.totalDistanceKm))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text("ピン \(trip.pins.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.dateFormatter.string(from: trip.date)) の記録、移動距離 \(String(format: "%.2f", trip.totalDistanceKm)) キロメートル、ピン \(trip.pins.count) 件")
    }

    /// 開始〜終了時刻の表示。終了時刻が未確定（記録継続中）の場合は「-」で省略。
    private var timeRangeText: String {
        let start = Self.timeFormatter.string(from: trip.startedAt)
        if let endedAt = trip.endedAt {
            let end = Self.timeFormatter.string(from: endedAt)
            return "\(start) - \(end)"
        } else {
            return "\(start) - （記録中）"
        }
    }
}

#Preview {
    NavigationStack {
        HistoryListView()
    }
}
