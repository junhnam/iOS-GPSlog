//
//  MainScreenMock.swift
//  GPSLogger
//
//  ============================================================
//  これは Sprint 3 以降のメイン画面実装の「視覚的参照モック」である。
//  本ファイルは project.yml で `Design/**` がビルドターゲットから
//  除外されているため、アプリ本体のビルドには含まれない。
//  Xcode の Canvas プレビュー（#Preview）で確認することを想定。
//  ============================================================
//
//  目的:
//   - PO/SM/Dev/Designer 間の合意形成用ビジュアル
//   - Sprint 3 以降の実装者がレイアウト・カラー・余白の参照に使う
//
//  含まれる構成要素:
//   1. 全画面の地図プレースホルダ（Google Maps SDK の代替として灰色塗り）
//   2. 上部ステータスバッジ（記録中 / 停止中 / 自宅滞在中 のダミー切替）
//   3. 中央〜下部の情報カード（移動距離・経過時間・滞留ピン数）
//   4. 右下のフローティング記録ボタン（ON/OFF 切替の見た目）
//   5. 下部タブバー（地図 / 履歴 / 設定）
//
//  デザイン原則:
//   - iOS Human Interface Guidelines に準拠
//   - ライト／ダークモード両対応
//   - 屋外でも視認できる強コントラスト
//   - VoiceOver 対応（accessibilityLabel 付与）
//
//  ハードコードされたダミーデータ:
//   - 移動距離: 12.3 km
//   - 経過時間: 0:42:15
//   - 滞留ピン: 2 件
//

import SwiftUI

// MARK: - Design Tokens (将来 DesignSystem.swift に切り出す前提のローカル定義)

private enum MockColor {
    /// プライマリカラー（記録中・主要アクション）
    static let primary = Color(red: 0x1E / 255.0, green: 0x88 / 255.0, blue: 0xE5 / 255.0) // #1E88E5
    /// 危険カラー（停止アクション）
    static let danger = Color(red: 0xE5 / 255.0, green: 0x39 / 255.0, blue: 0x35 / 255.0) // #E53935
    /// ニュートラル背景（カード背景の代替。実際は systemBackground を優先）
    static let neutralBackground = Color(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF5 / 255.0) // #F5F5F5
    /// サクセス（自宅滞在中などの安全インジケータ）
    static let success = Color(red: 0x43 / 255.0, green: 0xA0 / 255.0, blue: 0x47 / 255.0) // #43A047
}

private enum MockSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

private enum MockRadius {
    static let card: CGFloat = 16
    static let pill: CGFloat = 999
}

// MARK: - 記録ステータス（ダミー列挙）

private enum RecordingState {
    case recording        // 記録中（プライマリ青）
    case stopped          // 停止中（グレー）
    case atHomeIdle       // 自宅滞在中（記録自動停止）

    var label: String {
        switch self {
        case .recording:    return "記録中"
        case .stopped:      return "停止中"
        case .atHomeIdle:   return "自宅滞在中"
        }
    }

    var systemImage: String {
        switch self {
        case .recording:    return "record.circle.fill"
        case .stopped:      return "stop.circle.fill"
        case .atHomeIdle:   return "house.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recording:    return MockColor.primary
        case .stopped:      return .secondary
        case .atHomeIdle:   return MockColor.success
        }
    }
}

// MARK: - メインモックビュー

struct MainScreenMock: View {

    /// プレビュー切替用。実装時には ViewModel から受け取る想定。
    @State private var state: RecordingState = .recording

    var body: some View {
        TabView {
            mainTab
                .tabItem { Label("地図", systemImage: "map.fill") }
            historyTab
                .tabItem { Label("履歴", systemImage: "clock.fill") }
            settingsTab
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .tint(MockColor.primary)
    }

    // MARK: メインタブ（地図画面）

    private var mainTab: some View {
        ZStack(alignment: .bottomTrailing) {
            mapPlaceholder

            // 上部 = ステータスバッジ、下部左 = 情報カード、右下 = 記録ボタン
            VStack(alignment: .leading, spacing: MockSpacing.m) {
                statusBadge
                Spacer()
                infoCard
            }
            .padding(.horizontal, MockSpacing.l)
            .padding(.top, MockSpacing.s)
            .padding(.bottom, MockSpacing.xl)

            recordButton
                .padding(.trailing, MockSpacing.l)
                .padding(.bottom, MockSpacing.xl + 60) // タブバーぶん持ち上げ
        }
    }

    // MARK: 地図プレースホルダ

    /// Google Maps SDK 未統合時の代替表示。
    /// Sprint 3 以降は GMSMapView をホストする SwiftUI ラッパに差し替える。
    private var mapPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.gray.opacity(0.25),
                    Color.gray.opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 地図っぽさを匂わせるグリッドラインと擬似経路
            mapGuideLines
            fakeRoutePolyline
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("地図エリア。実装時は Google Maps が表示されます。")
    }

    /// 緯度経度グリッドのダミー線
    private var mapGuideLines: some View {
        GeometryReader { geo in
            let columns = 5
            let rows = 9
            ZStack {
                ForEach(0..<columns, id: \.self) { i in
                    Path { p in
                        let x = geo.size.width * CGFloat(i) / CGFloat(columns - 1)
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
                ForEach(0..<rows, id: \.self) { i in
                    Path { p in
                        let y = geo.size.height * CGFloat(i) / CGFloat(rows - 1)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            }
        }
    }

    /// 走行経路を示すダミーのポリライン（Sprint 1 ゴール「青い線」のイメージ）
    private var fakeRoutePolyline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
                p.addCurve(
                    to: CGPoint(x: w * 0.55, y: h * 0.55),
                    control1: CGPoint(x: w * 0.25, y: h * 0.70),
                    control2: CGPoint(x: w * 0.40, y: h * 0.50)
                )
                p.addCurve(
                    to: CGPoint(x: w * 0.85, y: h * 0.20),
                    control1: CGPoint(x: w * 0.65, y: h * 0.55),
                    control2: CGPoint(x: w * 0.75, y: h * 0.30)
                )
            }
            .stroke(
                MockColor.primary,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: MockColor.primary.opacity(0.4), radius: 4, x: 0, y: 2)

            // ピン（滞留検出のダミー）
            mapPin(at: CGPoint(x: w * 0.55, y: h * 0.55), label: "カフェ A")
            mapPin(at: CGPoint(x: w * 0.85, y: h * 0.20), label: "現在地")
        }
    }

    private func mapPin(at point: CGPoint, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(MockColor.danger)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                )
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(.thinMaterial)
                )
        }
        .position(point)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("地図上のピン: \(label)")
    }

    // MARK: ステータスバッジ

    private var statusBadge: some View {
        HStack(spacing: MockSpacing.s) {
            Image(systemName: state.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(Circle().fill(state.tint))

            Text(state.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            if state == .recording {
                // 記録中の点滅ドット（実装時に Animation で点滅させる前提）
                Circle()
                    .fill(MockColor.danger)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, MockSpacing.m)
        .padding(.vertical, MockSpacing.s)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(state.tint.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("現在のステータス: \(state.label)")
    }

    // MARK: 情報カード（距離 / 時間 / ピン数）

    private var infoCard: some View {
        HStack(spacing: 0) {
            metric(value: "12.3", unit: "km", label: "移動距離", systemImage: "road.lanes")
            divider
            metric(value: "0:42:15", unit: "", label: "経過時間", systemImage: "clock")
            divider
            metric(value: "2", unit: "件", label: "滞留ピン", systemImage: "mappin.and.ellipse")
        }
        .padding(.vertical, MockSpacing.m)
        .padding(.horizontal, MockSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: MockRadius.card, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MockRadius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func metric(value: String, unit: String, label: String, systemImage: String) -> some View {
        VStack(spacing: MockSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MockColor.primary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(unit)")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 36)
    }

    // MARK: 記録ボタン（フローティング）

    private var recordButton: some View {
        Button {
            // モックなので何もしない。プレビューでの状態切替のみ。
            switch state {
            case .recording:    state = .stopped
            case .stopped:      state = .recording
            case .atHomeIdle:   state = .recording
            }
        } label: {
            ZStack {
                Circle()
                    .fill(state == .recording ? MockColor.danger : MockColor.primary)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)

                Image(systemName: state == .recording ? "stop.fill" : "record.circle")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        // 受け入れ条件: VoiceOver 用ラベル
        .accessibilityLabel("記録開始/停止")
        .accessibilityHint(state == .recording ? "タップで記録を停止します" : "タップで記録を開始します")
    }

    // MARK: 履歴タブ（プレースホルダ）

    private var historyTab: some View {
        NavigationStack {
            List {
                Section("最近の移動") {
                    historyRow(date: "2026/05/05", distance: "12.3 km", duration: "0:42")
                    historyRow(date: "2026/05/04", distance: "84.7 km", duration: "1:58")
                    historyRow(date: "2026/05/03", distance: "3.1 km", duration: "0:18")
                }
                Section("今月のサマリ") {
                    LabeledContent("総移動距離", value: "412.6 km")
                    LabeledContent("記録日数", value: "14 日")
                    LabeledContent("滞留ピン総数", value: "37 件")
                }
            }
            .navigationTitle("履歴")
        }
    }

    private func historyRow(date: String, distance: String, duration: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date)
                    .font(.subheadline.weight(.semibold))
                Text("\(distance) ・ \(duration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(date) の記録。距離 \(distance)、時間 \(duration)")
    }

    // MARK: 設定タブ（プレースホルダ）

    private var settingsTab: some View {
        NavigationStack {
            Form {
                Section("記録モード") {
                    settingRow(icon: "dot.radiowaves.left.and.right", text: "常時同期")
                    settingRow(icon: "hand.tap", text: "トリガー同期")
                }
                Section("位置・カレンダー") {
                    settingRow(icon: "house", text: "自宅を設定")
                    settingRow(icon: "calendar", text: "iOS カレンダー連携")
                }
                Section("データ") {
                    settingRow(icon: "square.and.arrow.up", text: "CSV エクスポート")
                    settingRow(icon: "icloud", text: "クラウド同期先")
                    settingRow(icon: "trash", text: "DB クリア", tint: MockColor.danger)
                }
                Section("バッテリー") {
                    settingRow(icon: "battery.75percent", text: "省電力モード")
                }
            }
            .navigationTitle("設定")
        }
    }

    private func settingRow(icon: String, text: String, tint: Color = MockColor.primary) -> some View {
        HStack(spacing: MockSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(tint))
            Text(text)
                .font(.body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Previews

#Preview("Light - 記録中") {
    MainScreenMock()
        .preferredColorScheme(.light)
}

#Preview("Dark - 記録中") {
    MainScreenMock()
        .preferredColorScheme(.dark)
}
