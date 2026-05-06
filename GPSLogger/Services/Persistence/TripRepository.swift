import Foundation
import CoreLocation
import SwiftData

/// TripRecord に対する取得・作成・更新を集約するリポジトリ（S2-003）。
///
/// LocationService（保存）／履歴画面（読み出し）／復元処理（読み出し）から
/// 共通で呼ばれる中心 API。ModelContext を DI で受け取るため、
/// 本番では `PersistenceController.shared.container.mainContext` を、
/// テストではインメモリコンテナの mainContext を注入する。
///
/// 全メソッドは `@MainActor` 前提で、`ModelContext` のスレッド安全性ルール
/// （main で扱う）に従う。
@MainActor
final class TripRepository {
    /// 注入された ModelContext。アプリ全体での共有 mainContext を想定。
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Errors

    /// リポジトリ層が返すエラー。境界（呼び出し側）でログ・UI 通知に変換する想定。
    enum TripRepositoryError: Error {
        /// SwiftData の fetch に失敗。原因は `underlying` に格納。
        case fetchFailed(underlying: Error)
        /// SwiftData の save に失敗。原因は `underlying` に格納。
        case saveFailed(underlying: Error)
    }

    // MARK: - Read

    /// 当日（0 時に正規化された Date）の TripRecord を取得する。
    /// `creatingIfMissing` が true なら、無い場合に新規作成して返す。
    /// false なら見つからなければ nil を返す（復元処理で使う）。
    func todayTrip(creatingIfMissing: Bool) throws -> TripRecord? {
        let today = Calendar.current.startOfDay(for: Date())
        if let existing = try trip(on: today) {
            return existing
        }
        guard creatingIfMissing else { return nil }

        let new = TripRecord(date: today, startedAt: Date())
        modelContext.insert(new)
        do {
            try modelContext.save()
        } catch {
            throw TripRepositoryError.saveFailed(underlying: error)
        }
        return new
    }

    /// 受け入れ条件 API（オーバーロード）: `creatingIfMissing: true` 専用版。
    /// 利用側で nil を意識しなくて良いよう、必ず TripRecord を返す。
    func todayTrip() throws -> TripRecord {
        // creatingIfMissing: true を指定した場合 nil は返らないので強制アンラップで安全。
        guard let trip = try todayTrip(creatingIfMissing: true) else {
            // 防御的: creatingIfMissing でも nil を返す経路はないはずだが、
            // 仕様変更時に備えて save 失敗扱いにする。
            throw TripRepositoryError.fetchFailed(underlying: NSError(domain: "TripRepository",
                                                                      code: -1,
                                                                      userInfo: [NSLocalizedDescriptionKey: "todayTrip(creatingIfMissing:true) returned nil unexpectedly"]))
        }
        return trip
    }

    /// 指定日付（時刻付きでも内部で 0 時に正規化）の TripRecord を取得。
    /// 該当日付のレコードが無ければ nil。
    ///
    /// 実装メモ: SwiftData の `#Predicate` で Date を比較するパターンは
    /// 環境によって不安定（クラッシュ報告がある）なため、ここでは全件取得して
    /// first(where:) でメモリ内フィルタする。本アプリは「1 日 1 レコード」前提で
    /// 全件でも数十〜数百レコードに収まるため性能上も問題ない。
    func trip(on date: Date) throws -> TripRecord? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<TripRecord>()
        do {
            let results = try modelContext.fetch(descriptor)
            return results.first(where: { $0.date == day })
        } catch {
            throw TripRepositoryError.fetchFailed(underlying: error)
        }
    }

    /// 直近 N 件の TripRecord を日付降順で返す（履歴画面用）。
    /// limit のデフォルトは 30 日（おおよそ 1 ヶ月分）。
    func recentTrips(limit: Int = 30) throws -> [TripRecord] {
        var descriptor = FetchDescriptor<TripRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw TripRepositoryError.fetchFailed(underlying: error)
        }
    }

    // MARK: - Write

    /// 経路点を追加して TripRecord に紐付ける。
    /// 距離加算は別途 `updateTotalDistance` を呼ぶ前提（責務分離）。
    /// CLLocation 自体を受け取り、緯度・経度・timestamp に分解して RoutePoint を作る。
    func appendRoutePoint(_ location: CLLocation, to trip: TripRecord) throws {
        let point = RoutePoint(latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude,
                               timestamp: location.timestamp,
                               trip: trip)
        modelContext.insert(point)
        do {
            try modelContext.save()
        } catch {
            throw TripRepositoryError.saveFailed(underlying: error)
        }
    }

    /// 既に作成済みの PinRecord を TripRecord に紐付けて永続化する。
    /// PinRecord 自体の生成（位置・滞留時間の決定）は呼び出し側（StayDetector）が行う。
    func appendPin(_ pin: PinRecord, to trip: TripRecord) throws {
        pin.trip = trip
        modelContext.insert(pin)
        do {
            try modelContext.save()
        } catch {
            throw TripRepositoryError.saveFailed(underlying: error)
        }
    }

    /// 記録終了時刻を書き込む。トリガーモードでの停止操作や、日付切り替え時に呼ぶ。
    func updateEnd(of trip: TripRecord, at date: Date) throws {
        trip.endedAt = date
        do {
            try modelContext.save()
        } catch {
            throw TripRepositoryError.saveFailed(underlying: error)
        }
    }

    /// 累積距離をメートル単位で加算保存する。
    /// 追加した移動セグメントの距離（CLLocation.distance(from:) の結果）を渡す。
    func updateTotalDistance(of trip: TripRecord, addingMeters meters: Double) throws {
        trip.totalDistanceMeters += meters
        do {
            try modelContext.save()
        } catch {
            throw TripRepositoryError.saveFailed(underlying: error)
        }
    }

    /// PinRecord のプロパティを直接書き換えた後に呼び出して、ModelContext を保存する（S3-007）。
    /// 例: MKLocalSearch で取得した placeName / placeURL を Pin に書き戻したあと。
    /// 個別フィールドへの setter を増やすのではなく汎用 save にする方針（PinRecord 自体は @Model なので
    /// プロパティ変更は context に追跡される）。
    func savePinUpdates() throws {
        do {
            try modelContext.save()
        } catch {
            throw TripRepositoryError.saveFailed(underlying: error)
        }
    }
}
