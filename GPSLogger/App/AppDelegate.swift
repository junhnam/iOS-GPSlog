import UIKit

/// S6-018: AppDelegate を導入し、SLC 起床経路でも確実に DI を完了させる。
///
/// ### 背景
/// `GPSLoggerApp` が `@State private var dependencies = AppDependencyContainer()` で
/// DIコンテナを保持していた従来の設計では、バックグラウンド SLC 起床（アプリが kill
/// された後に OS が位置変化で再起動する経路）で `WindowGroup.body` が評価されるまで
/// `AppDependencyContainer` が生成されない「遅延評価問題」があった。
///
/// この経路では `CLLocationManager.delegate` が nil のまま `didUpdateLocations` が
/// 呼ばれ、位置情報が取りこぼされる可能性があった（S6-018 リリースブロッカー）。
///
/// ### 解決策
/// `UIApplicationDelegateAdaptor` で `AppDelegate` を接続し、
/// `application(_:didFinishLaunchingWithOptions:)` の中で — SwiftUI の描画サイクル
/// より確実に早い時点で — `AppDependencyContainer` を生成する。
/// SLC 起床経路は `UIApplication.LaunchOptionsKey.location` で検出し、
/// `LocationService.startTrackingFromSLC()` を呼んで追跡状態を復元する。
///
/// ### Swift 6 strict concurrency
/// クラス全体を `@MainActor` 隔離することで、`@MainActor` 必須の
/// `AppDependencyContainer.init()` を安全に呼べる。
/// `UIApplicationDelegate` メソッドは iOS ランタイムがメインスレッドで呼ぶため、
/// `@MainActor` 隔離と矛盾しない。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// DIコンテナ。`GPSLoggerApp.body` が参照するためオプショナルではなく
    /// 強参照の implicitly unwrapped で保持する。
    /// `application(_:didFinishLaunchingWithOptions:)` で必ず生成されるため
    /// アクセス時は必ず non-nil となる。
    var dependencies: AppDependencyContainer!

    /// SLC 起床経路の検出キー。
    /// `UIApplication.LaunchOptionsKey.location` は iOS 26.0 で deprecated となり、
    /// scene connection 経由の検出が推奨されている（Sprint 7 で正式対応予定）。
    /// 暫定的に raw value を直接使うことで deprecated 警告を回避しつつ既存挙動を維持する。
    private static let slcLaunchOptionsKey = UIApplication.LaunchOptionsKey(
        rawValue: "UIApplicationLaunchOptionsLocationKey"
    )

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // S6-018: バックグラウンド SLC 起床経路でも確実に DI を完了させる。
        // App.init() で生成すると @State 遅延評価のため WindowGroup.body 評価前には
        // 間に合わない。AppDelegate.didFinishLaunchingWithOptions は SwiftUI の
        // 描画サイクルより確実に先行するため、ここで生成する。
        dependencies = AppDependencyContainer()

        // S6-018: SLC 起床経路を検出し、LocationService に通知する。
        // launch options に SLC キーが含まれている場合、OS がアプリを kill した後に
        // SLC（Significant Location Changes）で再起動した経路。
        if launchOptions?[Self.slcLaunchOptionsKey] != nil {
            dependencies.locationService.startTrackingFromSLC()
        }

        return true
    }
}
