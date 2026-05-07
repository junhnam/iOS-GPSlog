# デザインシステムメモ (Sprint 6 確立版)

商用化判断時の再デザイン参照用として、Sprint 6 で確立したデザイン言語をメモする。

---

## カラーパレット

| 用途 | 名前 | HEX | RGB (sRGB) | 使用箇所 |
|---|---|---|---|---|
| プライマリ (アクション / ルートライン) | Primary Blue | #1E88E5 | R:0.118 G:0.533 B:0.898 | AccentColor / MockColor.primary / 既存 UI 全般 |
| アイコン背景 始点 | Icon Deep | #1A3A5C | R:0.102 G:0.227 B:0.361 | AppIcon グラデーション始点 / ローンチスクリーン背景 |
| アイコン背景 終点 | Icon Light | #2E7FC0 | R:0.180 G:0.498 B:0.753 | AppIcon グラデーション終点 |
| 経路ライン | Route Line | #A8D8FF | R:0.659 G:0.847 B:1.000 | AppIcon 内経路 |
| 危険 (停止アクション) | Danger Red | #E53935 | R:0.898 G:0.224 B:0.208 | 記録停止ボタン |
| 成功 (自宅滞在) | Success Green | #43A047 | R:0.263 G:0.627 B:0.278 | 自宅滞在ステータス |

---

## タイポグラフィ

| 用途 | 指定 |
|---|---|
| ナビゲーションタイトル | `.navigationTitle()` / システムデフォルト |
| メトリクス値 | `.system(size: 18, weight: .semibold, design: .rounded)` |
| ラベル | `.system(size: 11)` / `.secondary` |
| アプリ名 (ローンチスクリーン) | `.system(size: 28, weight: .semibold, design: .rounded)` |

---

## スペーシング

| トークン | pt値 | 使用例 |
|---|---|---|
| xs | 4 | アイコンとテキストの間隔 |
| s | 8 | バッジ内パディング |
| m | 12 | カード内セクション間隔 |
| l | 16 | 画面端マージン |
| xl | 24 | セクション間余白 |

---

## アイコンデザイン

- モチーフ: S字カーブの移動経路 + 目的地ピン + 現在地ドット
- 視覚的意図: 「移動を記録するアプリ」を一目で伝える
- 配色トーン: 落ち着いた濃紺〜青のグラデーション (派手さを避けた個人利用向け)
- 商用化時の方針: Google Maps らしい緑系への変更 or ブランドカラー策定で全面見直し推奨

---

## コンポーネント

| コンポーネント | 角丸 | シャドウ |
|---|---|---|
| 情報カード | 16pt (continuous) | radius:12 opacity:0.08 |
| フローティングボタン | Circle | radius:10 opacity:0.25 |
| ステータスバッジ | Capsule | なし (マテリアル背景) |
| アイコン (ホーム画面) | iOS 自動マスク | なし |
| アイコン (ローンチスクリーン内) | 26pt (continuous) | radius:20 opacity:0.30 |

---

## ローンチスクリーン実装方式

- 方式: `Info.plist > UILaunchScreen` 辞書
- 背景色: `LaunchBackground` カラーアセット (#1A3A5C / ダークモードも同色)
- 内容: 単色背景のみ (シンプル / アニメーションなし)
- 理由: storyboard 不要でコード量を最小化。iOS 14+ 全対応。

---

## 注記

- 全コンポーネントは iOS Human Interface Guidelines に準拠
- ライト / ダークモード両対応 (アクセントカラー・ローンチ背景は両モード同色)
- VoiceOver 対応: 主要コンポーネントに `accessibilityLabel` 付与済 (MainScreenMock.swift 参照)
