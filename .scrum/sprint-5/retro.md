# Sprint 5 Retrospective

開催日: 2026-05-06
参加: PO/SM（Opus）/ Dev-1（Sonnet）/ Dev-2（Sonnet）/ QA Agent A（Opus, Single-Agent モード）

---

## Sprint 4 retro Try の達成状況

Sprint 5 開始時点で Sprint 4 retro が挙げていた Try 項目への取り組み結果:

| # | Sprint 4 Try | Sprint 5 結果 | 評価 |
|---|---|---|---|
| 1 | Dev フェーズ完了基準に `xcodebuild clean build` の warning 数チェックを追加 | **達成**。`.scrum/process/dev-completion-checklist.md` を新規作成し Sprint 5 から運用開始。各チケットの board.md に「フル再ビルド warning」スタンプ列を追加 | Keep |
| 2 | Sonnet サブエージェントの sandbox 制約を settings.json で解消 | **未達**。jun さん指示「グローバル設定を変えるのは怖いのでメイン代行で継続」により Sprint 5 では現状維持。長期方針として Sprint 6 以降も同じ運用 | 判断保留（jun さん意向に従う） |
| 3 | `.scrum/notes/ios26-api-changes.md` に「新規 API 採用時は置換チェーンを 2 段先まで確認」のルール追記 | **達成**。Sprint 4 retro 末尾で更新済み。Sprint 5 では Dev エージェントプロンプトで継続参照 | Keep |
| 4 | Sprint 5 開始時に Task ツール可否を再確認 | **未達のまま継続**。Sprint 5 でも Single-Agent QA モードで実施（Task ツールが使えなかった） | Sprint 6 でも継続 Try |
| 5 | Dev フェーズ完了直後に push 候補を提示 | **未達**。Sprint 5 でも Sprint 完了時の 1 回提示にとどまった | Sprint 6 でも継続 Try |
| 6 | `.scrum/notes/simulator-scenarios.md` に Drive / Dropbox 認証フローを追記 | **未達**。Sprint 5 中に追記しなかった。jun さん向けの実 OAuth 確認手順は review.md 内のテーブルでカバーしたが、ノートへの集約は Sprint 6 で実施 | Sprint 6 で取り込み |
| 7 | GitHub Issue クローズの一括コマンドを review 末尾に添付 | **達成**。Sprint 5 review.md 末尾にコマンドドラフト記載 | Keep |
| 8 | Sonnet 化の効果を Sprint 5 でも継続検証 | **達成**。Sprint 5 review「モデル切替の効果」セクションで Sprint 4/5 比較を記録。所見は「品質低下なし、ただし Critical/High 統合バグはプロセス側の取りこぼしで連続発生」 | Keep |
| 9 | **DI 経路統合テストの自動化**（Sprint 3 retro Try からの継続強化） | **未達 → QA-S5-001 / QA-S5-002 として再発**。Sprint 5 plan で具体ガイドラインに落ちず、`CloudUploadCoordinator` 追加時に DI 検証が漏れた | **要改善・Sprint 6 で強化必須** |

→ Sprint 4 retro Try 9 件中、達成 4 件 / 未達のまま継続 4 件 / 要改善 1 件。**特に #9 は QA-S5-001 / QA-S5-002 として顕在化した重大な取りこぼしであり、Sprint 6 で具体ガイドラインに落とす必要がある。**

---

## Keep（続けること）

- **メイン代行運用が安定して機能した**。Sonnet サブエージェントの sandbox 制約により xcodebuild が拒否される現象は Sprint 5 でも継続したが、Dev エージェントが「ビルド確認をお願いします」と要請 → メインエージェント（Opus）が `xcodebuild clean build` / `xcodebuild clean test` を代行する運用が確立。各チケットの board.md に「メイン代行確認済」スタンプを残せた。jun さん指示「settings.json は変えない」方針と整合する形で運用を回せたのは Sprint 5 の重要な学び。
- **Apple 純正のみで Google Drive 連携を軽量実装する判断**（S5-001）。Dev-2 が公式 SDK（GoogleSignIn-iOS / GoogleAPIClientForREST）を採用せず、ASWebAuthenticationSession + URLSession + CryptoKit + Keychain Services の組み合わせで OAuth PKCE フローと Drive API V3 連携を自前実装した。SPM 依存追加ゼロ・バイナリサイズ増ゼロを達成。Sprint 6 で Dropbox を追加するときも `CloudStorageProvider` プロトコル経由で同パターンを再利用できる設計。jun さんの「具体的な SDK 選定は Dev-2 の判断で OK」という委任が成功した。
- **QA Single-Agent モードでリリースブロッカーを早期検出 + スプリント内修正**できた。QA-S5-001（Critical：本番経路で `CloudUploadCoordinator` が nil）と QA-S5-002（High：DI 検証テスト未整備）は **スプリントゴール検証条件 #2 / #3 を実質達成不能にしていた**重大バグだったが、Agent A がコードレビューで検出 → 同セッション内で修正 → 回帰テスト追加までを完遂。修正コミット（`0f17622`）後にメイン代行で `xcodebuild clean test` 173/173 pass を確認できた。Single-Agent モードでも「観点設計 + 即時修正 + 回帰テスト追加」のサイクルが動くことを Sprint 5 でも実証。
- **Dev フェーズ完了基準の運用開始**（Sprint 4 retro Try）。`.scrum/process/dev-completion-checklist.md` を新規作成し、各 Dev が自分の担当チケット完了前に「ユニットテスト pass / フル再ビルド warning 数 / iOS 26 API 整合 / board.md 状態更新」を board.md スタンプに残す運用を Sprint 5 から開始。Sprint 4 末で残っていた MapView Coordinator warning（S5-008）とテスト群 @MainActor warning（S5-009）も Sprint 5 末で warning 0 達成できた。
- **PinRecord.address 追加で Sprint 4 申し送り（QA-S4-002）を解消**（S5-007）。Sprint 4 retro で「dead code 相当の no-op で機能影響なし」と判定していた `addressFromPlaceURL` を Sprint 5 で正面から取り込み、CalendarSyncService の 3 段フォールバック（placeName → address → 座標）を文言通りに成立させた。前スプリントの申し送りを次スプリントで確実に潰す運用が継続。
- **Dev-1 / Dev-2 のファイル分割が引き続き機能**。Sprint 5 では `Models/AppSettings.swift` / `Features/Settings/SettingsView.swift` / `GPSLogger/App/RootView.swift` の 3 ファイルが共有候補だったが、plan.md の事前合意通り **git 競合 0 件**で完了。Sprint 1〜4 と同様の品質を Sprint 5 でも維持。
- **API キー漏洩 0 件を継続**。Sprint 1 で築いた `.gitignore` + `AIza` grep の体制が Sprint 5 でも崩れていない。OAuth 関連の機密値（アクセストークン / リフレッシュトークン）は Keychain Services に保存されるため、コードリポジトリには出ない設計。

## Problem（問題だったこと）

- **QA-S5-001 / QA-S5-002 が Sprint 4 retro Try「DI 経路統合テストの定型化」の取りこぼしで発生した**。Sprint 4 retro で「DI 経路統合テストの自動化」を Try に挙げたが、Sprint 5 plan / `dev-completion-checklist.md` に**具体ガイドラインとして落ちなかった**。結果、Sprint 5 で `CloudUploadCoordinator` / `CloudUploadRetryQueue` という新規サービスが追加されたとき、`RootView.init()` で生成・注入する処理が抜け落ち、`LocationService.cloudUploadCoordinator` が常に nil → 自動アップロードが本番経路で発火しないという**スプリントゴール達成不能レベルの統合バグ**を生んだ。Sprint 3 の QA-S3-001（同型）→ Sprint 4 retro Try → Sprint 5 で再発、というパターンが見えており、retro Try が「概念だけ」で具体ガイドラインに落ちないと再発するという学びを得た。
- **RootView.init が肥大化していたために QA-S5-001 修正が「一覧で見るとどこに何が入っているか分かりにくい」状態**。`CloudUploadCoordinator` / `CloudUploadRetryQueue` を新規生成し `LocationService` に注入する処理を `RootView.init` に追加したが、既に `AppSettings` / `GoogleDriveSyncService` / `CalendarSyncService` 等の生成も RootView で行っていたため、init 内が長くなった。これは将来また新しいサービスが追加されたときに同じ問題（DI 漏れ）を生むリスクが残る。
- **QA セッション中断と再開時のハンドオーバー不整合**。QA Single-Agent モードで QA-S5-001 / QA-S5-002 修正コードを書いたあと、xcodebuild の権限が当該セッションで無く中断 → 別セッションで commit → board.md 更新まで複数セッションをまたいだ。`.claude-handover.md` を A 分岐 / B 分岐で記載することで対応したが、commit 状態と handover の更新タイミングが「commit 前下書き保存 → commit 後 TL;DR 追記」という変則的な順序になり、再開時のセッションが状況把握に時間を要した。
- **Info.plist のプレースホルダー値管理が Sprint 5 中に整理できなかった**（QA-S5-003）。`GoogleDriveOAuthClientID` と `CFBundleURLSchemes` がプレースホルダーのまま git に追跡されており、jun さん側で実 OAuth テストするためには手動で値を埋める必要がある。`GoogleMaps-Info.plist` のような gitignore + .example パターンは Sprint 1 で確立済だったが、OAuth 用の同パターン化を Sprint 5 中に取り込めなかった。
- **Single-Agent QA モードの継続**。Sprint 5 でも Task ツールが使えず、Agent A が観点設計（A）/ テスト実装（B）/ テスト実行（C・D・E）/ バグ修正（F）を兼任。Sprint 5 の観点数は 130（Sprint 4 の 110 から +20）で、OAuth / クラウド I/O / リトライキュー / NWPathMonitor / UN 通知という新規領域が増えたことで負荷感は引き続き高かった。Sprint 1〜4 retro でも継続課題として挙がっており、解消方法が見つかっていない。
- **17 コミットが未 push のまま Sprint レビューに突入**。Sprint 1〜4 と同様、Sprint 中にこまめに push する運用にはまだ至れていない。Sprint 4 retro Try「Dev フェーズ完了直後に push 候補を提示」も未達。

## Try（次に試すこと）

- **DI 経路カバレッジテストを `dev-completion-checklist.md` に組み込む**（最優先）
  - 責任者: PO/SM（チェックリスト改訂）+ Dev 全員（運用遵守）
  - 成功指標: Sprint 6 で新規サービスを追加した場合、当該サービスについて RootView.init 経由の DI が verify される統合テストが「Dev フェーズ完了前」に追加されている。Sprint 6 QA で同型の DI 漏れバグが 0 件
  - 具体策:
    1. `.scrum/process/dev-completion-checklist.md` の Dev フェーズ完了チェックに「**新規サービスを追加した場合、`RootViewIntegrationTests` に DI 検証テストを 1 件以上追加すること**」を明文化
    2. plan.md のチケット起票時に「DI 検証テスト要否」をフラグとして判定し、必要な場合は受け入れ条件に明記
    3. Sprint 6 開始時に `RootViewIntegrationTests.swift` を雛形として、`CloudUploadCoordinator` / `CloudUploadRetryQueue` の DI 検証テスト（Sprint 5 で追加した 1 件）を「DI 検証テストの書き方サンプル」としてコメント化
- **`AppDependencyContainer` 型を導入し RootView.init を整理**（推奨）
  - 責任者: Dev-1（UI 周辺の DI 整理経験あり）
  - 成功指標: Sprint 6 末で `RootView.init` の本体行数が現在の 2/3 以下に縮小し、新規サービス追加時の編集箇所が `AppDependencyContainer` に集約される。DI 検証テストが `AppDependencyContainer` に対する単体テストに移行し、`RootViewIntegrationTests` は「Container を生成して RootView に渡す」薄いテストに集約される
  - リスク: SwiftUI の `@StateObject` / `@Environment` との相性確認が必要。Sprint 6 で実装難度が高いと判定された場合は Sprint 7 へ繰越判断
- **Info.plist の OAuth 設定を gitignore + .example パターン化**（QA-S5-003 解消）
  - 責任者: Dev-2（GoogleMaps-Info.plist で同パターンを実装した経験あり）
  - 成功指標: `GPSLogger/Resources/GoogleDriveOAuth-Info.plist` を `.gitignore` に追加し、`GoogleDriveOAuth-Info.plist.example` を git 追跡。`.scrum/notes/google-drive-oauth-setup.md` で jun さん向けに「Google Cloud Console での発行手順 + .example をコピーして値を埋める手順」を整備
- **CloudUploadRetryQueue の CSV 出力失敗時の挙動を整理**（QA-S5-004 解消）
  - 責任者: Dev-2
  - 成功指標: 「A. retryCount を加算」「B. csvFailureCount 別カウンタ追加」「C. 現状維持」の 3 案から方針判断 → 実装 + テスト追加。Sprint 6 末で `CloudUploadRetryQueue` のドキュメントコメントに失敗ケースの挙動が明記されている
- **シミュレータ動作確認シナリオを `.scrum/notes/simulator-scenarios.md` に集約**（Sprint 4 retro Try の継続）
  - 責任者: PO/SM
  - 成功指標: Sprint 5 review.md「シミュレータ動作確認の依頼項目」7 項目を `simulator-scenarios.md` に追記し、Sprint 6 では新規シナリオ（Dropbox 認証 / DB クリア機能等）を同ファイルに追加する形で運用
- **Sprint 6 開始時に Task ツール可否を再確認**（Sprint 1〜5 retro 継続課題）
  - 責任者: PO/SM
  - 成功指標: Sprint 6 planning 冒頭で Task ツール起動を試行 → 起動できれば QA Multi-Agent モード復活、ダメなら Single-Agent モードで観点を Critical/High に絞り込む運用継続
- **節目ハンドオーバー更新の「commit 前 / commit 後」の順序を `.claude-handover.md` 内テンプレ化**
  - 責任者: PO/SM（メインセッション側）
  - 成功指標: Sprint 6 中の中断・再開時に再開セッションが「いまどの状態か」を 1 分以内に判定できる。`.claude-handover.md` 冒頭の TL;DR 規約を明文化
- **Dev フェーズ完了直後に push 候補を提示する運用**（Sprint 4 retro Try の継続）
  - 責任者: PO/SM
  - 成功指標: Sprint 6 中に最低 1 回、Dev フェーズ末で jun さんに「ここまでの X コミットを push しますか」と提示する。jun さんの判断で push or 据え置き
- **Sonnet 化の効果検証は継続する**（Sprint 4 retro Try）
  - 責任者: PO/SM
  - 成功指標: Sprint 6 review に「Sprint 4 / 5 / 6 のメトリクス比較」テーブルを追加し、3 スプリント連続で品質傾向を観察

---

## メトリクス

| 指標 | Sprint 5 | Sprint 4 比較 |
|---|---|---|
| 計画チケット数 | 8（S5-002 は Sprint 6 へ繰越合意済 / 9 件中 1 件繰越） | 同等 |
| 完了チケット数 | 8 | 同等 |
| 完了率 | 100% | 同等 |
| 持ち越しチケット | 1（S5-002 / Sprint 6 へ繰越合意済） | +1（Sprint 4 は 0） |
| Sprint 中コミット数 | 17（Sprint 4 末から HEAD まで） | +6（Sprint 4 は 11） |
| ユニットテスト数 | 173 | +52（Sprint 4 末は 121） |
| ユニットテスト pass 率 | 100% | 同等 |
| ビルド warning / error | 0 / 0（Sprint 4 申し送り 2 件解消） | 同等 |
| バグチケット起票数 | 4（QA-S5-001〜004） | +2（Sprint 4 は 2） |
| 残存バグ（Critical / High） | 0 件 | 同等 |
| 残存バグ（Medium / Low） | 2 件（Sprint 6 申し送り） | -1（Sprint 4 は 1 件 = QA-S4-002 を Sprint 5 で解消） |
| QA 観点充足 | 130 / 130 | +20（Sprint 4 は 110） |
| **Sprint 内 Critical バグ修正** | **1（QA-S5-001）** | +1（Sprint 4 は 0） |
| **Sprint 内 High バグ修正** | **1（QA-S5-002）** | 同等（Sprint 4 は QA-S4-001 = 1 件） |
| Sprint 内コンパイルエラー | 0 | -1（Sprint 4 は 1） |
| git 競合 | 0 件 | 同等 |

QA 観点が Sprint 4（110）から 130 へ増えたのは、Sprint 5 のスコープが「OAuth フロー / クラウド I/O / リトライキュー / NWPathMonitor / UN 通知」と新規領域が多かったため。Sprint 6 は「Dropbox + リリース準備 + DB 機能」になるため、観点数は 130〜150 を想定。

### トークンコスト推定（Sonnet 化の継続検証）

Sprint 4 から運用開始した `scrum-dev-agent: Sonnet` 化を Sprint 5 でも継続:

- **Dev エージェント単体のトークンコスト**: Sprint 4 と同じく **Opus 比で約 1/5 〜 1/3** に抑えられた
- **品質低下**: 観測されず（チケット完遂率 100% / git 競合 0 件 / テスト追加 +52 件）
- **副作用**: メイン代行運用が引き続き必要（settings.json は jun さん意向で据え置き）
- **観察ポイント**: Sprint 4 / 5 で連続して Critical/High 統合バグが発生しているが、これは Sonnet 化の影響というより **「DI 経路統合テストの定型化」が plan に落ちなかったプロセス側の問題**。Sprint 6 retro Try でこの点を強化する

→ Sonnet 化は継続。意思決定（PO/SM）と観点設計・品質判定（QA Orchestrator）は Opus を維持する戦略を Sprint 6 以降も継続する。

---

## アクションアイテム（Sprint 6 開始前までに）

- [ ] jun さん: Sprint 5 review.md「シミュレータ動作確認の依頼項目」7 項目（特に項目 1 = Info.plist の OAuth ClientID 埋め）の確認
- [ ] jun さん: 本 retro Try の優先度判断（特に「DI 経路カバレッジテストの定型化」「`AppDependencyContainer` 導入」「Info.plist の gitignore + .example 化」）
- [ ] PO/SM: ユーザー承認後、ローカル 17 コミット + Sprint 5 review/retro 1 コミット = 計 18 コミットを `origin main` に push
- [ ] PO/SM: ユーザー承認後、GitHub Issues #35 / #37 / #38 / #39 / #40 / #41 / #42 / #43（S5-001 + S5-003〜S5-009 想定）をクローズ（コメント: "Sprint 5 で実装完了"）。Issue #36（S5-002 Dropbox）は Sprint 6 へ繰越のため close しない
- [ ] PO/SM: `.scrum/config.md` の `current_sprint` を 6 に、`sprint_phase` を `planning` に更新（合意後）
- [ ] PO/SM: Sprint 6 のスコープ確定（Dropbox + QA-S5-003 / QA-S5-004 解消 + DB クリア機能 + DB 自動消去 + アプリアイコン + ローンチスクリーン + バッテリー最適化 + プライバシーマニフェスト + DI 経路テスト定型化）
- [ ] PO/SM: Sprint 6 planning 冒頭で Task ツール可否を再確認
- [ ] PO/SM: `.scrum/process/dev-completion-checklist.md` に「DI 検証テスト追加」のチェック項目を追記
- [ ] PO/SM: `.scrum/notes/simulator-scenarios.md` に Sprint 5 のシミュレータ動作確認 7 項目を追記
