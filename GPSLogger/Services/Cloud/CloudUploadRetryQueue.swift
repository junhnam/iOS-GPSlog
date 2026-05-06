import Foundation
import Network
import SwiftData
import UserNotifications
import os

/// 通知センターの最小限のインタフェース（S5-006）。
///
/// `UNUserNotificationCenter.current()` を直接 retain せずプロトコル境界に置くことで、
/// テスト時に通知発火を検証できるようにする。
public protocol UploadFailureNotifying: Sendable {
    /// 5 回失敗した PendingUpload に対して 1 度だけ通知を送る。
    /// 内部で必要に応じて `UNUserNotificationCenter.requestAuthorization` を呼ぶ。
    func notifyFinalFailure(tripDate: Date, providerKind: CloudProviderKind) async
}

/// `UNUserNotificationCenter` を使う本番実装。
public struct UNNotificationFailureNotifier: UploadFailureNotifying {
    private static let identifier: String = "com.junhnam.gpslogger.cloudUploadFinalFailure"

    public init() {}

    public func notifyFinalFailure(tripDate: Date, providerKind: CloudProviderKind) async {
        let center = UNUserNotificationCenter.current()
        // 権限要求（拒否されたら通知をスキップする方針。受け入れ条件 S5-006）
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            granted = false
        }
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "クラウド同期に失敗しました"
        content.body = "\(providerKind.displayName) への同期が 5 回連続で失敗しました。設定から手動同期してください。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "\(Self.identifier).\(tripDate.timeIntervalSince1970)",
                                            content: content,
                                            trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // 通知追加失敗（権限取り消し・OS 内部エラー）はログのみで継続。
        }
    }
}

/// ネットワーク状態を監視する最小限のインタフェース（S5-006）。
/// テスト時はフェイクで「回復イベント」を任意のタイミングで送る。
public protocol NetworkPathObserving: Sendable {
    func startObserving(onPathChange: @escaping @Sendable (Bool) -> Void)
    func stopObserving()
}

/// `NWPathMonitor` を使う本番実装。
public final class NWPathNetworkObserver: NetworkPathObserving, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.junhnam.gpslogger.networkObserver")

    public init() {}

    public func startObserving(onPathChange: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            onPathChange(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    public func stopObserving() {
        monitor.cancel()
    }
}

/// クラウドアップロード失敗時のリトライキュー（S5-006）。
///
/// 役割:
///   - CloudUploadCoordinator から失敗した TripRecord を受け取り SwiftData に永続化
///   - アプリ起動時 + ネットワーク回復時にキューを処理
///   - 指数バックオフ（30s → 1m → 2m → 5m → 10m）で最大 5 回まで再試行
///   - 5 回失敗で `UploadFailureNotifying` 経由で通知発火
///
/// 設計判断:
///   - `@MainActor`（SwiftData ModelContext は Sprint 1〜4 で MainActor 統一）
///   - 通知は Sprint 5 では「初回起動時 + ネットワーク回復時」の 2 トリガーのみ
///     （Background Fetch / BGTaskScheduler は Sprint 6 以降で検討）
@MainActor
public final class CloudUploadRetryQueue: CloudUploadRetryEnqueuing {
    private let modelContext: ModelContext
    private let providers: [CloudProviderKind: any CloudStorageProvider]
    private let csvExporter: any CSVExporting
    private let appSettings: AppSettings
    private let notifier: any UploadFailureNotifying
    private let networkObserver: any NetworkPathObserving
    private let tripRepository: TripRepository

    /// 指数バックオフ秒数（受け入れ条件 S5-006）。
    /// インデックスが retryCount に対応する（0 回目失敗後 = 30 秒、4 回目失敗後 = 10 分）。
    public static let backoffSeconds: [TimeInterval] = [30, 60, 120, 300, 600]

    /// 最大リトライ回数（受け入れ条件 S5-006）。
    public static let maxAttempts: Int = 5

    private static let logger = Logger(subsystem: "com.junhnam.gpslogger",
                                       category: "CloudUploadRetryQueue")

    public init(modelContext: ModelContext,
                tripRepository: TripRepository,
                providers: [CloudProviderKind: any CloudStorageProvider],
                csvExporter: any CSVExporting = CSVExportingAdapter(),
                appSettings: AppSettings,
                notifier: any UploadFailureNotifying = UNNotificationFailureNotifier(),
                networkObserver: any NetworkPathObserving = NWPathNetworkObserver()) {
        self.modelContext = modelContext
        self.tripRepository = tripRepository
        self.providers = providers
        self.csvExporter = csvExporter
        self.appSettings = appSettings
        self.notifier = notifier
        self.networkObserver = networkObserver
    }

    // MARK: - CloudUploadRetryEnqueuing

    /// 失敗した TripRecord をリトライキューに登録する（CloudUploadCoordinator から呼ばれる）。
    /// 同じ tripDate のエントリが既にあれば retryCount を加算する。
    public func enqueue(tripDate: Date,
                        providerKind: CloudProviderKind,
                        lastError: CloudStorageError) async throws {
        let normalizedDate = Calendar.current.startOfDay(for: tripDate)
        if let existing = try fetchPending(matchingDate: normalizedDate) {
            existing.retryCount += 1
            existing.lastTriedAt = Date()
            existing.lastErrorMessage = describe(error: lastError)
            existing.providerKindRaw = providerKind.rawValue
            try modelContext.save()
        } else {
            let pending = PendingUpload(
                tripDate: normalizedDate,
                providerKind: providerKind,
                retryCount: 1, // CloudUploadCoordinator の最初の失敗を 1 回目とカウント
                lastTriedAt: Date(),
                lastErrorMessage: describe(error: lastError)
            )
            modelContext.insert(pending)
            try modelContext.save()
        }
        Self.logger.info("PendingUpload enqueue tripDate=\(normalizedDate) error=\(lastError)")
    }

    // MARK: - Public API

    /// 設定画面のバッジ用: 未送信件数を返す（S5-006 受け入れ条件）。
    public func pendingCount() throws -> Int {
        let descriptor = FetchDescriptor<PendingUpload>()
        return try modelContext.fetch(descriptor).count
    }

    /// 設定画面の「未同期分を手動同期」ボタンから呼ばれる即時実行（S5-006 受け入れ条件）。
    /// 全件を即時にリトライする。バックオフは無視する。
    /// 戻り値: 成功した件数（呼び出し側でトースト表示する想定）。
    @discardableResult
    public func processNow() async throws -> Int {
        return try await processQueue(ignoringBackoff: true)
    }

    /// アプリ起動時の自動処理。バックオフを尊重して未送信分を試す（受け入れ条件 S5-006）。
    @discardableResult
    public func processOnAppLaunch() async throws -> Int {
        return try await processQueue(ignoringBackoff: false)
    }

    /// ネットワーク監視を開始し、回復イベントごとに `processQueue` を起動する（受け入れ条件 S5-006）。
    public func startObservingNetwork() {
        networkObserver.startObserving { [weak self] satisfied in
            guard satisfied else { return }
            Task { @MainActor [weak self] in
                _ = try? await self?.processQueue(ignoringBackoff: false)
            }
        }
    }

    public func stopObservingNetwork() {
        networkObserver.stopObserving()
    }

    // MARK: - Internal

    /// SwiftData から未送信エントリを 1 件取得する。
    private func fetchPending(matchingDate date: Date) throws -> PendingUpload? {
        // iOS 26 SwiftData ノートに従い `#Predicate` ではなく取得後にメモリフィルタ。
        let descriptor = FetchDescriptor<PendingUpload>()
        let all = try modelContext.fetch(descriptor)
        return all.first(where: { Calendar.current.isDate($0.tripDate, inSameDayAs: date) })
    }

    /// キューを処理する。`ignoringBackoff` true なら全件即時実行、false なら次回実行時刻を尊重。
    private func processQueue(ignoringBackoff: Bool) async throws -> Int {
        let descriptor = FetchDescriptor<PendingUpload>()
        let pendings = try modelContext.fetch(descriptor)
        var successCount = 0
        let now = Date()

        for pending in pendings {
            // 通知済みの最終失敗エントリは触らない（手動同期では再試行する想定）
            if pending.notifiedFinalFailure && !ignoringBackoff {
                continue
            }
            // バックオフ判定
            if !ignoringBackoff {
                let nextAt = nextRetryDate(for: pending)
                if nextAt > now { continue }
            }
            // プロバイダ復元
            guard let kind = pending.providerKind,
                  let provider = providers[kind] else {
                continue
            }
            // TripRecord 取得（無ければエントリ削除して終了）
            guard let trip = try? tripRepository.trip(on: pending.tripDate) else {
                modelContext.delete(pending)
                try? modelContext.save()
                continue
            }
            // CSV データ生成
            let csvData: Data
            do {
                csvData = try csvExporter.csvData(for: trip)
            } catch {
                Self.logger.warning("リトライ中の CSV 出力失敗: \(error.localizedDescription)")
                continue
            }
            // アップロード
            let path = pathFor(date: pending.tripDate)
            do {
                _ = try await provider.uploadCSV(csvData, toPath: path)
                modelContext.delete(pending)
                try modelContext.save()
                successCount += 1
            } catch let error as CloudStorageError {
                pending.retryCount += 1
                pending.lastTriedAt = Date()
                pending.lastErrorMessage = describe(error: error)
                if pending.retryCount >= Self.maxAttempts && !pending.notifiedFinalFailure {
                    pending.notifiedFinalFailure = true
                    await notifier.notifyFinalFailure(tripDate: pending.tripDate, providerKind: kind)
                }
                try modelContext.save()
            } catch {
                // 想定外エラーは unknown 扱い
                pending.retryCount += 1
                pending.lastTriedAt = Date()
                pending.lastErrorMessage = error.localizedDescription
                try modelContext.save()
            }
        }
        return successCount
    }

    /// 次回リトライ予定時刻を返す（指数バックオフ）。
    func nextRetryDate(for pending: PendingUpload) -> Date {
        let index = max(0, min(pending.retryCount, Self.backoffSeconds.count - 1))
        let delta = Self.backoffSeconds[index]
        return pending.lastTriedAt.addingTimeInterval(delta)
    }

    private func pathFor(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return "\(GoogleDriveSyncService.rootFolderName)/\(formatter.string(from: date))/data.csv"
    }

    private func describe(error: CloudStorageError) -> String {
        switch error {
        case .notAuthenticated: return "未認証"
        case .authenticationExpired: return "認証期限切れ"
        case .userCancelled: return "ユーザーキャンセル"
        case .networkFailure(let m): return "ネットワーク失敗: \(m)"
        case .apiError(let s, let m): return "API エラー (\(s)): \(m)"
        case .keychainFailure(let m): return "Keychain 失敗: \(m)"
        case .unknown(let m): return "想定外: \(m)"
        }
    }
}
