import SwiftUI

@main
struct GPSLoggerApp: App {
    init() {
        // S1-002 でここに GMSServices.provideAPIKey の呼び出しを追加する。
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
