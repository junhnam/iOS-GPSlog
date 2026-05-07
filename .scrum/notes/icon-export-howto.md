# アプリアイコン PNG 書き出し手順

## 概要

`GPSLogger/Design/Mockups/IconDesignPreview.swift` に SwiftUI で描画したアイコンを
Xcode の Canvas プレビュー経由で PNG として書き出す手順です。

この手順を実施すると `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` が配置され、
ビルド時の「missing icon」警告が解消されます。

---

## 手順

### Step 1: プレビュー表示

1. Xcode でプロジェクトを開く
2. ファイルナビゲータから
   `GPSLogger > Design > Mockups > IconDesignPreview.swift` を開く
3. `Cmd + Option + Return` で Canvas (プレビューパネル) を表示する
4. Canvas 上部のドロップダウンから **"AppIcon1024Preview"** を選択する

### Step 2: PNG として書き出す

方法 A (推奨 - Xcode の Export 機能):
1. Canvas に表示された 1024x1024 のアイコンの上で **右クリック**
2. メニューから **"Export Preview..."** を選択
3. ファイル名を `AppIcon-1024.png` として保存先を指定する
4. 保存先は任意でよい (次の Step で移動する)

方法 B (スクリーンショット経由):
1. Canvas に 1024x1024 のプレビューが表示された状態で
   `Cmd + Shift + 4` を押してスクリーンショットモードに入る
2. Canvas のアイコン部分だけを範囲選択してスクリーンショットを撮る
3. 保存された PNG ファイルを macOS 標準の Preview.app で開く
4. `ツール > サイズを調整...` で 1024x1024 px に変更して保存する
5. ファイル名を `AppIcon-1024.png` にリネームする

### Step 3: Assets.xcassets へ配置

1. 書き出した `AppIcon-1024.png` を Finder で確認する
2. Xcode のファイルナビゲータで
   `GPSLogger > Resources > Assets.xcassets > AppIcon` を開く
3. `AppIcon-1024.png` を Xcode の AppIcon スロットに**ドラッグ&ドロップ**する
4. `Contents.json` が自動更新されて `"filename": "AppIcon-1024.png"` となっていれば完了

---

## 確認方法

Step 3 完了後、以下でアイコンが正しく設定されたか確認できます:

- Xcode メニュー `Product > Build` (Cmd+B) でエラーがないことを確認
- シミュレータに `Product > Run` でインストールし、ホーム画面のアイコンを確認

---

## アイコンデザイン仕様

| 項目 | 内容 |
|---|---|
| モチーフ | S字カーブの経路ライン + 目的地ピン + 現在地ドット |
| 背景 | 深藍 (#1A3A5C) から青 (#2E7FC0) への対角グラデーション |
| 経路ライン | 淡青 (#A8D8FF) の半透明ライン |
| ピン | 白 (ドーナツ形状 + 三角突起) |
| 現在地ドット | 白 (外側リング + 内側丸) |
| サイズ | 1024x1024 px (iOS 14+ Single Size) |
| 出力形式 | PNG |

---

## ローンチスクリーンについて

ローンチスクリーンは `Info.plist` の `UILaunchScreen` 辞書で設定済みです。

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIColorName</key>
    <string>LaunchBackground</string>
</dict>
```

`LaunchBackground` カラーは `Assets.xcassets/LaunchBackground.colorset` に定義されており、
アイコン背景と同じ深藍 (#1A3A5C) が設定されています。

アイコン PNG を配置してビルドすれば、ローンチスクリーンも機能します。
追加の設定は不要です。
