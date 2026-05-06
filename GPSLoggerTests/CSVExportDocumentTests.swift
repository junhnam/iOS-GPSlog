import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import GPSLogger

/// S4-006 受け入れ条件:
///   (a) Data 入力で生成した CSVExportDocument が同じ Data を保持する
///   (b) 一時ファイル URL から生成できる
///   (c) URL 不在時はエラーが投げられる
///   (d) readableContentTypes / writableContentTypes が .commaSeparatedText を含む
///
/// 注意: `FileDocument.ReadConfiguration` / `WriteConfiguration` は SwiftUI 側の
/// 公開イニシャライザを持たないため、`init(configuration:)` / `fileWrapper(configuration:)`
/// の直接テストは省略し、SwiftUI ランタイムによる `.fileExporter` 統合で動作確認する。
/// ここではドキュメント生成と保持の単体検証に絞る。
@MainActor
final class CSVExportDocumentTests: XCTestCase {

    private static let sampleCSV: String = {
        // UTF-8 BOM + 1 行ヘッダ + 1 行データ
        let bom = "\u{FEFF}"
        return bom + "date,totalDistanceKm,startedAt,endedAt\r\n2026-05-06,12.34,09:00,10:30\r\n"
    }()

    private func sampleData() -> Data {
        Self.sampleCSV.data(using: .utf8)!
    }

    // MARK: - (a) Data 入力で生成

    func test_init_withData_holdsExactBytes() {
        let data = sampleData()
        let doc = CSVExportDocument(data: data)
        XCTAssertEqual(doc.data, data)
    }

    // MARK: - (b) 一時ファイル URL から生成

    func test_init_contentsOfURL_loadsBytes() throws {
        let data = sampleData()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("csv_export_test_\(UUID().uuidString).csv")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try CSVExportDocument(contentsOf: url)
        XCTAssertEqual(doc.data, data, "URL から読み込んだバイト列が一致する")
    }

    // MARK: - (c) URL 不在時のエラー

    func test_init_contentsOfURL_throwsForMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("csv_missing_\(UUID().uuidString).csv")
        XCTAssertThrowsError(try CSVExportDocument(contentsOf: missing),
                             "存在しない URL からの初期化はエラーを投げる")
    }

    // MARK: - (d) ContentType の宣言

    func test_contentTypes_areCommaSeparatedText() {
        XCTAssertTrue(CSVExportDocument.readableContentTypes.contains(.commaSeparatedText))
        XCTAssertTrue(CSVExportDocument.writableContentTypes.contains(.commaSeparatedText))
    }
}
