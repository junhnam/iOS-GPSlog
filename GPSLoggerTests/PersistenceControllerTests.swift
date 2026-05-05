import XCTest
import SwiftData
@testable import GPSLogger

/// PersistenceController と SwiftData スキーマの基本動作確認テスト（S2-002）。
///
/// 検証観点:
///   - インメモリコンテナを生成して TripRecord を 1 件 insert → fetch で取り出せる
///   - 同一 `date`（ユニーク制約）の TripRecord を 2 件 insert したとき、
///     SwiftData がユニーク制約に従って 1 件に upsert すること
@MainActor
final class PersistenceControllerTests: XCTestCase {

    func test_makeInMemoryContainer_canInsertAndFetchTripRecord() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let day = Calendar.current.startOfDay(for: Date())
        let trip = TripRecord(date: day, startedAt: Date())
        context.insert(trip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.date, day)
        XCTAssertEqual(fetched.first?.totalDistanceMeters, 0)
    }

    /// 同じ日付の TripRecord を 2 回 insert したとき、ユニーク制約により
    /// 1 件に統合される（または 2 件目の insert で上書きされる）ことを検証する。
    /// SwiftData はデフォルトで upsert 挙動をとるため、最終的な fetch 結果は 1 件になる想定。
    func test_uniqueDateConstraint_upserts_onConflict() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let day = Calendar.current.startOfDay(for: Date())
        let trip1 = TripRecord(date: day, startedAt: Date(), totalDistanceMeters: 100)
        context.insert(trip1)
        try context.save()

        let trip2 = TripRecord(date: day, startedAt: Date(), totalDistanceMeters: 999)
        context.insert(trip2)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TripRecord>())
        // ユニーク制約により 1 件のみ残る（upsert 挙動）。
        XCTAssertEqual(fetched.count, 1, "Same-date TripRecord should be deduplicated by unique constraint")
    }

    func test_relationships_cascadeDelete_removesChildren() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let day = Calendar.current.startOfDay(for: Date())
        let trip = TripRecord(date: day, startedAt: Date())
        context.insert(trip)

        let point = RoutePoint(latitude: 35.0, longitude: 139.0, timestamp: Date(), trip: trip)
        let pin = PinRecord(latitude: 35.0, longitude: 139.0,
                            stayedFrom: Date(), stayedDurationSeconds: 600,
                            trip: trip)
        context.insert(point)
        context.insert(pin)
        try context.save()

        // 親を削除すると cascade で子も消える。
        context.delete(trip)
        try context.save()

        let pointsLeft = try context.fetch(FetchDescriptor<RoutePoint>())
        let pinsLeft = try context.fetch(FetchDescriptor<PinRecord>())
        XCTAssertEqual(pointsLeft.count, 0, "RoutePoint should be cascade-deleted")
        XCTAssertEqual(pinsLeft.count, 0, "PinRecord should be cascade-deleted")
    }
}
