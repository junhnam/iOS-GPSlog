import Foundation
import SwiftData

/// DB 自動消去サービス（S6-004）。
///
/// 機能:
///   - 記録停止時（LocationService.stopUpdatingLocation の末尾）に 1 回だけ呼ばれる。
///   - AppSettings.dbAutoCleanupEnabled が false のときは cleanup() が即 return（no-op）。
///   - SwiftData の sqlite ファイルサイズを計測し、しきい値（GB）を超過した場合に
///     古い日付の TripRecord から順番に削除する。
///   - メモリフィルタ方式（ios26-swiftdata.md #3 の方針）。
///     #Predicate を使わず FetchDescriptor で全件取得 → Swift 側で日付昇順ソート → 削除。
///
/// バッテリー対策:
///   - バックグラウンドで定期実行しない（BGTaskScheduler も使わない）。
///   - cleanup() が呼ばれるのは記録停止トリガーのみ。
///
/// 設計判断（Swift 6 strict concurrency）:
///   - @MainActor final class を採用する。
///     AppSettings / TripRepository / ModelContext がすべて @MainActor 隔離のため、
///     同じ隔離ドメインで動作させることで Sendable 警告を回避する。
///   - 容量計測は「クロージャ差し込み」方式で抽象化し、テスト時は Spy で値を返せるようにする。
///     本番クロージャは FileManager.default.attributesOfItem を使う。
@MainActor
class DatabaseAutoCleanupService {

    // MARK: - Dependencies

    private let appSettings: AppSettings
    private let modelContext: ModelContext

    /// 容量計測クロージャ。本番は FileManager、テストは Spy で差し替える。
    /// 戻り値は現在の DB ファイルサイズ（バイト）。取得失敗時は 0 を返す。
    /// @MainActor クラス内のプロパティとして保持されるため、呼び出しは常に MainActor 上で行われる。
    private let measureDBBytes: () -> Int64

    // MARK: - Init

    /// 本番用イニシャライザ。
    /// sqlite ファイルサイズを FileManager で計測するクロージャを自動設定する。
    convenience init(appSettings: AppSettings, modelContext: ModelContext) {
        self.init(
            appSettings: appSettings,
            modelContext: modelContext,
            measureDBBytes: { Self.defaultMeasureDBBytes() }
        )
    }

    /// テスト / DI 用イニシャライザ。容量計測クロージャを差し込める。
    ///
    /// - Parameters:
    ///   - appSettings: 設定オブジェクト。
    ///   - modelContext: TripRecord を操作する ModelContext。
    ///   - measureDBBytes: 現在の DB ファイルサイズ（バイト）を返すクロージャ。
    ///     呼び出しは常に MainActor 上で行われる（@MainActor クラスのプロパティのため）。
    init(
        appSettings: AppSettings,
        modelContext: ModelContext,
        measureDBBytes: @escaping () -> Int64
    ) {
        self.appSettings = appSettings
        self.modelContext = modelContext
        self.measureDBBytes = measureDBBytes
    }

    // MARK: - Public API

    /// DB 容量をチェックし、しきい値超過時に古い TripRecord から削除する。
    ///
    /// - AppSettings.dbAutoCleanupEnabled が false なら即 return（no-op）。
    /// - TripRecord が 0 件なら即 return（no-op）。
    /// - しきい値以下なら削除しない。
    /// - しきい値を下回るまで date 昇順（古い順）に 1 件ずつ削除する。
    func cleanup() throws {
        guard appSettings.dbAutoCleanupEnabled else { return }

        let currentBytes = measureDBBytes()
        let thresholdBytes = Int64(appSettings.dbAutoCleanupThresholdGB * 1_073_741_824.0)

        guard currentBytes > thresholdBytes else { return }

        // 全 TripRecord を取得してメモリ上で日付昇順ソート（#Predicate は使わない）。
        let descriptor = FetchDescriptor<TripRecord>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard !all.isEmpty else { return }

        let sorted = all.sorted { $0.date < $1.date }

        // しきい値を下回るまで古い順に削除する。
        // 各削除後に容量を再計測する（FileManager のキャッシュがある場合もあるが
        // 正確さよりも実用的な近似を優先する）。
        var currentSizeBytes = currentBytes
        for record in sorted {
            guard currentSizeBytes > thresholdBytes else { break }
            modelContext.delete(record)
            try modelContext.save()
            // 削除後に容量を再計測して残容量を把握する。
            currentSizeBytes = measureDBBytes()
        }
    }

    // MARK: - Private Helpers

    /// 本番用の DB ファイルサイズ計測。
    /// SwiftData の sqlite ファイル（default.store）のバイト数を返す。
    /// ファイルが存在しない / 取得失敗時は 0 を返す。
    private static func defaultMeasureDBBytes() -> Int64 {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return 0
        }
        let storeURL = appSupport.appendingPathComponent("default.store")
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            return attrs[FileAttributeKey.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}
