import SwiftUI
import EventKit

/// 同期対象カレンダーを選ぶ画面（S4-004）。
///
/// 役割:
///   - `CalendarSyncService.availableCalendars()` で取得した EKCalendar 一覧を List 表示
///   - 選択した EKCalendar の identifier を `AppSettings.calendarIdentifier` に保存
///   - 同期 OFF 時はカレンダー一覧の選択を無効化（呼び出し側で `disabled(...)` 制御）
///
/// 設計判断:
///   - `EKCalendar` を直接 ForEach で扱うと Identifiable 適合がないため、
///     `calendarIdentifier` をキーにした薄いラップ構造体で扱う
///   - 権限が無い場合は availableCalendars() が空配列を返すため、案内文を表示
struct CalendarPickerView: View {
    @Bindable var settings: AppSettings
    let calendarService: CalendarSyncService

    /// 取得した利用可能カレンダー一覧。onAppear で 1 回だけロード。
    @State private var calendars: [CalendarRow] = []

    var body: some View {
        List {
            if calendars.isEmpty {
                Section {
                    Text("利用可能なカレンダーがありません。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("iOS の設定アプリでカレンダーへのアクセスを許可してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("対象カレンダー")
                }
            } else {
                Section {
                    ForEach(calendars) { row in
                        Button {
                            settings.calendarIdentifier = row.identifier
                        } label: {
                            HStack {
                                if let cgColor = row.cgColor {
                                    Circle()
                                        .fill(Color(cgColor: cgColor))
                                        .frame(width: 12, height: 12)
                                }
                                Text(row.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if settings.calendarIdentifier == row.identifier {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityIdentifier("calendar_picker_checkmark_\(row.identifier)")
                                }
                            }
                        }
                        .accessibilityIdentifier("calendar_picker_row_\(row.identifier)")
                    }
                } header: {
                    Text("対象カレンダー")
                } footer: {
                    Text("選んだカレンダーに、滞留地点を自動で予定として追加します。")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("対象カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCalendars()
        }
    }

    private func loadCalendars() {
        let raw = calendarService.availableCalendars()
        calendars = raw.map { CalendarRow(calendar: $0) }
    }
}

/// `EKCalendar` を SwiftUI ForEach 用にラップする薄い構造体。
/// `EKCalendar` は Identifiable に適合しないため、calendarIdentifier をキーにする。
struct CalendarRow: Identifiable, Hashable {
    let id: String
    let identifier: String
    let title: String
    let cgColor: CGColor?

    init(calendar: EKCalendar) {
        self.identifier = calendar.calendarIdentifier
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.cgColor = calendar.cgColor
    }

    /// テスト・プレビュー用の直接初期化。
    init(identifier: String, title: String, cgColor: CGColor? = nil) {
        self.identifier = identifier
        self.id = identifier
        self.title = title
        self.cgColor = cgColor
    }
}

#Preview {
    NavigationStack {
        CalendarPickerView(
            settings: AppSettings(),
            calendarService: CalendarSyncService(appSettings: AppSettings())
        )
    }
}
