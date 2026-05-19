import SwiftUI
import SwiftData
import GoogleMaps

@main
struct GPSLoggerApp: App {
    /// S6-018: AppDelegate を接続し、バックグラウンド SLC 起床経路でも
    /// DI の初期化を確実に完了させる。
    ///
    /// 従来の `@State private var dependencies = AppDependencyContainer()` は
    /// SwiftUI の遅延評価により、SLC 起床 → `WindowGroup.body` が評価されるまで
    /// `AppDependencyContainer` が生成されない問題があった（リリースブロッカー）。
    /// `AppDelegate.didFinishLaunchingWithOptions` で先行生成することで解決する。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.configureGoogleMaps()
        // S6-018: AppDelegate.didFinishLaunchingWithOptions で dependencies が生成済み。
        // ここでは追加生成しない。
    }

    var body: some Scene {
        WindowGroup {
            // S6-018: appDelegate.dependencies は didFinishLaunchingWithOptions で
            // 確実に生成済みのため、force unwrap は安全。
            RootView(dependencies: appDelegate.dependencies)
        }
        // SwiftData の ModelContainer をアプリ全体に注入する（S2-002）。
        // 各 View からは `@Environment(\.modelContext)` で ModelContext を取得できる。
        .modelContainer(PersistenceController.shared.container)
    }

    /// Google Maps SDK にAPIキーを渡す。
    /// キー未設定時はクラッシュさせず警告ログのみ出して起動継続する
    /// （Sprint 1 ではキー未取得状態でもプロジェクト雛形の動作確認ができるようにするため）。
    private static func configureGoogleMaps() {
        guard let apiKey = GoogleMapsConfiguration.loadAPIKey(), !apiKey.isEmpty else {
            print("[GPSLogger] WARNING: Google Maps API key is not configured. Map features will not work until you set GoogleMaps-Info.plist.")
            return
        }
        GMSServices.provideAPIKey(apiKey)
    }
}
