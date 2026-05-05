# Sprint 1 Retrospective

開催日: 2026-05-05
参加: PO/SM / Dev-1 / Dev-2 / Designer / QA（Single-Agent モードで Agent A が代行）

---

## Keep（続けること）

- **iOS 開発初回スプリントで全 9 チケット 100% 完了**。スプリントゴール（地図表示 + 経路ライン描画）も達成。立ち上げから動く骨格まで一気通貫で到達できた。
- **Dev-1 / Dev-2 / Designer の作業ファイルが綺麗に分かれ、git 競合がゼロ**。`App/` と `Services/` と `Features/Map/` と `Design/Mockups/` で物理的に切り離した分割設計が機能した。
- **API キー管理の安全性**。`.gitignore` 設計と `GoogleMaps-Info.plist.example` テンプレート、環境変数フォールバック、起動時 nil チェックの組み合わせで、コードベース・git 履歴ともに本物のキー漏洩が 0 件。
- **バッテリー対策を Sprint 1 から意識**できた。`activityType = .automotiveNavigation` / `pausesLocationUpdatesAutomatically` / `distanceFilter` など、Apple 推奨の省電力設定を初期実装に組み込んでおり、後追い対応にならなかった。
- **XcodeGen の採用**で `project.pbxproj` の競合リスクを大きく下げられた。`project.yml` を編集して `xcodegen generate` する流れがチームで再現可能。
- **コードコメントの質**が高く、なぜそうしているか / Sprint 何で何を変える想定か、が日本語で書かれている。jun さん本人の後追い読解にもフレンドリー。
- **Swift 6 strict concurrency 対応**。`@MainActor` クラス + `nonisolated` delegate + `Task @MainActor` への復帰で warning 0 件達成。
- **QA がバグを 1 件しか出さず（しかも Low / 仕組み起因）、自動修正まで完了**。実装側の品質が高かった裏付け。

## Problem（問題だったこと）

- **初期セッションで Xcode 本体が未インストール**だったため、Dev-1 が `xcodebuild` でのビルド検証ができない期間があった。途中で jun さん側のセットアップで解消したが、もしブロッカー解消が遅れていたら Sprint 1 完了は危うかった。
- **QA フェーズで Task ツールが使えず Single-Agent モードでの実行**になった。Agent A が B/C/D/E/F の役を全部兼任したため、本来の並列実行のメリットが出ず、観点漏れリスクも高まった（結果としては 30 観点しっかり実行できた）。
- **シミュレータ実機での E2E 確認は私側ではできず、jun さんに依頼する形**になった。スプリントゴール「地図上に青いラインが描画されること」の最終確認が、PO/SM ではクローズできない状態で残った。
- **Designer が画面の PNG エクスポートを手元でできなかった**。Xcode Canvas の画像化機能が当環境で使えず、S1-008 の受け入れ条件「スクリーンショット 2 枚」が未対応のまま受け入れになった（チケットコメントで例外化）。
- **GitHub Issues #1〜#9 が作成されているが、まだ open のまま**。Sprint 1 完了処理（クローズコメント）はユーザー承認待ちで保留している。
- **ローカル 14 コミットが未 push**。スプリント途中で push のタイミングをユーザーに確認する仕組みがなく、レビュー時にまとめて承認依頼となった。

## Try（次に試すこと）

- **Sprint 2 開始前に jun さんに Sprint 1 の実機動作確認を依頼するチェックポイントを設ける**。Sprint 2 の planning 入りの前に「Sprint 1 のシミュレータ検証完了」を必須条件にする。
- **QA フェーズの最初に「Task ツール可否」を確認するルーチンを入れる**。使えない場合は最初から Single-Agent モード前提で観点を絞り込む / 順序を最適化する。
- **Xcode Canvas エクスポートを Sprint 2 初期に jun さんに依頼**。S1-008 の残課題を Sprint 2 のキックオフ時に jun さん側タスクとして明示する。
- **Sprint 中に「区切りの良いタイミングで push 確認するか」を決めておく**。Sprint 1 では PO/SM が後回しにしたが、Sprint 2 では「Dev フェーズ完了直後」と「Sprint 完了時」に push 確認を入れる運用を試す。
- **GitHub Issue クローズの自動化検討**。Sprint 完了時に board.md の Done 列を読んで一括クローズするスクリプト or 手順を用意。今回は手動で組み立てたバッチコマンドを report 末尾に提示している。
- **`.qa-workspace/` の `.gitignore` 反映を Sprint 2 冒頭で必ず実施**。Sprint 1 では Agent F が修正したが未コミット状態で持ち越している。

---

## メトリクス

| 指標 | 値 |
|---|---|
| 計画チケット数 | 9 |
| 完了チケット数 | 9 |
| 完了率 | 100% |
| 持ち越しチケット | 0（タスク残はあるが受け入れ済） |
| Sprint 中コミット数 | 14 |
| 変更ファイル数 | 24 |
| 追加行数 / 削除行数 | +1392 / -58 |
| ユニットテスト数 | 14（既存 5 + 追加 9） |
| ユニットテスト pass 率 | 100% |
| ビルド warning / error | 0 / 0 |
| バグチケット起票数 | 1（Low、修正済・コミット未） |
| 残存バグ | 0 |

## アクションアイテム（次スプリント開始前までに）

- [ ] jun さん: Xcode で `xcodegen generate` → ⌘R シミュレータ実行 → Freeway Drive で青ライン描画を目視確認
- [ ] jun さん: Light/Dark の MainScreenMock スクリーンショット 2 枚を `Design/Mockups/` 配下に PNG で配置
- [ ] PO/SM: ユーザー承認後、ローカル 14 コミットを `origin main` に push
- [ ] PO/SM: ユーザー承認後、GitHub Issues #1〜#9 をクローズ（コメント: "Sprint 1 で実装完了"）
- [ ] PO/SM: `.qa-workspace/` を `.gitignore` に追加（FIX_001 の反映）してコミット
- [ ] PO/SM: `.scrum/config.md` の `current_sprint` を 2 に、`sprint_phase` を `planning` に更新（合意後）
- [ ] PO/SM: Sprint 2（DB + 滞留検出 + ピン記録）の planning を実施
