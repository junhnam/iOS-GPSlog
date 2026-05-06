import XCTest
import SwiftData
import CoreLocation
@testable import GPSLogger

/// S4-005 のユニットテスト: CSVExportService の出力スキーマ・エンコード・エスケープ・インジェクション対策。
///
/// 5 ケース:
///   (a) 単一 trip の出力スキーマ
///   (b) UTF-8 BOM が先頭にある
///   (c) `,` `\n` `"` を含む値が正しくエスケープされる
///   (d) CSV インジェクション対策（=, +, -, @ で始まる値の先頭に `'`）
///   (e) routePoints / pins が空でもメタデータ行は出力される
@MainActor
final class CSVExportServiceTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run {
            retainedContainers.removeAll()
        }
        try await super.tearDown()
    }

    private func makeRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    // MARK: - (a) 出力スキーマ

    func test_exportTripRecord_writesAllSections() throws {
        let repo = try makeRepository()
        let trip = try repo.todayTrip()
        // 距離・時刻を埋める
        try repo.updateTotalDistance(of: trip, addingMeters: 1234.0)
        try repo.updateEnd(of: trip, at: trip.startedAt.addingTimeInterval(3600))

        // RoutePoint を 2 件
        let p1 = CLLocationOf(latitude: 35.658, longitude: 139.701, time: trip.startedAt)
        let p2 = CLLocationOf(latitude: 35.659, longitude: 139.702, time: trip.startedAt.addingTimeInterval(60))
        try repo.appendRoutePoint(p1, to: trip)
        try repo.appendRoutePoint(p2, to: trip)

        // Pin を 1 件
        let pin = PinRecord(latitude: 35.658, longitude: 139.701,
                            stayedFrom: trip.startedAt, stayedDurationSeconds: 720,
                            placeName: "Test Cafe",
                            placeURL: URL(string: "https://example.com/cafe"))
        try repo.appendPin(pin, to: trip)

        let sut = CSVExportService()
        let url = try sut.exportTripRecord(trip)
        XCTAssertEqual(url.pathExtension, "csv")
        let data = try Data(contentsOf: url)
        let body = bodyAfterBOM(data)
        XCTAssertTrue(body.contains("date,totalDistanceKm,startedAt,endedAt"),
                      "メタデータ行のヘッダ")
        XCTAssertTrue(body.contains("routePoint,timestamp,latitude,longitude"))
        XCTAssertTrue(body.contains("pin,arrivedAt,leftAt,latitude,longitude,placeName,placeURL,address"),
                      "S5-007: pin セクションヘッダに address 列を追加")
        XCTAssertTrue(body.contains("Test Cafe"))
        XCTAssertTrue(body.contains("https://example.com/cafe"))
    }

    // MARK: - (b) UTF-8 BOM

    func test_exportTripRecord_startsWithUTF8BOM() throws {
        let repo = try makeRepository()
        let trip = try repo.todayTrip()
        let sut = CSVExportService()
        let url = try sut.exportTripRecord(trip)
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 3)
        XCTAssertEqual(data[0], 0xEF)
        XCTAssertEqual(data[1], 0xBB)
        XCTAssertEqual(data[2], 0xBF)
    }

    // MARK: - (c) エスケープ（,, \n, ")

    func test_csvEscape_handlesSpecialCharacters() {
        // カンマ
        XCTAssertEqual(CSVExportService.escape("a,b"), "\"a,b\"")
        // ダブルクォート
        XCTAssertEqual(CSVExportService.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        // 改行
        XCTAssertEqual(CSVExportService.escape("line1\nline2"), "\"line1\nline2\"")
        // 通常文字列はそのまま
        XCTAssertEqual(CSVExportService.escape("Test Cafe"), "Test Cafe")
    }

    func test_exportTripRecord_escapesPlaceNameWithComma() throws {
        let repo = try makeRepository()
        let trip = try repo.todayTrip()
        let pin = PinRecord(latitude: 35.0, longitude: 139.0,
                            stayedFrom: trip.startedAt, stayedDurationSeconds: 600,
                            placeName: "Cafe, with comma\nand newline")
        try repo.appendPin(pin, to: trip)

        let sut = CSVExportService()
        let url = try sut.exportTripRecord(trip)
        let body = bodyAfterBOM(try Data(contentsOf: url))
        XCTAssertTrue(body.contains("\"Cafe, with comma\nand newline\""),
                      "カンマ + 改行を含む値はダブルクォートで囲まれる")
    }

    // MARK: - (d) CSV インジェクション対策

    func test_csvEscape_prefixesQuoteForInjectionStarts() {
        XCTAssertEqual(CSVExportService.escape("=SUM(1+1)"), "'=SUM(1+1)")
        XCTAssertEqual(CSVExportService.escape("+1234"), "'+1234")
        XCTAssertEqual(CSVExportService.escape("-1"), "'-1")
        XCTAssertEqual(CSVExportService.escape("@cmd"), "'@cmd")
        // インジェクション対象外の先頭文字は変化なし
        XCTAssertEqual(CSVExportService.escape("Normal"), "Normal")
    }

    func test_csvEscape_combinesInjectionAndQuoting() {
        // 先頭が = で内部にカンマ → シングルクォート + ダブルクォート囲み
        let result = CSVExportService.escape("=A,B")
        XCTAssertEqual(result, "\"'=A,B\"")
    }

    // MARK: - (e) 空の routePoints / pins でもメタデータ行は出る

    func test_exportTripRecord_outputsMetadata_whenNoPointsOrPins() throws {
        let repo = try makeRepository()
        let trip = try repo.todayTrip()
        let sut = CSVExportService()
        let url = try sut.exportTripRecord(trip)
        let body = bodyAfterBOM(try Data(contentsOf: url))
        XCTAssertTrue(body.contains("date,totalDistanceKm,startedAt,endedAt"))
        XCTAssertTrue(body.contains("routePoint,timestamp,latitude,longitude"))
        XCTAssertTrue(body.contains("pin,arrivedAt,leftAt,latitude,longitude,placeName,placeURL,address"),
                      "S5-007: pin セクションヘッダに address 列を追加")
    }

    // MARK: - (f) 全期間出力のファイル名

    func test_exportAllTrips_filenameContainsDate() throws {
        let repo = try makeRepository()
        let trip = try repo.todayTrip()
        let sut = CSVExportService()
        let url = try sut.exportAllTrips([trip])
        XCTAssertTrue(url.lastPathComponent.hasPrefix("gpslog_export_"),
                      "全期間出力のファイル名は gpslog_export_ で始まる")
        XCTAssertEqual(url.pathExtension, "csv")
    }

    // MARK: - Helpers

    /// UTF-8 BOM を取り除いた本文を String で返す（テスト検証用）。
    private func bodyAfterBOM(_ data: Data) -> String {
        guard data.count >= 3 else { return "" }
        let stripped = data.subdata(in: 3..<data.count)
        return String(data: stripped, encoding: .utf8) ?? ""
    }
}

// MARK: - Helpers

/// テスト用に CLLocation を簡潔に作るヘルパ（テストファイル内 private）。
private func CLLocationOf(latitude: Double, longitude: Double, time: Date) -> CLLocation {
    return CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                      altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                      timestamp: time)
}
