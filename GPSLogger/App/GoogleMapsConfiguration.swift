import Foundation

/// Google Maps SDK の API キー読み込みを集約するユーティリティ。
///
/// 優先順位:
///   1. 環境変数 `GMS_API_KEY`（CI / 開発時用）
///   2. バンドル内の `GoogleMaps-Info.plist` の `GMSApiKey` キー
///
/// どちらからも取得できない場合は `nil` を返す。`nil` の場合、呼び出し側で
/// 起動を継続するか落とすかを判断する（Sprint 1 では継続）。
enum GoogleMapsConfiguration {
    static func loadAPIKey(bundle: Bundle = .main,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let envKey = environment["GMS_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        guard let plistURL = bundle.url(forResource: "GoogleMaps-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let apiKey = plist["GMSApiKey"] as? String,
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }
}
