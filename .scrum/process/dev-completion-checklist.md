# Dev フェーズ完了基準チェックリスト

最終更新: 2026-05-06（Sprint 5 開始時に新規作成）
適用範囲: Sprint 5 以降の全ての Dev フェーズ
背景: Sprint 4 retro Try「Dev フェーズ完了基準に `xcodebuild clean build` の warning 数チェックを追加」を Sprint 5 から運用開始するための文書化。jun さんからの明示指示「Dev フェーズ完了基準への warning チェック追加: これはお願いします」を反映。

---

## このチェックリストの位置づけ

各 Dev エージェント（Dev-1 / Dev-2）は、自分の担当チケットを「Done」に更新する**前**に、本チェックリストを上から順に確認する。一つでも未達があるチケットは「In Progress」のままにし、PO/SM もしくはメインエージェントへ報告する。

このチェックリストは Sprint 4 retro の Problem「QA-S4-001（MKMapItem.placemark deprecated）が QA フェーズで発見された」を Dev フェーズで前倒しに捕まえる目的で導入する。

---

## チケット完了前の必須チェック（順番厳守）

### 1. ユニットテストが pass している

- 自分が触った範囲に関連する `XCTest` を `xcodebuild test` で実行（または Xcode の Cmd+U）
- 既存テストの回帰: 0 件
- 自分が追加したテスト: 全て pass
- pass 数 / fail 数を board.md のチケット行コメントにスタンプする

### 2. 静的解析（Swift コンパイラ警告）が 0 件

- Xcode の Issue Navigator（Cmd+5）で warning が **0 件** であることを確認
- ただし差分ビルドではキャッシュが効いて warning が見えないことがあるため、**必ずフル再ビルドで確認する**（次項を実施）

### 3. 【**Sprint 5 から必須**】`xcodebuild clean build` で warning 0 件

```bash
xcodebuild clean build \
  -project GPSLogger.xcodeproj \
  -scheme GPSLogger \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0' \
  2>&1 | grep -E '(warning:|error:)' | grep -v 'Pods/' | grep -v 'GoogleMaps' | wc -l
```

- 出力が `0` になることを確認
- Pods / GoogleMaps SDK 由来の warning は除外して構わない（自分のコード由来の warning だけが対象）
- もし warning がある場合は board.md のチケット行に「warning: N 件（内訳: ...）」と明記し、PO/SM に報告して Sprint 5 で吸収する別チケットを起こすか、Done 前に解消する

### 4. ビルドエラーが 0 件

- `xcodebuild build` または `xcodebuild clean build` が exit code 0 で終了する

### 5. iOS 26 API 変更点ノートとの整合

- 新規 API 採用時 / 既存 API の挙動変更時には `.scrum/notes/ios26-api-changes.md` を参照
- 該当エントリがない場合、新規 API 利用前に Apple ドキュメントで deprecated チェック
- 「**置換 API 自体も deprecated 化されているか**」を 2 段先まで確認（Sprint 4 retro Try）

### 6. board.md の状態更新

- 担当チケット行を `[ ]`（Todo）→ `[~]`（In Progress）→ `[x]`（Done）に更新
- Done の行には以下を記録:
  - コミット ID（短縮 7 桁）
  - フル再ビルド warning 数（0 が原則）
  - 追加テスト数

### 7. git commit

- コミットメッセージ: `<type>: <変更内容> (<TICKET-ID>)`
  - type: `feat` / `fix` / `chore` / `docs` / `refactor` / `test`
  - 例: `feat: Google Drive OAuth 認証フロー実装 (S5-001)`
- 単一のチケット = 1 コミット原則
- ブランチは `main` 直接（このプロジェクトの運用）

---

## 【**Sprint 5 限定**】 Sonnet サブエージェントの xcodebuild 代行運用

jun さんの明示指示「グローバル設定を変えるのは怖いので、引き続き Opus で代行する形で対応してください」により、Sprint 5 でも以下の運用を継続する:

### Dev エージェント（Sonnet）の責務

- 自分のコードを書く
- `xcodegen generate`（プロジェクトファイル更新が必要な場合）の実行
- `swift test` 単体（Swift パッケージ部分のテストのみ）
- Xcode 上でのビルドは試みない（sandbox で拒否されるため）

### メインエージェント（Opus）の責務

- Dev エージェントから「ビルド確認をお願いします」と要請を受けたら `xcodebuild clean build` を代行実行
- warning 数 / error 数を集計して Dev エージェントに返す
- Dev エージェントが warning を解消した後、再度ビルド確認を代行

### Dev エージェントへのプロンプト雛形

各 Dev サブエージェント起動時に以下を必ずプロンプトに含める:

```
- ビルド (xcodebuild) はメインエージェント (Opus) が代行する。あなた (Dev エージェント, Sonnet) は試みないこと
- ユニットテスト追加・xcodegen・コード編集は自分で行う
- 自チケット完了前にメインエージェントへ「ビルド確認をお願いします」と要請する
- メインがビルド結果（warning 数・error 数）を返したら、warning 0 / error 0 を確認のうえ Done に更新する
- iOS 26 API 変更点は .scrum/notes/ios26-api-changes.md を必ず参照する
- 新規 API 採用時は「置換 API 自体も deprecated 化されているか」を 2 段先まで確認する
```

---

## QA フェーズへの引き継ぎ条件

Dev フェーズ完了 = 以下が全て満たされた状態:

- [ ] board.md 上の全 Dev チケットが Done
- [ ] フル再ビルド (`xcodebuild clean build`) で warning 0 / error 0
- [ ] 全ユニットテストが pass（既存 + 新規）
- [ ] 全コミットが main にある
- [ ] `.scrum/config.md` の `sprint_phase` を `qa` に更新済み

これらが満たされたら、PO/SM が QA フェーズの起動（qa-multi-agent スキル）を行う。

---

## 改訂履歴

| 日付 | 内容 |
|---|---|
| 2026-05-06 | 初版（Sprint 5 開始時、Sprint 4 retro Try / jun さん指示を反映） |
