import SwiftUI

/// トリガー記録モード用のフローティングボタン（S3-005）。
///
/// 役割:
///   - `AppSettings.recordingMode == .trigger` のときのみ表示
///   - 「記録開始 / 停止」を 1 つのボタンで切り替え
///   - 記録中: 赤系 + 「停止」、停止中: 緑系 + 「記録開始」
///   - タップでバインドされた action クロージャを呼ぶ（実際の start/stop は親が行う）
///
/// 設計判断:
///   - LocationService への直接アクセスは持たず、純粋なプレゼンテーション層にする
///     （テストしやすく、後で LocationService の API が変わっても影響しない）
///   - `isLogging` は LocationService.isUpdating を流し込む想定
///   - 自宅滞在警告は MapView 側で HUD として表示する責務分離
struct RecordingToggleButton: View {
    /// 記録中かどうか。LocationService.isUpdating を流す。
    let isLogging: Bool

    /// タップ時に呼ばれる。`!isLogging` から呼び出されることを意図しているが、
    /// 副作用（start/stop の選択）は呼び出し側 closure 内で行う。
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isLogging ? "stop.circle.fill" : "record.circle.fill")
                    .font(.title3)
                Text(isLogging ? "停止" : "記録開始")
                    .font(.callout.bold())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(isLogging ? Color.red : Color.green, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
        .accessibilityIdentifier("recording_toggle_button")
        .accessibilityLabel(isLogging ? "記録停止ボタン" : "記録開始ボタン")
        .accessibilityHint("トリガーモードで GPS 記録を切り替えます")
    }
}

#Preview("停止中") {
    RecordingToggleButton(isLogging: false, action: {})
}

#Preview("記録中") {
    RecordingToggleButton(isLogging: true, action: {})
}
