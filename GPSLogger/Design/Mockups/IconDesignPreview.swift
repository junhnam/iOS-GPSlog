//
//  IconDesignPreview.swift
//  GPSLogger
//
//  ============================================================
//  このファイルはアプリアイコンのデザインプレビュー専用である。
//  project.yml で `Design/**` がビルドターゲットから除外されているため、
//  アプリ本体には含まれない。
//  Xcode の Canvas プレビュー (#Preview) で確認 → PNG 書き出しを想定。
//  ============================================================
//
//  デザイン方針:
//   - モチーフ: GPS 経路 (ルートライン) + 位置ピン
//   - 配色: 深みのある藍青 (#1A3A5C) をベースに、水色グラデーション (#2E7FC0) で抜ける
//     --> 既存 MockColor.primary (#1E88E5) と整合した青系トーン
//     --> 派手さを抑えた「落ち着いた配色」を維持
//   - 形状: 角丸正方形の中央に経路ライン + ピン
//   - アクセント: ルートの終端に白い丸ドット (現在地) を配置
//   - アイコン枠: iOS が自動的に角丸マスクをかけるため、1024x1024 フラット正方形で出力
//
//  PNG 書き出し手順:
//   1. Xcode でこのファイルを開き、Canvas を表示 (Cmd+Option+Return)
//   2. "AppIcon1024Preview" の Preview キャンバスを選択
//   3. プレビュー上で右クリック → "Export Preview" or スクリーンショット
//      (スクリーンショットの場合は macOS の Preview.app でリサイズが必要)
//   4. 1024x1024 px の PNG として保存
//   5. GPSLogger/Resources/Assets.xcassets/AppIcon.appiconset/ へドラッグ
//      (Xcode が自動的に Contents.json を更新する)
//   ※ 詳細手順は .scrum/notes/icon-export-howto.md を参照
//

import SwiftUI

// MARK: - アイコン専用カラー定義

private enum IconColor {
    /// 背景グラデーション: 始点 (深藍)
    static let backgroundDeep = Color(red: 0x1A / 255.0, green: 0x3A / 255.0, blue: 0x5C / 255.0)
    /// 背景グラデーション: 終点 (明るい青)
    static let backgroundLight = Color(red: 0x2E / 255.0, green: 0x7F / 255.0, blue: 0xC0 / 255.0)
    /// 経路ライン: 白に近い淡青 (背景に溶け込みすぎないよう彩度を持たせる)
    static let routeLine = Color(red: 0xA8 / 255.0, green: 0xD8 / 255.0, blue: 0xFF / 255.0)
    /// ピン: 鮮明な白
    static let pin = Color.white
    /// 現在地ドット: 白
    static let currentDot = Color.white
    /// 影 (ピン、ドットに薄く付ける)
    static let shadow = Color(red: 0x0A / 255.0, green: 0x1E / 255.0, blue: 0x3A / 255.0)
}

// MARK: - アイコン本体 View

/// 1024x1024 の正方形で描画するアプリアイコン。
/// iOS が角丸マスクをかけるため、四隅まで背景を塗りつぶす。
struct AppIconView: View {

    /// 描画スケールを正規化するための基準サイズ (1.0 = 1024pt 相当)
    var size: CGFloat = 1024

    private var scale: CGFloat { size / 1024 }

    var body: some View {
        ZStack {
            background
            routePath
            destinationPin
            currentLocationDot
        }
        .frame(width: size, height: size)
        .clipped()
    }

    // MARK: 背景 (深藍 → 青 の対角グラデーション)

    private var background: some View {
        LinearGradient(
            colors: [IconColor.backgroundDeep, IconColor.backgroundLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: size, height: size)
    }

    // MARK: 経路ライン (S字カーブで移動経路を表現)

    private var routePath: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // 左下から右上へ、S字の曲線で経路を描く
                path.move(to: CGPoint(x: w * 0.18, y: h * 0.82))
                path.addCurve(
                    to: CGPoint(x: w * 0.45, y: h * 0.52),
                    control1: CGPoint(x: w * 0.18, y: h * 0.62),
                    control2: CGPoint(x: w * 0.32, y: h * 0.52)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.72, y: h * 0.32),
                    control1: CGPoint(x: w * 0.58, y: h * 0.52),
                    control2: CGPoint(x: w * 0.72, y: h * 0.46)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.62, y: h * 0.18),
                    control1: CGPoint(x: w * 0.72, y: h * 0.22),
                    control2: CGPoint(x: w * 0.68, y: h * 0.18)
                )
            }
            .stroke(
                IconColor.routeLine,
                style: StrokeStyle(
                    lineWidth: 52 * scale,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .opacity(0.75)
        }
    }

    // MARK: 目的地ピン (右上寄り / ルート終端付近)

    private var destinationPin: some View {
        GeometryReader { geo in
            let cx = geo.size.width * 0.62
            let cy = geo.size.height * 0.18
            let pinBodyRadius: CGFloat = 90 * scale
            let pinTipLength: CGFloat = 36 * scale

            ZStack {
                // ピンの丸部分
                Circle()
                    .fill(IconColor.pin)
                    .frame(width: pinBodyRadius * 2, height: pinBodyRadius * 2)
                    .shadow(color: IconColor.shadow.opacity(0.5), radius: 12 * scale, x: 0, y: 6 * scale)
                    .position(x: cx, y: cy)

                // ピンの中心穴 (ドーナツ形状 → 塗り抜き)
                Circle()
                    .fill(IconColor.backgroundDeep)
                    .frame(width: pinBodyRadius * 0.72, height: pinBodyRadius * 0.72)
                    .position(x: cx, y: cy)

                // ピン下部の三角突起
                Path { p in
                    let tipY = cy + pinBodyRadius + pinTipLength
                    p.move(to: CGPoint(x: cx - 14 * scale, y: cy + pinBodyRadius * 0.85))
                    p.addLine(to: CGPoint(x: cx + 14 * scale, y: cy + pinBodyRadius * 0.85))
                    p.addLine(to: CGPoint(x: cx, y: tipY))
                    p.closeSubpath()
                }
                .fill(IconColor.pin)
            }
        }
    }

    // MARK: 現在地ドット (ルート始点 / 左下寄り)

    private var currentLocationDot: some View {
        GeometryReader { geo in
            let cx = geo.size.width * 0.18
            let cy = geo.size.height * 0.82

            ZStack {
                // 外側リング (パルス表現)
                Circle()
                    .fill(IconColor.currentDot.opacity(0.28))
                    .frame(width: 96 * scale, height: 96 * scale)
                    .position(x: cx, y: cy)

                // 内側白丸
                Circle()
                    .fill(IconColor.currentDot)
                    .frame(width: 58 * scale, height: 58 * scale)
                    .shadow(color: IconColor.shadow.opacity(0.5), radius: 8 * scale, x: 0, y: 4 * scale)
                    .position(x: cx, y: cy)
            }
        }
    }
}

// MARK: - ローンチスクリーンプレビュー

/// ローンチスクリーンの見た目確認用。
/// 実装は Info.plist の UILaunchScreen 辞書で行う。
/// このプレビューは配色・ロゴ配置の確認用。
struct LaunchScreenPreview: View {

    var body: some View {
        ZStack {
            // Info.plist UIColorName に登録する背景色と同じ色
            IconColor.backgroundDeep
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // 縮小版アイコン (ローンチスクリーン上のロゴ)
                AppIconView(size: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)

                Text("GPSログ")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(0.92)
            }
        }
    }
}

// MARK: - Previews

#Preview("AppIcon1024Preview") {
    AppIconView(size: 1024)
}

#Preview("AppIcon-小 (60pt@3x)") {
    AppIconView(size: 180)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("AppIcon-中 (76pt@2x iPad)") {
    AppIconView(size: 152)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("LaunchScreen") {
    LaunchScreenPreview()
}
