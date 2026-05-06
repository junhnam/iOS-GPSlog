import SwiftUI
import UniformTypeIdentifiers

/// `.fileExporter` 用の薄い `FileDocument` 実装（S4-006）。
///
/// 役割:
///   - CSV のバイト列を保持し、SwiftUI 標準の `.fileExporter(...)` に渡せる形にラップする。
///   - 入力は `Data`（または一時ファイル `URL`）。CSVExportService（S4-005）が出力した
///     ファイル URL から読み込んで初期化する用途を想定。
///
/// 設計判断:
///   - `readableContentTypes` / `writableContentTypes` は `.commaSeparatedText` のみ。
///     CSV 以外の保存・読み込みは想定しない。
///   - 大きな CSV でも SwiftUI が `FileWrapper` を適切に扱うため、本構造体は単純に `Data` を保持する。
///     Sprint 6 で 1GB 級の連結出力を扱う場合は `OutputStream` ベースの拡張版を検討する。
///   - `init(configuration:)` は読み込み用で、本アプリは出力主体だが FileDocument プロトコルが
///     要求するため最低限の実装を提供する。
struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    /// CSV のバイト列。UTF-8 BOM 付きで CSVExportService から渡される想定。
    let data: Data

    /// バイト列から直接生成するイニシャライザ（出力時に使用）。
    init(data: Data) {
        self.data = data
    }

    /// 一時ファイル URL から生成するイニシャライザ（CSVExportService の戻り値を渡す想定）。
    /// 読み込み失敗時は `CocoaError` を投げる。
    init(contentsOf url: URL) throws {
        self.data = try Data(contentsOf: url)
    }

    /// `.fileExporter` が読み込み時に使うイニシャライザ。
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    /// `.fileExporter` が書き出し時に使うメソッド。
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
