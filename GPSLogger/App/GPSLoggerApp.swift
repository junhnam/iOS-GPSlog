import SwiftUI
import GoogleMaps

@main
struct GPSLoggerApp: App {
    init() {
        Self.configureGoogleMaps()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
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
