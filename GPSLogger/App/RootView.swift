import SwiftUI

/// アプリ起動直後に表示されるルート画面のプレースホルダ。
/// Sprint 1 では空 SwiftUI 画面の表示確認のみが目的。
/// ナビゲーション骨格 (S1-004) で TabView などに置き換えられる予定。
struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.north.line.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            Text("Hello, GPSLogger")
                .font(.title2)
            Text("Sprint 1 雛形")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
