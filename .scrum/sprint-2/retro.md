# Sprint 2 Retrospective

開催日: 2026-05-05
参加: PO/SM / Dev-1 / Dev-2 / QA（Single-Agent モードで Agent A が代行）

---

## Keep（続けること）

- **ユーザー要望（総移動距離 km 表示）を Sprint 2 のスコープに即時取り込めた**。Sprint 1 終了直後にいただいた追加要望を CLAUDE.md に反映し、S2-004 として独立チケット化。Sprint 全体のリスケなしで完了できた。
- **Swift 6 strict concurrency 対応の継続**。Sprint 1 で確立した `@MainActor` クラス + `nonisolated` delegate + `Task @MainActor` の戻りパターンを Sprint 2 全体（Persistence / Repository / StayDetector / LocationService / MapViewModel）でも徹底し、warning 0 を維持。
- **API キー漏洩 0 件を継続**。git 履歴に `AIza` 0 ヒット、`GoogleMaps-Info.plist` 実体は `.gitignore` で追跡外。Sprint 1 で築いた仕組みが Sprint 2 でも崩れていない。
- **iOS 26 SwiftData の特殊事情を Sprint 内に発見・修正できた**。`@Relationship` の配列プロパティに `= []` 既定値を付けないと iOS 26 では precondition でクラッシュする現象を S2-102 として起票し、即修正。Sprint をまたいだバグの持ち越しがゼロ。
- **テスト基盤の SIGTRAP も内部で完結**。LocationServiceTests の `ModelContainer` 強参照漏れによる間欠 SIGTRAP も S2-103 として捕捉、`retainedContainers` パターンで再発防止までユニットテストで担保。
- **permissions の整備で Xcode 関連コマンドの自動実行が可能に**。`.claude/settings.local.json` に `xcodebuild` / `xcrun simctl` / XcodeGen 系を追加したことで、Sprint 2 中の許諾ダイアログがほぼゼロ。Single-Agent モードの並列負担を緩和できた。
- **シミュレータ動作確認まで到達**（jun さん目視）。「総移動距離 3.74 km 復元」を実機相当の検証で確認できたことが、44 件のユニットテストだけでは出ない安心感につながった。
- **Dev-1 / Dev-2 の作業ファイル分割が綺麗に機能**。`Models/` `Services/Persistence/` を Dev-1、`Services/Trip/` `Services/Location/` `Features/History/` を Dev-2、共有ファイル（`MapView.swift` / `LocationService.swift`）は事前合意した範囲だけを触る運用で git 競合 0 件。

## Problem（問題だったこと）

- **Sprint 2 開発中に SwiftData の precondition クラッシュが発生**。`@Relationship` 配列に既定値が必要という iOS 26 の仕様を事前に把握できておらず、S2-001 完了後の S2-002 統合段階で初めて顕在化。修正自体は小さかったが、調査と切り分けに時間を要した。
- **LocationServiceTests の container 強参照漏れによる間欠 SIGTRAP**。テスト粒度では再現性が低く、Test Suite 全体実行のタイミング依存で出る/出ないが分かれた。`retainedContainers` 配列で寿命管理する形に集約し直して解消。
- **jun さん側の Xcode キャッシュ（DerivedData）が古いまま動作確認に進んだケース**で、何度かクラッシュレポートが上がった。jun さんの手元でクラッシュ → 再現条件確認 → DerivedData 削除で解消、というやり取りが複数回発生し、原因の切り分けに時間を消費した。
- **`.claude/settings.local.json` の hot reload が効かない**。permissions を追加しても次のメッセージから即時反映されないケースがあり、結局 DerivedData 削除（および別経路の状態リセット）で復帰させた。
- **QA は引き続き Single-Agent モード**。Task ツールが使えないため、Agent A が B（テスト実装）/ C・D・E（テスト実行）/ F（バグ修正）を兼任。30 観点 × 3 ランナー相当を直列実行する負荷は Sprint 1 と変わらず、本来の並列実行のメリットを得られなかった。
- **ローカル 14 コミットが未 push の状態**。Sprint 1 と同様、Sprint 中にこまめに push する運用にはまだ至れていない。

## Try（次に試すこと）

- **Sprint 3 開始前に、Sprint 2 申し送り 6 件のうち優先度の高いものをチケット化**。特に `restoreTodayTrip` のエラー昇格（観察 #4）は jun さんが日常使いする上で見える挙動になる可能性があるため、Sprint 3 の planning 時に優先度を再判定する。
- **iOS 26 SwiftData の特殊事情をプロジェクト内に記録**。`@Relationship` 配列の `= []` 既定値が必須である件を、`CLAUDE.md` の「技術スタック / 注意事項」セクション、もしくは `.scrum/notes/ios26-swiftdata.md` に書き起こす。次に類似実装が来たときの再発を防ぐ。
- **jun さんの Xcode キャッシュ問題が再発した場合の手順を README に追記**。「Claude が完成と言うまで Xcode は閉じておく → 完成宣言後に開いて Clean Build Folder（Shift+⌘+K） → ⌘R」の運用を明記する。Sprint 2 の途中混乱を Sprint 3 で繰り返さないため。
- **xcodebuild 実行前に毎回 `xcodebuild clean` を挟む運用**を試す。CI 観点で時間は数秒〜十数秒のロスだが、不可解なクラッシュ調査の時間ロスのほうが大きい。
- **QA 開始前に Task ツール可否を確認するルーチン**は Sprint 1 retro でも try に挙げていた。Sprint 2 では実施したが、結果として Task ツールが引き続き使えなかった。Sprint 3 開始時にもう一度確認し、ダメなら Single-Agent 前提で観点を絞り込む（ Sprint 1 retro と同じ Try を継続）。
- **Dev フェーズ完了直後と Sprint 完了時の 2 回 push 確認**は Sprint 1 retro の Try だが、Sprint 2 では Sprint 完了時の 1 回のみになった。Sprint 3 では Dev フェーズ完了直後にも push 確認を入れる運用を再度試す。
- **GitHub Issue クローズの一括コマンドをレビュー文書末尾に必ず添付**。Sprint 1 / Sprint 2 ともに jun さんの承認後に手動で実施する形だが、コマンド自体はレビュー文書末尾にドラフトを置くと迷わない（今 Sprint も末尾に提示済）。

---

## メトリクス

| 指標 | 値 | Sprint 1 比較 |
|---|---|---|
| 計画チケット数 | 8 | -1（Sprint 1 は 9） |
| 完了チケット数 | 8 | 同等 |
| 完了率 | 100% | 同等 |
| 持ち越しチケット | 0 | 同等 |
| Sprint 中コミット数 | 14 | 同等（Sprint 1 も 14） |
| 変更ファイル数 | 47 | +23（規模ほぼ倍） |
| 追加行数 / 削除行数 | +2740 / -80 | +1348 / +22（約 2 倍） |
| ユニットテスト数 | 44 | +30（Sprint 1 末は 14） |
| ユニットテスト pass 率 | 100% | 同等 |
| ビルド warning / error | 0 / 0 | 同等 |
| バグチケット起票数 | 3（S2-101 / S2-102 / S2-103） | +2（Sprint 1 は 1） |
| 残存バグ | 0 | 同等 |
| QA 観点充足 | 75 / 75 | +30（Sprint 1 は 30） |

## アクションアイテム（Sprint 3 開始前までに）

- [ ] jun さん: シミュレータでの追加検証（任意）— 長時間ドライブシナリオでの 10 分滞留 → PinRecord 自動生成の確認
- [ ] PO/SM: ユーザー承認後、ローカル 14 コミットを `origin main` に push
- [ ] PO/SM: ユーザー承認後、GitHub Issues #10〜#17 をクローズ（コメント: "Sprint 2 で実装完了"）
- [ ] PO/SM: `.scrum/config.md` の `current_sprint` を 3 に、`sprint_phase` を `planning` に更新（合意後）
- [ ] PO/SM: Sprint 3（自宅設定 / 常時・トリガーモード切替 / お店情報 MKLocalSearch 連携）の planning を実施
- [ ] PO/SM: Sprint 2 申し送り 6 件のうち、Sprint 3 で扱うものを planning 時に決定
