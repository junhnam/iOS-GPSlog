import SwiftUI
import SwiftData
import GoogleMaps

@main
struct GPSLoggerApp: App {
    /// アプリ全体の依存を保持する DIコンテナ（S6-002）。
    ///
    /// `@State` で保持することで App の生存期間中 MainActor 上で 1 インスタンスを維持する。
    /// `App.body` は @MainActor で評価されるため、@MainActor 必須の
    /// `AppDependencyContainer.init()` をここで安全に呼べる。
    @State private var dependencies = AppDependencyContainer()

    init() {
        Self.configureGoogleMaps()
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
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
