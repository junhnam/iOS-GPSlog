import XCTest
import SwiftUI
import UIKit
@testable import GPSLogger

/// S4-006 受け入れ条件:
///   (a) 保存成功（didPickDocumentsAt）で URL が onComplete に渡る
///   (b) キャンセル（documentPickerWasCancelled）で空配列が onComplete に渡る
///
/// `UIDocumentPickerViewController` 自体の UI 側（保存ダイアログ）はシミュレータの
/// UI テストでしか確認できないため、Coordinator のデリゲートメソッドを直接呼んで
/// SwiftUI 連携部分のロジックを検証する。
@MainActor
final class DocumentPickerViewTests: XCTestCase {

    /// 実際にファイルを書き出した一時 URL を返す。
    /// `UIDocumentPickerViewController(forExporting:asCopy:)` は存在しないファイル URL では
    /// アサートに失敗するため、テスト時は最小サイズのバイト列を書き出してから渡す。
    private func makeRealTempCSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc_picker_test_\(UUID().uuidString).csv")
        try Data("test".utf8).write(to: url)
        return url
    }

    // MARK: - (a) 保存成功

    func test_coordinator_didPickDocuments_callsOnCompleteWithURLs() throws {
        let savedURLs = [try makeRealTempCSV(), try makeRealTempCSV()]
        defer { savedURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let exp = expectation(description: "onComplete called with URLs")
        var received: [URL]?

        let view = DocumentPickerView(urls: savedURLs) { urls in
            received = urls
            exp.fulfill()
        }
        let coordinator = view.makeCoordinator()
        let picker = UIDocumentPickerViewController(forExporting: savedURLs, asCopy: true)
        coordinator.documentPicker(picker, didPickDocumentsAt: savedURLs)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, savedURLs)
    }

    // MARK: - (b) キャンセル

    func test_coordinator_wasCancelled_callsOnCompleteWithEmpty() throws {
        let urls = [try makeRealTempCSV()]
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        let exp = expectation(description: "onComplete called with empty")
        var received: [URL]?

        let view = DocumentPickerView(urls: urls) { picked in
            received = picked
            exp.fulfill()
        }
        let coordinator = view.makeCoordinator()
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        coordinator.documentPickerWasCancelled(picker)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, [], "キャンセル時は空配列が返る")
    }
}
