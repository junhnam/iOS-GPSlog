import SwiftUI
import UniformTypeIdentifiers

/// CSV エクスポート画面（S4-007）。
///
/// 役割:
///   - 「今日の記録だけ書き出す」「全期間の記録を書き出す」の 2 ボタンを提供
///   - ボタン押下時に CSV 出力（S4-005）→ `.fileExporter` 起動（S4-006）の順で連携
///   - 進行中は ProgressView を表示し、完了で結果メッセージを Alert 表示
///
/// 設計判断:
///   - `CSVExportService` 型に直接依存せず、`@MainActor` クロージャで疎結合化することで
///     S4-005 の最終的な protocol 名や引数仕様が変わっても影響を受けないようにしている。
///   - テスト時は `actor` ベースのカウンタを掴んだフェイクを差し込み、ボタン押下で
///     正しいメソッドが呼ばれるか検証できる。
struct ExportView: View {
    /// 今日の TripRecord を CSV に書き出して URL を返すクロージャ。
    /// 当日 trip が無ければ nil を返す（呼び出し側で disabled 制御済の想定だが二重防御）。
    let exportTodayTrip: @MainActor () async throws -> URL?

    /// 全期間の TripRecord を CSV に書き出して URL を返すクロージャ。
    /// 0 件なら nil を返す。
    let exportAllTrips: @MainActor () async throws -> URL?

    /// 永続化されている TripRecord の件数（disabled 制御用）。
    let tripCount: @MainActor () -> Int

    @State private var isExporting: Bool = false
    @State private var resultMessage: String?
    @State private var pendingDocument: CSVExportDocument?
    @State private var pendingFilename: String = ""
    @State private var showFileExporter: Bool = false

    var body: some View {
        Form {
            Section {
                Text("CSV ファイルとして書き出します。Excel やスプレッドシートで開けます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                exportButton(
                    title: "今日の記録だけ書き出す",
                    accessibilityID: "export_today_button",
                    filenamePrefix: "gpslog_today",
                    action: exportTodayTrip
                )
            }

            Section {
                exportButton(
                    title: "全期間の記録を書き出す",
                    accessibilityID: "export_all_button",
                    filenamePrefix: "gpslog_all",
                    action: exportAllTrips
                )
            } footer: {
                if tripCount() == 0 {
                    Text("記録がまだありません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("エクスポート")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showFileExporter,
            document: pendingDocument,
            contentType: .commaSeparatedText,
            defaultFilename: pendingFilename
        ) { result in
            handleFileExporterResult(result)
        }
        .alert("エクスポート結果",
               isPresented: Binding(
                   get: { resultMessage != nil },
                   set: { if !$0 { resultMessage = nil } }
               ),
               actions: {
                   Button("OK", role: .cancel) { resultMessage = nil }
               },
               message: {
                   if let message = resultMessage {
                       Text(message)
                   }
               })
    }

    @ViewBuilder
    private func exportButton(title: String,
                              accessibilityID: String,
                              filenamePrefix: String,
                              action: @escaping @MainActor () async throws -> URL?) -> some View {
        Button {
            runExport(filenamePrefix: filenamePrefix, action: action)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if isExporting {
                    ProgressView()
                        .accessibilityIdentifier("\(accessibilityID)_progress")
                }
            }
        }
        .accessibilityIdentifier(accessibilityID)
        .disabled(isExporting || tripCount() == 0)
    }

    private func runExport(filenamePrefix: String,
                           action: @escaping @MainActor () async throws -> URL?) {
        guard !isExporting else { return }
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                guard let url = try await action() else {
                    resultMessage = "書き出し対象の記録がありません。"
                    return
                }
                let document = try CSVExportDocument(contentsOf: url)
                pendingDocument = document
                pendingFilename = Self.makeFilename(prefix: filenamePrefix)
                showFileExporter = true
            } catch {
                resultMessage = "書き出しに失敗しました: \(error.localizedDescription)"
            }
        }
    }

    private func handleFileExporterResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            resultMessage = "保存しました。"
        case .failure(let error):
            // ユーザーキャンセルは macOS 系では .userCancelled になる。
            // iOS では .fileExporter キャンセル時に `failure(.cancelled)` 相当の Error が来るため、
            // 文言を 1 種類にまとめる（成功・失敗で十分判別可能）。
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError {
                resultMessage = "保存をキャンセルしました。"
            } else {
                resultMessage = "保存に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// ファイル名生成（gpslog_today_2026-05-06.csv の形式）。
    private static func makeFilename(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "\(prefix)_\(dateString).csv"
    }
}

#Preview {
    NavigationStack {
        ExportView(
            exportTodayTrip: {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview_today.csv")
                try Data("date\n2026-05-06\n".utf8).write(to: url)
                return url
            },
            exportAllTrips: {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview_all.csv")
                try Data("date\n2026-05-06\n".utf8).write(to: url)
                return url
            },
            tripCount: { 1 }
        )
    }
}
