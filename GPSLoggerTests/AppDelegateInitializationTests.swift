import XCTest
import UIKit
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S6-018 受け入れ条件:
///   (1) AppDelegate.application(_:didFinishLaunchingWithOptions:) で dependencies が生成される
///   (2) launchOptions に .location が含まれる場合、startTrackingFromSLC() が呼ばれる
///   (3) launchOptions に .location が含まれない場合、startTrackingFromSLC() は呼ばれない
@MainActor
final class AppDelegateInitializationTests: XCTestCase {

    // MARK: - (1) dependencies が初期化される（S6-018）

    /// application(_:didFinishLaunchingWithOptions:) が呼ばれた後、
    /// AppDelegate.dependencies が non-nil になることを検証する。
    func test_didFinishLaunchingWithOptions_initializesDependencies_S6018() {
        let sut = AppDelegate()

        // didFinishLaunchingWithOptions を模擬呼び出し
        let result = sut.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertTrue(result,
            "application(_:didFinishLaunchingWithOptions:) は true を返す（S6-018）")
        XCTAssertNotNil(sut.dependencies,
            "didFinishLaunchingWithOptions 後 dependencies が non-nil になる（S6-018）")
        XCTAssertNotNil(sut.dependencies.locationService,
            "dependencies.locationService が non-nil になる（S6-018）")
    }

    // MARK: - (2) launchOptions に .location がある場合は isLaunchedFromSLC=true になる（S6-018 / S6-022 更新）

    /// バックグラウンド SLC 起床経路（launchOptions[.location] != nil）のとき、
    /// AppDelegate.isLaunchedFromSLC が true になることを検証する。
    ///
    /// ### S6-022 更新
    /// 旧テスト (S6-018) では AppDelegate が直接 `startTrackingFromSLC()` を呼び、
    /// `isMonitoringSignificantChanges=true` になることを確認していた。
    ///
    /// S6-022 で SLC 起床の `startTrackingFromSLC()` 呼び出しが SceneDelegate に移管されたため、
    /// AppDelegate は `isLaunchedFromSLC=true` を設定するのみとなった。
    /// SceneDelegate 経由の呼び出し検証は `SceneDelegateConnectionTests` で行う（T-A1 / T-A2）。
    func test_didFinishLaunchingWithOptions_withLocationLaunchOption_callsStartTrackingFromSLC_S6018() {
        let sut = AppDelegate()

        // launchOptions に SLC 起床キーを含めて呼ぶ
        let slcKey = UIApplication.LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsLocationKey")
        let launchOptions: [UIApplication.LaunchOptionsKey: Any] = [slcKey: true]
        _ = sut.application(UIApplication.shared, didFinishLaunchingWithOptions: launchOptions)

        XCTAssertNotNil(sut.dependencies,
            "launchOptions[.location] あり: dependencies が non-nil（S6-018）")
        // S6-022: startTrackingFromSLC() の呼び出しは SceneDelegate に移管。
        // AppDelegate 側では isLaunchedFromSLC=true になることを確認する。
        XCTAssertTrue(sut.isLaunchedFromSLC,
            "launchOptions[.location] あり: isLaunchedFromSLC=true になる（S6-022 SceneDelegate 移管後）"
        )
    }

    // MARK: - (3) launchOptions に .location がない場合は startTrackingFromSLC が呼ばれない（S6-018）

    /// 通常起動経路（launchOptions に .location なし）のとき、
    /// startTrackingFromSLC() が呼ばれないことを検証する。
    /// isMonitoringSignificantChanges が false のままであることで確認する。
    func test_didFinishLaunchingWithOptions_withoutLocationLaunchOption_doesNotCallStartTrackingFromSLC_S6018() {
        let sut = AppDelegate()

        // launchOptions なし（通常起動）
        _ = sut.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertNotNil(sut.dependencies,
            "launchOptions なし: dependencies が non-nil（S6-018）")
        XCTAssertFalse(
            sut.dependencies.locationService.isMonitoringSignificantChanges,
            "launchOptions に .location なし: startTrackingFromSLC は呼ばれず isMonitoringSignificantChanges=false のまま（S6-018）"
        )
    }

    // MARK: - (4) dependencies の locationService が CLLocationManager delegate を持つ（S6-018）

    /// AppDelegate 経由で生成された dependencies の locationService は、
    /// CLLocationManager の delegate として自身を設定している。
    /// これにより SLC 起床時の didUpdateLocations コールバックが確実に受け取られることを保証する。
    ///
    /// テスト方法: AppDependencyContainer は本番 init で CLLocationManager() を使うため、
    /// locationService のプロパティとして観測可能な isUpdating / authorizationStatus で
    /// 正常に初期化されていることを確認する（delegate の直接参照は LocationService 内部のため
    /// テストからはアクセス不可）。
    func test_didFinishLaunchingWithOptions_locationService_isProperlyInitialized_S6018() {
        let sut = AppDelegate()
        _ = sut.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        let locationService = sut.dependencies.locationService

        // LocationService の @Published プロパティが初期状態として定義値を持つことを確認
        XCTAssertFalse(locationService.isUpdating,
            "初期状態: isUpdating=false（startUpdatingLocation は未呼び出し）（S6-018）")
        XCTAssertFalse(locationService.isMonitoringSignificantChanges,
            "初期状態: isMonitoringSignificantChanges=false（startTrackingFromSLC 未呼び出し）（S6-018）")
    }
}
