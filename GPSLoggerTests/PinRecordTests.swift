import XCTest
import SwiftData
@testable import GPSLogger

/// S5-007: PinRecord.address フィールドの初期化動作を検証する。
///
/// ケース:
///   (a) address 引数を渡さない場合は nil
///   (b) address 引数を渡した場合はそのまま保持される
///   (c) SwiftData コンテナに保存して再取得しても address が保持される（自動マイグレーション互換）
@MainActor
final class PinRecordTests: XCTestCase {

    /// ios26-swiftdata.md ノートに従い ModelContainer を強参照保持する。
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run {
            retainedContainers.removeAll()
        }
        try await super.tearDown()
    }

    // MARK: - (a) address 未指定

    func test_init_withoutAddress_isNil() {
        let pin = PinRecord(latitude: 35.658,
                            longitude: 139.701,
                            stayedFrom: Date(timeIntervalSince1970: 1_700_000_000),
                            stayedDurationSeconds: 600)
        XCTAssertNil(pin.address)
    }

    // MARK: - (b) address 指定

    func test_init_withAddress_keepsValue() {
        let pin = PinRecord(latitude: 35.658,
                            longitude: 139.701,
                            stayedFrom: Date(timeIntervalSince1970: 1_700_000_000),
                            stayedDurationSeconds: 600,
                            address: "東京都 渋谷区 道玄坂 2-29-5")
        XCTAssertEqual(pin.address, "東京都 渋谷区 道玄坂 2-29-5")
    }

    // MARK: - (c) SwiftData 永続化と取り出し

    func test_swiftData_persistsAndRestoresAddress() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        let context = container.mainContext

        let pin = PinRecord(latitude: 35.658,
                            longitude: 139.701,
                            stayedFrom: Date(timeIntervalSince1970: 1_700_000_000),
                            stayedDurationSeconds: 600,
                            address: "東京都 渋谷区")
        context.insert(pin)
        try context.save()

        let descriptor = FetchDescriptor<PinRecord>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.address, "東京都 渋谷区")
    }
}
