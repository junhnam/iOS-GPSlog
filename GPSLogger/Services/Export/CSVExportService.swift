import Foundation
import os

/// CSV エクスポートの抽象化（S4-005）。
///
/// テスト容易性のため `CSVExportService` を直接モックするのではなく、
/// プロトコル境界を介して呼び出し側（ExportView / ExportViewModel）を疎結合に保つ。
@MainActor
protocol CSVExportProviderProtocol: Sendable {
    /// 単一 TripRecord を CSV に書き出し、書き込み済みファイル URL を返す（一時ディレクトリ）。
    func exportTripRecord(_ trip: TripRecord) throws -> URL

    /// 全 TripRecord を 1 ファイルに連結して書き出し、URL を返す（一時ディレクトリ）。
    func exportAllTrips(_ trips: [TripRecord]) throws -> URL
}

/// SwiftData の TripRecord / RoutePoint / PinRecord を CSV としてフラット化するサービス（S4-005）。
///
/// 設計方針:
///   - CLAUDE.md の DB テーブル定義（日付・移動ルート・ピン・開始終了・総移動距離）を
///     そのまま CSV のセクションとしてフラット化する
///   - 文字エンコードは UTF-8 BOM 付き（Excel 互換）
///   - 改行コードは `\r\n`（CRLF。Excel 互換 / RFC 4180 準拠）
///   - 値内の `,` `\n` `"` を含む場合はダブルクォートで囲み、内部の `"` は `""` に 2 重化
///   - CSV インジェクション対策: 値が `=`, `+`, `-`, `@` で始まる場合は先頭にシングルクォート `'`
///
/// 出力スキーマ（CLAUDE.md DB テーブル定義に対応）:
///   1. メタデータ行（1 件）
///      `date,totalDistanceKm,startedAt,endedAt`
///      （日付 / 総移動距離 km / 記録開始時刻 / 記録終了時刻）
///   2. 経路セクション（routePoints の件数分）
///      `routePoint,timestamp,latitude,longitude`
///      （行頭ラベル `routePoint` で経路点を識別）
///   3. ピンセクション（pins の件数分）
///      `pin,arrivedAt,leftAt,latitude,longitude,placeName,placeURL`
///      （行頭ラベル `pin`）
///
/// 全期間出力（exportAllTrips）はメタデータ + 経路 + ピンを TripRecord ごとに繰り返す。
@MainActor
final class CSVExportService: CSVExportProviderProtocol {
    /// 出力 CSV ファイルの拡張子。
    private static let fileExtension: String = "csv"
    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "CSVExportService")

    /// UTF-8 BOM。Excel が UTF-8 を判別するためのマーカー（受け入れ条件）。
    private static let utf8BOM: Data = Data([0xEF, 0xBB, 0xBF])

    /// CSV 内の改行（CRLF）。
    private static let crlf: String = "\r\n"

    /// ISO 8601 で日時を整形するフォーマッタ（タイムゾーンを保持する）。
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 日付（年月日のみ）の整形フォーマッタ。
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()

    init() {}

    // MARK: - Public API

    /// 単一 TripRecord を CSV に書き出す。
    func exportTripRecord(_ trip: TripRecord) throws -> URL {
        var data = Self.utf8BOM
        data.append(Self.body(for: trip).data(using: .utf8) ?? Data())
        let url = try Self.makeTemporaryURL(filename: Self.singleFilename(for: trip))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 全期間の TripRecord を 1 ファイルに連結して書き出す。
    /// ファイル名は `gpslog_export_<YYYY-MM-DD>.csv`（受け入れ条件）。
    func exportAllTrips(_ trips: [TripRecord]) throws -> URL {
        var data = Self.utf8BOM
        var combined = ""
        for (index, trip) in trips.enumerated() {
            if index > 0 {
                combined.append(Self.crlf) // 各 trip の間に空行を挟む
            }
            combined.append(Self.body(for: trip))
        }
        data.append(combined.data(using: .utf8) ?? Data())
        let today = Self.dateOnlyFormatter.string(from: Date())
        let url = try Self.makeTemporaryURL(filename: "gpslog_export_\(today).\(Self.fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Body builder

    /// 1 件分の TripRecord に対して、メタデータ行 + 経路 + ピンの CSV body を組み立てる。
    static func body(for trip: TripRecord) -> String {
        var lines: [String] = []

        // 1. メタデータ行: date,totalDistanceKm,startedAt,endedAt
        lines.append(buildHeader(name: "metadata", columns: ["date", "totalDistanceKm", "startedAt", "endedAt"]))
        lines.append(joinRow([
            escape(dateOnlyFormatter.string(from: trip.date)),
            escape(String(format: "%.2f", trip.totalDistanceKm)),
            escape(isoFormatter.string(from: trip.startedAt)),
            escape(trip.endedAt.map { isoFormatter.string(from: $0) } ?? "")
        ]))

        // 2. 経路セクション
        lines.append(buildHeader(name: "routePoints", columns: ["routePoint", "timestamp", "latitude", "longitude"]))
        let sortedRoutes = trip.routePoints.sorted { $0.timestamp < $1.timestamp }
        for point in sortedRoutes {
            lines.append(joinRow([
                "routePoint",
                escape(isoFormatter.string(from: point.timestamp)),
                escape(String(point.latitude)),
                escape(String(point.longitude))
            ]))
        }

        // 3. ピンセクション
        lines.append(buildHeader(name: "pins", columns: ["pin", "arrivedAt", "leftAt", "latitude", "longitude", "placeName", "placeURL"]))
        let sortedPins = trip.pins.sorted { $0.stayedFrom < $1.stayedFrom }
        for pin in sortedPins {
            let arrivedAt = isoFormatter.string(from: pin.stayedFrom)
            let leftAt = isoFormatter.string(from: pin.stayedFrom.addingTimeInterval(pin.stayedDurationSeconds))
            lines.append(joinRow([
                "pin",
                escape(arrivedAt),
                escape(leftAt),
                escape(String(pin.latitude)),
                escape(String(pin.longitude)),
                escape(pin.placeName ?? ""),
                escape(pin.placeURL?.absoluteString ?? "")
            ]))
        }

        return lines.joined(separator: crlf) + crlf
    }

    // MARK: - CSV escaping

    /// CSV 値を RFC 4180 + CSV インジェクション対策に従ってエスケープ。
    /// 公開（internal）にしてユニットテストから直接検証可能にする。
    static func escape(_ raw: String) -> String {
        // CSV インジェクション対策: 先頭が `=`, `+`, `-`, `@` ならシングルクォートを付与
        let injectionPrefixes: [Character] = ["=", "+", "-", "@"]
        var value = raw
        if let first = value.first, injectionPrefixes.contains(first) {
            value = "'" + value
        }

        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        if needsQuote {
            // 内部のダブルクォートを 2 重化
            value = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"" + value + "\""
        }
        return value
    }

    /// セクションヘッダー行を構築（カラム名を列挙する 1 行）。
    static func buildHeader(name: String, columns: [String]) -> String {
        return joinRow(columns.map { escape($0) })
    }

    /// カンマ区切りで 1 行を組み立てる。
    static func joinRow(_ cells: [String]) -> String {
        cells.joined(separator: ",")
    }

    // MARK: - File helpers

    private static func singleFilename(for trip: TripRecord) -> String {
        let dateStr = dateOnlyFormatter.string(from: trip.date)
        return "gpslog_\(dateStr).\(fileExtension)"
    }

    private static func makeTemporaryURL(filename: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(filename, isDirectory: false)
    }
}
