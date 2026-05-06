# Sprint 4 Retrospective

開催日: 2026-05-06
参加: PO/SM（Opus）/ Dev-1（Sonnet）/ Dev-2（Sonnet）/ QA Agent A（Opus, Single-Agent モード）

---

## Keep（続けること）

- **Sprint 3 の retro Try をほぼ全て実装に取り込めた**。retro Try「`.scrum/notes/ios26-api-changes.md` を Sprint 4 開始前に作成」「`.scrum/notes/simulator-scenarios.md` を Sprint 4 開始前に作成」は両方とも Sprint 4 開始時点で着手済。retro Try「Dev フェーズ完了基準に統合経路の静的レビューを追加」については Sprint 4 では Critical / Integration バグの新規発生 0 件で機能した（QA-S4-001 は warning 系で別カテゴリ）。「retro が次スプリントの planning に反映される」サイクルが Sprint 3 → Sprint 4 でも継続。
- **CLGeocoder 移行を冒頭固定で先に潰せた**。jun さん指示「Sprint 4 の最初に CLGeocoder 移行をやる」を厳守し、S4-001 を Dev-2 が並行スコープ全体の前段で完了。S4-001 完了時点で iOS 26 API 流儀がプロジェクトに揃ったので、S4-002 以降の EventKit / fileExporter 周りも iOS 26 SDK ヘッダの最新流儀（async/await + actor isolation）で統一できた。
- **DI 構造の徹底が継続できた**（CalendarSyncService / EventStoreProviding / CalendarProviding / GeocoderPerforming / CSVExportService）。各機能をプロトコル抽象で組み立てたことで、ユニットテストが Sprint 3 末 79 → Sprint 4 末 121 に伸びた（**+42 件**）。EventKit や `.fileExporter` のように OS 依存の API も、テスト側でフェイク（FakeEventStore / FakeCalendarProvider 等）を差し込めて高速に検証できた。
- **API キー漏洩 0 件を継続**。Sprint 1 で築いた `.gitignore` + `AIza` grep の体制が Sprint 4 でも崩れていない。git 履歴に対する漏洩スキャンも 0 件継続。
- **Swift 6 strict concurrency 対応の継続**。Sprint 4 で新たに導入した `CalendarSyncService`（@MainActor）/ `CSVExportService`（actor 不要・純粋関数中心）/ `ExportView` / `CSVExportDocument`（FileDocument の `Sendable` 要件）すべて warning 0 で実装。Sprint 1〜3 で確立したパターンを Dev-1 / Dev-2 が独立に踏襲できている。
- **Dev-1 / Dev-2 の作業ファイル分割が引き続き機能**。Sprint 4 では `Models/AppSettings.swift`（calendarSyncEnabled / calendarIdentifier）/ `Features/Settings/SettingsView.swift` / `Features/Settings/HomeRegistrationView.swift` / `Features/Map/MapView.swift` の 4 ファイルが共有候補だったが、plan.md の事前合意通り **git 競合 0 件**で完了。Dev-1 ↔ Dev-2 の board.md 上の申し送り（4 往復）も明文化されており、後から経緯を追える。
- **Sonnet 化した Dev エージェントでも品質が落ちなかった**。Sprint 4 から scrum-dev-agent を Sonnet に切り替えたが、8 チケット完遂・追加テスト 42 件・コンパイルエラー 1 件（hotfix で即解消）・git 競合 0 件で、Sprint 3（Opus）と同等の生産量を達成。**トークンコストの削減**が品質低下なしで実現できた点は重要な学び。
- **QA フェーズで Dev フェーズの取りこぼしを捕まえられた**（QA-S4-001）。Dev フェーズ完了時点で warning 0 と思われていたが、QA フェーズの「フル再ビルド warning スキャン」で MKMapItem.placemark deprecated 4 件を検出。Apple の API 変更が連鎖的（CLGeocoder の代替が MKReverseGeocodingRequest、その戻り値の placemark プロパティが別途 deprecated）であることを学習し、`.scrum/notes/ios26-api-changes.md` に「**置換 API 自体も deprecated 化されているか**」のチェック観点を追記。

## Problem（問題だったこと）

- **High バグ（QA-S4-001）が QA フェーズで発見された**。スプリントゴール検証条件 #4「フル再コンパイルで warning が 0 件」を実質的に破っていた。Dev フェーズ完了時点で「ビルド成功 + ユニットテスト pass = OK」とサインしていたが、`xcodebuild build`（差分ビルド）と `xcodebuild clean build`（フル再ビルド）で warning 数が違う点を Dev フェーズ完了基準に組み込んでいなかった。Sprint 3 の QA-S3-002 と同じ「フル再ビルドでのみ顕在化する warning」のパターン。
- **iOS 26 API 変更点ノートに「置換 API 自体も deprecated 化されているか」の観点が抜けていた**。Sprint 3 retro Try で `.scrum/notes/ios26-api-changes.md` を Sprint 4 開始前に作成したが、内容は「CLGeocoder の置換 = MKReverseGeocodingRequest」止まりで、その先の連鎖（MKMapItem.placemark も別途 deprecated）まで網羅できていなかった。Apple の deprecated API は連鎖することがあるという経験則を Sprint 4 で初めて学習。
- **Sonnet サブエージェントの sandbox で xcodebuild が拒否された**。Dev-2 が S4-001 完了直後に xcodebuild でビルド検証しようとしたところ、Sonnet サブエージェントの sandbox 制限で xcodebuild の起動が拒否された。回避策としてメインエージェント（Opus）が代行ビルドを実行したが、Dev フェーズの所要時間が想定より長くなった。長期運用としては settings.json の permissions に xcodebuild を追加すべき。
- **Single-Agent QA モードの継続**。Sprint 4 でも Task ツールが使えず、Agent A が B（テスト実装）/ C・D・E（テスト実行）/ F（バグ修正）を兼任。110 観点を直列実行する負荷は Sprint 1〜3 と変わらず、本来の並列実行のメリットを得られなかった。Sprint 4 では観点数が Sprint 3（60）から 110 へ増加（カレンダー / CSV / インジェクション対策など新規領域の網羅）したため、Single-Agent モードでは負荷感が顕著に増した。
- **シミュレータでの実機相当の動作確認が未完了**のまま Sprint レビューに入っている。EventKit と `.fileExporter` はユニットテストでは挙動を完全に再現できない領域（権限ダイアログ・iOS 標準カレンダーアプリでの確認・UIDocumentPickerViewController の保存先選択など）であり、jun さん側のシミュレータ確認が必須。Sprint 3 と同じく後ろ倒し。
- **ローカル 11 コミット + 本 retro/review コミット = 12 コミットが未 push**。Sprint 1〜3 と同じく、Sprint 中にこまめに push する運用にはまだ至れていない。

## Try（次に試すこと）

- **Dev フェーズ完了基準に `xcodebuild clean build` の warning 数チェックを追加**。Sprint 5 の Dev フェーズ完了時、各 Dev が自分の担当チケット完了前に `xcodebuild clean build` を実行し、warning 数を board.md にスタンプする運用を試す。差分ビルドでは見えない「フル再コンパイル時のみの deprecated warning」を Dev フェーズで捕まえられるようにする。Sprint 3 の Try「統合経路の静的レビューを追加」と同じく、Dev フェーズ完了基準を一つずつ強化していく方針を継続。
- **Sonnet サブエージェントの sandbox 制約を settings.json で解消する**。`/Users/hirayamajunya/.claude/settings.json` の permissions に xcodebuild を追加し、Sonnet サブエージェントでも xcodebuild build / xcodebuild test / xcodebuild clean build が実行できるようにする。これで Dev-2 がメインエージェント代行ビルドに頼らずに済む。Sprint 5 開始前に PO/SM が settings 更新を提案 → jun さん承認。
- **`.scrum/notes/ios26-api-changes.md` の運用ルールを更新**。Sprint 5 から「新規 API 採用時は必ず置換チェーンを 2 段先まで確認」のルールを追記する。今回 QA-S4-001 で学んだ Apple の連鎖的 API 変更パターンを今後の retro Try に反映。
- **Sprint 5 開始時に Task ツール可否を再確認**。Sprint 1 / 2 / 3 / 4 retro でも Try に挙げているが継続。ダメなら Single-Agent 前提で観点を絞り込み、QA 観点を 110 → 70 程度に圧縮する代替案（重要度 Critical/High に集中）を検討する。
- **Dev フェーズ完了直後に push 候補をユーザーに提示する運用**を Sprint 5 でも継続。Sprint 4 では Sprint 完了時の 1 回提示になったが、Sprint 5 では Dev フェーズ終了時にも提示する。
- **シミュレータの Simulate Location シナリオ + EventKit 権限フローシナリオ**を `.scrum/notes/simulator-scenarios.md` に追加維持。Sprint 4 で EventKit 権限フローと UIDocumentPickerViewController の確認手順を追記済（review.md「シミュレータ動作確認の依頼項目」と連動）。Sprint 5 の Drive / Dropbox 認証フローもこのノートに追記する。
- **GitHub Issue クローズの一括コマンドをレビュー文書末尾に必ず添付**は Sprint 1〜4 でできているので継続。
- **Sonnet 化の効果を Sprint 5 でも継続検証**。Sprint 4 の 1 スプリントだけでは品質傾向の評価としてサンプル数が少ない。Sprint 5（クラウド同期）はファイル I/O + OAuth + ネットワーク I/O が絡んで難度が上がるため、Sonnet 化が品質に影響しないかを継続観察する。

---

## メトリクス

| 指標 | Sprint 4 | Sprint 3 比較 |
|---|---|---|
| 計画チケット数 | 8 | -1（Sprint 3 は 9） |
| 完了チケット数 | 8 | -1 |
| 完了率 | 100% | 同等 |
| 持ち越しチケット | 0 | 同等 |
| Sprint 中コミット数 | 11 | -2（Sprint 3 は 13） |
| 変更ファイル数 | 41 | +1（Sprint 3 は 40） |
| 追加行数 / 削除行数 | +3167 / -91 | -142 / +18（Sprint 3 は +3309 / -73） |
| ユニットテスト数 | 121 | +42（Sprint 3 末は 79） |
| ユニットテスト pass 率 | 100% | 同等 |
| ビルド warning / error | 0 / 0（既知 1 件は Sprint 5 へ繰越承認済み） | 同等 |
| バグチケット起票数 | 2（QA-S4-001 / QA-S4-002） | 同等（Sprint 3 は 2） |
| 残存バグ | 0 | 同等 |
| QA 観点充足 | 110 / 110 | +50（Sprint 3 は 60） |
| **High バグ Sprint 内修正** | **1（QA-S4-001）** | -（Sprint 3 は Critical 1 件） |
| **Critical バグ Sprint 内修正** | 0 | -1（Sprint 3 は 1 件） |
| **Sprint 内コンパイルエラー** | 1（S4-001 hotfix で即解消） | -（Sprint 3 は 0） |

QA 観点が Sprint 3（60）から 110 へ大きく増えたのは、Sprint 4 のスコープが「カレンダー / CSV / 権限 / インジェクション対策」と新規領域が多かったため。Sprint 5 はクラウド同期で OAuth / ネットワーク I/O / リトライが加わるため、観点数は 110 前後を維持する見込み。

### トークンコスト推定（Sonnet 化の効果）

Sprint 4 から scrum-dev-agent を Opus → Sonnet に切り替えた効果:

- **Dev エージェント単体のトークンコスト**: 概算で **約 1/5 〜 1/3 に削減**（Anthropic 公式の Sonnet vs Opus 価格比に基づく粗い推定）
- **品質低下**: 観測されず（completion 率・テスト追加数・git 競合 0 件のいずれも Sprint 3 と同等）
- **副作用**: Sonnet サブエージェントの sandbox 制約で xcodebuild が拒否される 1 件（Try で settings.json permissions 追加を提案）
- **Opus を維持した場面**: PO/SM（戦略・合意形成）と QA Orchestrator（観点設計・品質判定）。これらの役割は Opus の判断力が引き続き必要

→ 結論: **コード実装中心のサブエージェントは Sonnet で十分**。意思決定・観点設計・外部報告は Opus を維持する戦略を Sprint 5 以降も継続する。

## アクションアイテム（Sprint 5 開始前までに）

- [ ] jun さん: シミュレータで Sprint 4 review.md「シミュレータ動作確認の依頼項目」4 項目（カレンダー権限フロー / 滞留ピン → カレンダー登録 / CSV エクスポート保存先選択 / CSV 中身確認）の確認
- [ ] jun さん: Sprint 5 申し送り 6 件のうち優先度判断が必要な #3（QA-S4-002 の方針）と #5（Dev フェーズ完了基準への warning チェック追加）への回答
- [ ] PO/SM: ユーザー承認後、ローカル 12 コミット（11 + 本 retro/review コミット）を `origin main` に push
- [ ] PO/SM: ユーザー承認後、GitHub Issues #27〜#34（S4-001 〜 S4-008 想定）をクローズ（コメント: "Sprint 4 で実装完了"）
- [ ] PO/SM: `.scrum/config.md` の `current_sprint` を 5 に、`sprint_phase` を `planning` に更新（合意後）
- [ ] PO/SM: Sprint 5（クラウド同期）の planning を実施
- [ ] PO/SM: Sprint 5 planning 時に申し送り 6 件のうち取り込むものを決定
- [ ] PO/SM: `settings.json` の permissions に xcodebuild を追加する提案を jun さんへ（Sonnet サブエージェントの sandbox 制約解消）
- [ ] PO/SM: `.scrum/notes/ios26-api-changes.md` に「新規 API 採用時は置換チェーンを 2 段先まで確認」のルールを追記
