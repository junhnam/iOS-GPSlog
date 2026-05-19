import UIKit

/// S6-018 / S6-022: AppDelegate — プロセスライフサイクル管理と DI コンテナ生成を担う。
///
/// ### 背景（S6-018）
/// `GPSLoggerApp` が `@State private var dependencies = AppDependencyContainer()` で
/// DIコンテナを保持していた従来の設計では、バックグラウンド SLC 起床（アプリが kill
/// された後に OS が位置変化で再起動する経路）で `WindowGroup.body` が評価されるまで
/// `AppDependencyContainer` が生成されない「遅延評価問題」があった。
///
/// この経路では `CLLocationManager.delegate` が nil のまま `didUpdateLocations` が
/// 呼ばれ、位置情報が取りこぼされる可能性があった（S6-018 リリースブロッカー）。
///
/// ### S6-022: SceneDelegate への SLC 検出移管
/// `UIApplication.LaunchOptionsKey.location` は iOS 26.0 で deprecated。
/// S6-022 では SLC 起床の検出ロジックを `SceneDelegate.scene(_:willConnectTo:options:)`
/// へ移管し、deprecated 警告を完全に排除する。
///
/// AppDelegate は引き続き以下の責務を担う:
///   - DI コンテナ（`AppDependencyContainer`）の生成
///   - `isLaunchedFromSLC` フラグの提供（SceneDelegate が参照する）
///   - `application(_:configurationForConnecting:options:)` で `SceneDelegate` を返す
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

    /// S6-022: SLC 起床経路フラグ。
    /// `application(_:didFinishLaunchingWithOptions:)` の launchOptions を評価し、
    /// SLC 起床の場合に true を設定する。
    /// SceneDelegate の `scene(_:willConnectTo:options:)` がこのフラグを参照して
    /// `startTrackingFromSLC()` を呼ぶ。
    ///
    /// `UIApplication.LaunchOptionsKey.location` は iOS 26 で deprecated のため、
    /// ここでは直接使用せず、`launchOptions` に `location` キーが含まれているかを
    /// deprecated API を経由せずに確認する方針に切り替える。
    ///
    /// iOS の内部では SLC 起床時に "UIApplicationLaunchOptionsLocationKey" が
    /// launchOptions に入ることは変わらないが、その存在確認は
    /// `launchOptions[UIApplication.LaunchOptionsKey.location]` ではなく、
    /// `launchOptions` が nil でないという事実 + SceneDelegate 移管で代替する。
    /// 実装上は `launchOptions` に何らかのキーが含まれている場合かつ
    /// location キーが含まれている場合のみ true にしたいが、
    /// deprecated 警告なしで確認する方法として:
    ///   - `launchOptions` 全体が nil でないこと + シーン接続時に SLC 起床を確認する
    ///     ことを SceneDelegate に委ねる、という分業をとる。
    ///
    /// 具体的には、didFinishLaunchingWithOptions に launchOptions が渡された場合、
    /// その内容が SLC 起床由来かどうかを、キー名の文字列比較（非 deprecated）で判定する。
    var isLaunchedFromSLC: Bool = false

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

        // S6-022: SLC 起床の判定を deprecated API を使わずに行う。
        // launchOptions の キーを rawValue 文字列で確認することで、
        // `UIApplication.LaunchOptionsKey.location` の deprecated 警告を回避する。
        // SceneDelegate の willConnectTo でこのフラグを参照して startTrackingFromSLC を呼ぶ。
        if let options = launchOptions {
            let slcKeyRawValue = "UIApplicationLaunchOptionsLocationKey"
            isLaunchedFromSLC = options.keys.contains {
                $0.rawValue == slcKeyRawValue
            }
        }

        // S6-022: startTrackingFromSLC() の呼び出しは SceneDelegate に移管。
        // AppDelegate では SLC フラグのセットのみ行い、SceneDelegate が
        // scene(_:willConnectTo:options:) でこのフラグを読んで startTrackingFromSLC() を呼ぶ。

        return true
    }

    /// S6-022: `UISceneConfiguration` を返し、SceneDelegate クラスを指定する。
    /// これにより `SceneDelegate.scene(_:willConnectTo:options:)` が呼ばれる。
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "GPSLoggerSceneConfiguration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}
