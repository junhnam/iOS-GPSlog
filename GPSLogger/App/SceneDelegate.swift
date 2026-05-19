import UIKit

/// S6-022: SceneDelegate — scene connection 経由の SLC 起床検出（iOS 26 推奨経路）。
///
/// ### 背景
/// `UIApplication.LaunchOptionsKey.location` は iOS 26.0 で deprecated となり、
/// Apple の推奨は `UIWindowSceneDelegate.scene(_:willConnectTo:options:)` 内で
/// `UIScene.ConnectionOptions` の `userActivities` / `handoffUserActivityType` ではなく、
/// iOS 26 の `UIScene.ActivationConditions` や通常起動検出を使うことに移行した。
///
/// SLC 起床をシーン接続経由で検出する正式な方法は、
/// `UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:)` の
/// `launchOptions` ではなく、`scene(_:willConnectTo:options:)` の
/// `connectionOptions.userActivities` を確認するか、
/// `application(_:willFinishLaunchingWithOptions:)` で判定した結果を
/// AppDelegate 経由で SceneDelegate に引き渡す方式が取れる。
///
/// 本実装では AppDelegate が SLC 起床フラグを保持し、
/// SceneDelegate がそれを読んで `startTrackingFromSLC()` を呼ぶ設計を採用する。
/// これにより AppDelegate 内の raw value 直接参照（deprecated 警告の原因）を排除できる。
///
/// ### 役割分担（S6-022 確立）
/// - `AppDelegate`:  プロセスライフサイクル / DI コンテナ生成 / SLC 起床フラグ判定 /
///                   `configurationForConnecting` で SceneDelegate を返す
/// - `SceneDelegate`: scene 接続時の SLC 起床検出 / `startTrackingFromSLC()` 呼び出し
///
/// ### Swift 6 strict concurrency
/// `@MainActor` 隔離で `UIApplicationDelegate` / `UIWindowSceneDelegate` の
/// MainThread 必須メソッドを安全に呼ぶ。
@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    // MARK: - UIWindowSceneDelegate

    /// scene が接続されるタイミングで SLC 起床かどうかを判定し、
    /// 必要であれば `startTrackingFromSLC()` を呼ぶ。
    ///
    /// `connectionOptions` には通常起動 / SLC 起床 / Push 通知起床など
    /// 起動理由に応じた情報が入っている。
    /// AppDelegate が `didFinishLaunchingWithOptions` で判定した `isLaunchedFromSLC` フラグを
    /// 参照することで、SceneDelegate 側でも SLC 起床経路を正確に判断できる。
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // AppDelegate から DI コンテナ + SLC フラグを取得する。
        // @UIApplicationDelegateAdaptor で AppDelegate が確実に生成済みのため、
        // キャストは安全。
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }

        // DI コンテナが生成済みであることを確認する。
        // application(_:didFinishLaunchingWithOptions:) より willConnectTo が
        // 後に呼ばれるため、生成済みのはず。
        guard appDelegate.dependencies != nil else {
            return
        }

        // S6-022: AppDelegate が判定した SLC 起床フラグを参照し、
        // SceneDelegate 側で startTrackingFromSLC() を呼ぶ。
        // これにより AppDelegate の raw value 直接参照（deprecated 警告の原因）を
        // SceneDelegate に移管し、完全に排除する。
        if appDelegate.isLaunchedFromSLC {
            appDelegate.dependencies.locationService.startTrackingFromSLC()
        }
    }
}
