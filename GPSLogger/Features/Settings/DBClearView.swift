import SwiftUI

/// DB クリア画面（S6-003）。
///
/// 機能:
///   - TripRepository から日付一覧を取得してリスト表示する（昇順 / 降順切替トグル）
///   - 各行に削除ボタン → 確認アラート → 確定で 1 件削除
///   - 「全削除」ボタン → 2 段階確認アラート → 確定で全件削除
///   - 削除中は ProgressView + ボタン disable で二重タップ防止
///   - 削除後はリストを即時更新（削除済み日付を除外）
///
/// アーキテクチャ:
///   - ViewModel なし。View に直接 @State を持つシンプル構成。
///     DB 操作は TripRepository（@MainActor）を直接呼ぶため、
///     追加の非同期ブリッジが不要で Swift 6 の strict concurrency に安全に収まる。
@MainActor
struct DBClearView: View {

    /// DB 操作用リポジトリ（AppDependencyContainer から注入する）。
    let repository: TripRepository

    /// 日付フォーマッタ（行表示用）。
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    /// 表示中の日付一覧。削除後に即時更新される。
    @State private var dates: [Date] = []

    /// 日付を降順で表示するかどうか（true = 新しい順）。
    @State private var showDescending: Bool = true

    /// 削除処理の実行中フラグ（二重タップ防止）。
    @State private var isDeleting: Bool = false

    /// 単一日削除の確認アラート表示フラグ。
    @State private var showDeleteSingleAlert: Bool = false

    /// 削除対象の日付（単一削除）。
    @State private var pendingDeleteDate: Date? = nil

    /// 全削除アラートの段階（0 = 非表示 / 1 = 1 段目 / 2 = 2 段目）。
    @State private var deleteAllPhase: Int = 0

    /// エラーアラートのメッセージ。nil = 非表示。
    @State private var errorMessage: String? = nil

    // MARK: - Body

    var body: some View {
        List {
            if isDeleting {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("削除中...")
                        Spacer()
                    }
                }
            }

            if dates.isEmpty && !isDeleting {
                Section {
                    Text("削除できる記録がありません。")
                        .foregroundStyle(.secondary)
                }
            } else {
                sortedDatesSection
            }

            deleteAllSection
        }
        .navigationTitle("DB クリア")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("降順", isOn: $showDescending)
                    .toggleStyle(.button)
                    .disabled(isDeleting)
                    .accessibilityIdentifier("db_clear_sort_toggle")
            }
        }
        .onAppear {
            loadDates()
        }
        // 単一日削除の確認アラート
        .alert("削除の確認",
               isPresented: $showDeleteSingleAlert,
               presenting: pendingDeleteDate) { date in
            Button("削除", role: .destructive) {
                performDeleteSingle(date: date)
            }
            Button("キャンセル", role: .cancel) {
                pendingDeleteDate = nil
            }
        } message: { date in
            Text("\(Self.dateFormatter.string(from: date)) の記録を削除します。この操作は取り消せません。")
        }
        // 全削除 1 段目アラート
        .alert("全データを削除しますか？",
               isPresented: Binding(
                   get: { deleteAllPhase == 1 },
                   set: { if !$0 { deleteAllPhase = 0 } }
               )) {
            Button("次に進む", role: .destructive) {
                deleteAllPhase = 2
            }
            Button("キャンセル", role: .cancel) {
                deleteAllPhase = 0
            }
        } message: {
            Text("全 \(dates.count) 件の移動記録を削除します。")
        }
        // 全削除 2 段目アラート
        .alert("本当に削除しますか？",
               isPresented: Binding(
                   get: { deleteAllPhase == 2 },
                   set: { if !$0 { deleteAllPhase = 0 } }
               )) {
            Button("全削除", role: .destructive) {
                deleteAllPhase = 0
                performDeleteAll()
            }
            Button("キャンセル", role: .cancel) {
                deleteAllPhase = 0
            }
        } message: {
            Text("この操作は取り消しできません。全ての移動記録（経路・ピン含む）が削除されます。")
        }
        // エラーアラート
        .alert("エラー",
               isPresented: Binding(
                   get: { errorMessage != nil },
                   set: { if !$0 { errorMessage = nil } }
               )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sortedDatesSection: some View {
        let sorted = showDescending ? dates.sorted(by: >) : dates.sorted(by: <)
        Section {
            ForEach(sorted, id: \.self) { date in
                HStack {
                    Text(Self.dateFormatter.string(from: date))
                    Spacer()
                    Button {
                        pendingDeleteDate = date
                        showDeleteSingleAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                    .accessibilityLabel("\(Self.dateFormatter.string(from: date)) の記録を削除")
                }
            }
        } header: {
            Text("移動記録（\(dates.count) 件）")
        }
    }

    @ViewBuilder
    private var deleteAllSection: some View {
        Section {
            Button(role: .destructive) {
                deleteAllPhase = 1
            } label: {
                HStack {
                    Spacer()
                    Text("全削除")
                    Spacer()
                }
            }
            .disabled(isDeleting || dates.isEmpty)
            .accessibilityIdentifier("db_clear_delete_all_button")
        } footer: {
            Text("全削除を実行すると、全ての日付の移動記録（経路・ピン含む）が完全に削除されます。")
                .font(.footnote)
        }
    }

    // MARK: - Actions

    /// DB から日付一覧を再取得して @State を更新する。
    private func loadDates() {
        do {
            dates = try repository.availableDates()
        } catch {
            errorMessage = "日付一覧の取得に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 単一日を削除してリストを即時更新する。
    private func performDeleteSingle(date: Date) {
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try repository.deleteTrip(on: date)
                loadDates()
            } catch {
                errorMessage = "削除に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// 全件削除してリストを即時更新する。
    private func performDeleteAll() {
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try repository.deleteAllTrips()
                loadDates()
            } catch {
                errorMessage = "全削除に失敗しました: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    // Preview 用インメモリコンテナを使って DBClearView を確認する。
    // #Preview マクロは @MainActor コンテキストで評価されるため try! は安全。
    let container = try! PersistenceController.makeInMemoryContainer()
    let repo = TripRepository(modelContext: container.mainContext)
    // container を明示的に参照して Preview 中の解放を防ぐ
    _ = container
    return NavigationStack {
        DBClearView(repository: repo)
    }
}
