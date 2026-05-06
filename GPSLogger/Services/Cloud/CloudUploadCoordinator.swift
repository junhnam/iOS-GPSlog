import Foundation
import os

/// CSV エクスポート結果（Data）を作るための薄い境界（S5-005）。
///
/// `CSVExportService` は `URL` を返すため、CloudUploadCoordinator がそのまま
/// アップロード API（`Data` ベース）に渡しにくい。CSV 化のロジックは `CSVExportService.body(for:)`
/// を使い、UTF-8 BOM を頭に付けた `Data` を作るパターンに揃える。
///
/// テスト容易性のため、`CSVExporting` プロトコルを介して差し替え可能にする。
@MainActor
protocol CSVExporting: Sendable {
    /// 指定 TripRecord を CSV データ（UTF-8 BOM 含む）に変換する。
    func csvData(for trip: TripRecord) throws -> Data
}

/// `CSVExportService` を `CSVExporting` として包む本番実装。
@MainActor
struct CSVExportingAdapter: CSVExporting {
    private let service: CSVExportService

    init(service: CSVExportService = CSVExportService()) {
        self.service = service
    }

    func csvData(for trip: TripRecord) throws -> Data {
        let url = try service.exportTripRecord(trip)
        return try Data(contentsOf: url)
    }
}

/// 記録停止時に CSV をクラウドへ自動アップロードする責務を持つ Coordinator（S5-005）。
///
/// 役割:
///   - `AppSettings.cloudAutoSyncEnabled` と `AppSettings.cloudProviderKind` を見て
///     アップロード可否を判断する
///   - CSV 出力 → 階層パス組み立て → `CloudStorageProvider.uploadCSV(...)` 呼び出し
///   - アップロード失敗時はリトライキュー (S5-006) に渡す
///
/// 設計判断:
///   - `@MainActor` クラス（AppSettings の読み込みが MainActor 必須のため）
///   - 内部のアップロードは Task で actor 越しに await
///   - 失敗してもクラッシュさせず、ログ + リトライキュー登録で吸収
@MainActor
final class CloudUploadCoordinator {
    private let providers: [CloudProviderKind: any CloudStorageProvider]
    private let appSettings: AppSettings
    private let csvExporter: any CSVExporting
    private let retryQueue: (any CloudUploadRetryEnqueuing)?
    private let dateFormatter: DateFormatter
    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "CloudUploadCoordinator")

    /// 1 回の `uploadIfEnabled(for:)` 呼び出しに対する完了状態（S5-006 で参照）。
    enum Outcome: Sendable, Equatable {
        /// 自動同期 OFF / プロバイダ未選択 / トリップ未準備 などで何もしなかった。
        case skipped(reason: String)
        /// アップロード成功。
        case uploaded(result: CloudUploadResult)
        /// アップロード失敗。リトライ対象なら retryQueue に登録済み。
        case failed(error: CloudStorageError, enqueuedForRetry: Bool)

        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            switch (lhs, rhs) {
            case (.skipped(let l), .skipped(let r)): return l == r
            case (.uploaded(let l), .uploaded(let r)): return l == r
            case (.failed(let le, let lf), .failed(let re, let rf)):
                return le == re && lf == rf
            default: return false
            }
        }
    }

    init(providers: [CloudProviderKind: any CloudStorageProvider],
                appSettings: AppSettings,
                csvExporter: any CSVExporting = CSVExportingAdapter(),
                retryQueue: (any CloudUploadRetryEnqueuing)? = nil) {
        self.providers = providers
        self.appSettings = appSettings
        self.csvExporter = csvExporter
        self.retryQueue = retryQueue
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        self.dateFormatter = formatter
    }

    /// 自動同期 ON ならアップロードを試みる。OFF なら no-op。
    /// 結果は `Outcome` で返し、呼び出し側はテストで検証可能。
    @discardableResult
    func uploadIfEnabled(for trip: TripRecord) async -> Outcome {
        // 1. 設定チェック
        guard appSettings.cloudAutoSyncEnabled else {
            return .skipped(reason: "cloudAutoSyncEnabled == false")
        }
        guard let kind = appSettings.cloudProviderKind else {
            return .skipped(reason: "cloudProviderKind == nil")
        }
        guard let provider = providers[kind] else {
            return .skipped(reason: "未対応プロバイダ: \(kind.rawValue)")
        }

        // 2. CSV データ生成
        let csvData: Data
        do {
            csvData = try csvExporter.csvData(for: trip)
        } catch {
            Self.logger.warning("CSV 出力失敗: \(error.localizedDescription)")
            return .skipped(reason: "CSV 出力失敗: \(error.localizedDescription)")
        }

        // 3. アップロード経路の組み立て
        let path = pathFor(trip: trip)

        // 4. アップロード（actor 越し）
        do {
            let result = try await provider.uploadCSV(csvData, toPath: path)
            Self.logger.info("クラウド同期成功 path=\(path) fileID=\(result.fileID)")
            return .uploaded(result: result)
        } catch let error as CloudStorageError {
            return await handleUploadFailure(error: error, trip: trip, providerKind: kind, path: path)
        } catch {
            let wrapped = CloudStorageError.unknown(message: error.localizedDescription)
            return await handleUploadFailure(error: wrapped, trip: trip, providerKind: kind, path: path)
        }
    }

    /// `GPSログ/{YYYY-MM-DD}/data.csv` パスを返す。
    func pathFor(trip: TripRecord) -> String {
        let dateStr = dateFormatter.string(from: trip.date)
        return "\(GoogleDriveSyncService.rootFolderName)/\(dateStr)/data.csv"
    }

    private func handleUploadFailure(error: CloudStorageError,
                                     trip: TripRecord,
                                     providerKind: CloudProviderKind,
                                     path: String) async -> Outcome {
        Self.logger.warning("クラウド同期失敗 path=\(path) error=\(String(describing: error))")
        var enqueued = false
        if error.isRetryable, let queue = retryQueue {
            do {
                try await queue.enqueue(tripDate: trip.date,
                                        providerKind: providerKind,
                                        lastError: error)
                enqueued = true
            } catch {
                Self.logger.warning("リトライキュー登録失敗: \(error.localizedDescription)")
            }
        }
        return .failed(error: error, enqueuedForRetry: enqueued)
    }
}

/// 失敗したアップロードをリトライキューに積むための境界（S5-006）。
///
/// CloudUploadCoordinator は具体実装を知らず、本プロトコル経由で enqueue する。
/// Sprint 5 で `CloudUploadRetryQueue`（SwiftData 永続化）が同プロトコルを実装する。
protocol CloudUploadRetryEnqueuing: Sendable {
    func enqueue(tripDate: Date,
                 providerKind: CloudProviderKind,
                 lastError: CloudStorageError) async throws
}
