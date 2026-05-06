import Foundation
import SwiftData

/// アプリ全体で共有する SwiftData コンテナのラッパー。
///
/// - 本番では `PersistenceController.shared.container` を `WindowGroup` に
///   `.modelContainer(_:)` 経由で渡す。
/// - スキーマ初期化に失敗した場合（破損ファイル等）は `fatalError` させず、
///   インメモリコンテナにフォールバックして起動を継続する。
///   これにより「永続化はできないが UI は触れる」という最低限の救済を行う
///   （要件: 受け入れ条件「警告ログを出してインメモリにフォールバック」）。
/// - テストでは `PersistenceController.makeInMemoryContainer()` でクリーンな
///   インメモリコンテナを毎回生成して利用する。
@MainActor
final class PersistenceController {
    /// アプリ起動から終了までライフタイムを共有するシングルトン。
    static let shared = PersistenceController()

    /// 実体となる ModelContainer。SwiftUI の `.modelContainer(_:)` に渡す。
    let container: ModelContainer

    /// 通常初期化（本番用）。
    /// 失敗した場合はインメモリにフォールバックし、起動を継続する。
    private init() {
        self.container = Self.makeContainer()
    }

    /// 本番用 ModelContainer を構築する。失敗時はインメモリにフォールバック。
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            TripRecord.self,
            RoutePoint.self,
            PinRecord.self,
            PendingUpload.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // SwiftData のスキーマ移行失敗・ファイル破損等。
            // クラッシュを避け、警告ログ出力のうえインメモリで継続。
            print("[PersistenceController] WARNING: Failed to initialize persistent ModelContainer (\(error.localizedDescription)). Falling back to in-memory store. Data will not survive app restart this session.")
            do {
                let memoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                // インメモリにも失敗するケースは事実上発生しないが、
                // ここまで来た場合はもう起動継続不可能。
                fatalError("[PersistenceController] FATAL: Even in-memory ModelContainer failed to initialize: \(error)")
            }
        }
    }

    /// ユニットテスト用にクリーンなインメモリ ModelContainer を生成する。
    /// テストごとに呼べば、テスト間でデータが混ざらない。
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            TripRecord.self,
            RoutePoint.self,
            PinRecord.self,
            PendingUpload.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
