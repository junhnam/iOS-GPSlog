import Foundation
import SwiftData

/// アプリ全体の依存性を組み立てる DIコンテナ（S6-002）。
///
/// Sprint 5 までは `RootView.init` に直接散らばっていた組立処理を 1 箇所に集約する。
///
/// 設計判断（Swift 6 strict concurrency）:
///   - `@MainActor final class` を採用する。
///     AppSettings / TripRepository / CloudUploadRetryQueue / CloudUploadCoordinator が
///     すべて `@MainActor` 隔離のため、`Sendable` 構造体ベースにすると
///     内部の参照型プロパティで `Sendable` 違反が生じる。
///     `@MainActor final class` なら全プロパティが `@MainActor` 内で生成・保持され、
///     Swift 6 でも警告なく参照できる。
///   - ObservableObject / @StateObject は使わない。Container はビューモデルではなく
///     依存の組立器。RootView は `let` で保持する。
///
/// イニシャライザ:
///   - `init()` — 本番経路。`PersistenceController.shared.container.mainContext` を使う。
///   - `init(container:settings:googleDriveService:)` — テスト経路。
///     inMemory コンテナ・カスタム AppSettings・Spy/Stub サービスを差し込める。
@MainActor
final class AppDependencyContainer {

    // MARK: - Core

    /// ModelContainer の強参照（SwiftData の落とし穴メモ #2 に従い明示的に保持）。
    let modelContainer: ModelContainer

    // MARK: - Shared Services

    let appSettings: AppSettings
    let repository: TripRepository
    let calendarService: CalendarSyncService
    let googleDriveService: GoogleDriveSyncService
    let placeLookupService: PlaceLookupService
    let cloudUploadRetryQueue: CloudUploadRetryQueue
    let cloudUploadCoordinator: CloudUploadCoordinator
    let databaseAutoCleanupService: DatabaseAutoCleanupService
    /// 後追い滞留検知サービス（S6-010 B 案）。
    let retroactiveStayDetector: RetroactiveStayDetector
    let locationService: LocationService

    // MARK: - Providers (for SettingsView closures)

    let providers: [CloudProviderKind: any CloudStorageProvider]

    // MARK: - Production init

    /// 本番用イニシャライザ。すべての依存を本番実装で組み立てる。
    convenience init() {
        let container = PersistenceController.shared.container
        let driveService = GoogleDriveSyncService()
        self.init(
            modelContainer: container,
            settings: AppSettings(),
            googleDriveService: driveService
        )
    }

    // MARK: - DI init (for testing / overriding)

    /// テスト・カスタム経路用イニシャライザ。
    ///
    /// - Parameters:
    ///   - modelContainer: 使用する ModelContainer（inMemory コンテナを差し込める）。
    ///   - settings: 注入する AppSettings（テスト用 UserDefaults スイートを持つものを渡せる）。
    ///   - googleDriveService: GoogleDriveSyncService の実装（actor なので Spy 差し替えは別プロトコル経由が望ましいが、
    ///     本番と同インタフェースの GoogleDriveSyncService を受け取る形で統一する）。
    ///   - databaseAutoCleanupService: DB 自動消去サービス（S6-004）。nil = デフォルト実装を使う。
    init(modelContainer: ModelContainer,
         settings: AppSettings,
         googleDriveService: GoogleDriveSyncService,
         databaseAutoCleanupService: DatabaseAutoCleanupService? = nil) {
        self.modelContainer = modelContainer

        let context = modelContainer.mainContext
        let repository = TripRepository(modelContext: context)
        let calendarService = CalendarSyncService(appSettings: settings)
        let placeLookupService = PlaceLookupService()
        let providers: [CloudProviderKind: any CloudStorageProvider] = [.googleDrive: googleDriveService]
        let retryQueue = CloudUploadRetryQueue(
            modelContext: context,
            tripRepository: repository,
            providers: providers,
            appSettings: settings
        )
        let coordinator = CloudUploadCoordinator(
            providers: providers,
            appSettings: settings,
            retryQueue: retryQueue
        )
        // S6-004: DatabaseAutoCleanupService。差し込み引数があればそちらを使い、
        // なければデフォルト実装（FileManager 計測）を生成する。
        let cleanupService = databaseAutoCleanupService
            ?? DatabaseAutoCleanupService(appSettings: settings, modelContext: context)
        // S6-010: RetroactiveStayDetector。デフォルト config（radius=30m / minDuration=600s）で生成。
        let retroactiveDetector = RetroactiveStayDetector()
        let locationService = LocationService(
            repository: repository,
            retroactiveStayDetector: retroactiveDetector,
            placeProvider: placeLookupService,
            appSettings: settings,
            calendarSync: calendarService,
            cloudUploadCoordinator: coordinator,
            databaseAutoCleanup: cleanupService
        )

        self.appSettings = settings
        self.repository = repository
        self.calendarService = calendarService
        self.googleDriveService = googleDriveService
        self.placeLookupService = placeLookupService
        self.cloudUploadRetryQueue = retryQueue
        self.cloudUploadCoordinator = coordinator
        self.databaseAutoCleanupService = cleanupService
        self.retroactiveStayDetector = retroactiveDetector
        self.locationService = locationService
        self.providers = providers
    }
}
