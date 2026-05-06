import SwiftUI
import UIKit

/// `UIDocumentPickerViewController(forExporting:asCopy:)` の SwiftUI ラッパー（S4-006）。
///
/// 役割:
///   - SwiftUI 標準の `.fileExporter` で対応できないケース（複数 URL の同時エクスポートで
///     ユーザーが保存先フォルダを 1 度だけ選びたい等）の **フォールバック** として用意。
///   - 第一候補は `.fileExporter` + `CSVExportDocument`（受け入れ条件参照）。
///
/// 入出力:
///   - 入力: `urls` … CSVExportService が返す一時ファイル URL の配列（1 件以上）。
///   - 出力: `onComplete` … 保存成功時に保存先 URL（複数）を、キャンセル時に空配列を返す。
///
/// 注意:
///   - `asCopy: true` で開く（一時ファイルを移動せずコピー）。CSVExportService の一時ファイルは
///     呼び出し側のライフサイクルが完了するまで FileManager.default.temporaryDirectory に残る。
///   - SwiftUI 側からは `.sheet(isPresented:)` で表示する想定。
struct DocumentPickerView: UIViewControllerRepresentable {
    /// 書き出したい一時ファイル URL の配列。
    let urls: [URL]
    /// 保存完了 / キャンセル時のコールバック。引数は保存先 URL の配列（キャンセル時は空）。
    let onComplete: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // forExporting:asCopy: は iOS 14+ で提供。Sprint 4 では asCopy = true で運用。
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = urls.count > 1
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {
        // ピッカーは表示中に内容を変えない想定（SwiftUI 側で再生成される）
    }

    /// UIKit のデリゲートを SwiftUI に橋渡しする Coordinator。
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: ([URL]) -> Void

        init(onComplete: @escaping ([URL]) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onComplete(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete([])
        }
    }
}
