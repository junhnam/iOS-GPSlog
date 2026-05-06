# Sprint 5 Review

- スプリント期間: 2026-05-06（1 イテレーション完結）
- 体制: PO/SM（Opus）+ Dev x2（Dev-1 / Dev-2 / Sonnet）+ QA（Single-Agent モードで Agent A が代行 / Opus）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・ローカル 17 コミットが origin/main から先行・未 push）
- 最終コミット: `7a99e9e chore: Sprint 5 board.md を QA 完了状態に更新`

---

## スプリントゴール

> **移動記録をクラウドストレージに自動同期し、機器を変えても残せる状態にする**

→ **達成（条件付き合格 → ビルド確認済で正式合格）**

QA Single-Agent モードで Critical 4 件 + High 1 件のリリースブロッカー（実態は 1 つの統合バグ「`CloudUploadCoordinator` が本番経路で nil 注入」とそのテスト未整備）を検出 → スプリント内で即時修正 → `xcodebuild clean test` で 173/173 pass / warning 0 / error 0 を確認したうえでゴール達成と判定した。

検証根拠（plan.md の検証条件 5 項目）:

| # | 検証条件 | 結果 | 確認方法 |
|---|---|---|---|
| 1 | クラウド保存先（Google Drive）を選び、OAuth 認証ができる | 静的 OK / 実 OAuth は jun さん側 DEFER | S5-001 / S5-003 のテスト（OAuth PKCE フロー / Keychain 保存 / トークンリフレッシュ）+ コードレビュー |
| 2 | 自動同期 ON 時、記録停止のたびに「GPSログ/{日付}/data.csv」階層へ自動アップロードされる | **修正前: 不達 / 修正後: 静的 OK / 実 Drive 連携は jun さん側 DEFER** | QA-S5-001 修正で `RootView` で `CloudUploadCoordinator` を生成し `LocationService` に注入。回帰テスト 1 件追加で DI が崩れない仕組みを担保。S5-005 のテスト 5+ で動作検証 |
| 3 | アップロード失敗時にリトライキューが動き、5 回失敗で通知が出る | **修正前: 不達 / 修正後: 静的 OK** | QA-S5-001 修正で `startObservingNetwork()` + `processOnAppLaunch()` を `.task` で起動。S5-006 のテスト 4+ でリトライ動作と通知発火を検証 |
| 4 | PinRecord に address フィールドが追加され、CalendarSyncService の 3 段フォールバック（placeName → address → 座標）が文言通りに動く | OK | S5-007 のテスト 8 件 + コード静的レビュー。Sprint 4 申し送りの QA-S4-002（`addressFromPlaceURL` no-op）も同時解消 |
| 5 | フル再コンパイルで warning 0 件（既存 MapView Coordinator warning 1 件解消含む） | OK | S5-008（MapView Coordinator @MainActor 化）+ S5-009（テスト群 setUp/tearDown を async 版に統一）でフル再ビルド warning 0 達成。メイン代行 `xcodebuild clean test` で確認済 |

ユニットテスト + コード静的レビューでは 5 項目すべて OK。実 OAuth 認証 + Google Drive 上での実アップロード確認（クラウドサーバーに実際にファイルを上げる動作）はユニットテストでは再現できないため、別途 jun さんに依頼（後述「シミュレータ動作確認の依頼項目」参照）。

---

## 完了チケット（8 / 8）

| ID | タイトル | 担当 | コミット | 備考 |
|---|---|---|---|---|
| S5-001 | Google Drive SDK 軽量実装 + OAuth PKCE | dev-2 | `8c43aaf` | **公式 SDK 不採用判断**。Apple 純正のみで実装（ASWebAuthenticationSession + URLSession + CryptoKit + Keychain Services）。SPM 依存追加ゼロ・バイナリサイズ増ゼロ。`CloudStorageProvider` プロトコルで抽象化し Sprint 6 の Dropbox 追加に備える設計 |
| S5-003 | クラウド保存先選択 UI | dev-1 | `3cc209e` | 設定画面「データ」セクションに `CloudStoragePickerView` を追加。プロバイダ選択 + 認証状態表示 |
| S5-004 | 自動同期 ON/OFF 設定 | dev-1 | `3cc209e` | `AppSettings.cloudAutoSyncEnabled` を新規追加。Toggle と認証済プロバイダの存在チェックで disable 制御 |
| S5-005 | 「GPSログ/{日付}/data.csv」階層での自動アップロード | dev-2 | `14f4936` + `9675c11` | `CloudUploadCoordinator` 新規。記録停止 → CSV 出力 → Drive アップロードを 1 経路で完結 |
| S5-006 | 同期失敗時のリトライ + 通知 | dev-2 | `14f4936` | `CloudUploadRetryQueue` 新規（`PendingUpload` を SwiftData @Model で永続化）。指数バックオフ + 5 回失敗で UN 通知 + ネットワーク回復時の自動再試行（`NWPathMonitor`） |
| S5-007 | PinRecord.address 追加 + addressFromPlaceURL 削除（QA-S4-002 解消） | dev-2 | `d1d1476` | `PinRecord.address: String?` 追加。`PlaceLookupService` で逆ジオコーディング結果を address に書き戻し。CalendarSyncService の 3 段フォールバックを「文言通り」に成立させた |
| S5-008 | MapView Coordinator strict concurrency warning 解消 | dev-1 | `8051930` | Coordinator を `@MainActor` 化。Sprint 4 申し送り #1 をクリア |
| S5-009 | テスト群の @MainActor strict concurrency warning 解消 | dev-1（メイン代行） | `1ae29e9` | 12 テストファイルの `setUp`/`tearDown` を async 版に統一。フル再ビルド warning 0 達成。Sprint 4 申し送り #2 を Could 枠で吸収 |

加えて Agent A が QA フェーズで QA-S5-001 / QA-S5-002 修正コミット（`0f17622`）を担当し、QA Single-Agent モードで Critical/High リリースブロッカーをスプリント内で解消した。

## 未完了チケット（Sprint 6 へ繰越）

| ID | タイトル | 理由 | 次スプリントへ |
|---|---|---|---|
| S5-002 | Dropbox SDK 導入 + OAuth 認証 | Sprint 5 planning 時の jun さん承認で「Sprint 5 では Google Drive のみ・Dropbox は Sprint 6 へ繰越」と合意 | はい（Issue #36 に sprint-6 ラベル付与済） |

---

## メイン代行修正（Dev エージェントの sandbox 制約により Opus メインが代行）

| コミット | 内容 |
|---|---|
| `f2cc406` | Cloud 系コードを internal で統一 + iOS 26 deprecated 解消 + ネットワーク復旧時のバックオフ無視（`processQueue(ignoringBackoff: true)`） |
| `a45a2f3` | テストの async-safe ロック（`NSLock.withLock`）と FakeHTTPClient 引数順序の修正 |
| `1ae29e9` | テスト群 setUp/tearDown を async 版に統一（S5-009 として） |
| `0f17622` | **QA-S5-001 / QA-S5-002 修正**: RootView で `CloudUploadCoordinator` / `CloudUploadRetryQueue` を生成し `LocationService` に注入。`.task` で起動時の `processOnAppLaunch` + `startObservingNetwork` を発火。回帰テスト `test_locationService_stopRecording_invokesCloudUploadCoordinator_QA_S5_001` を 1 件追加。Sprint 5 リリースブロッカー解消 |

メイン代行修正の副作用は QA Single-Agent モードでレビュー済（最終レポート「メイン代行修正の副作用所見」参照）。`public → internal` 一括化、iOS 26 deprecated 解消（ASPresentationAnchor の `init(windowScene:)` 経由生成）、`CloudStorageError.isRetryable` の到達不能 case 削除、復旧時バックオフ無視はいずれも論理的に等価 or 受け入れ条件を満たすために必要な修正と判定。

---

## バグチケット

### Sprint 内に修正済み

| ID | 概要 | 重大度 | 担当 | 修正コミット | 影響 |
|---|---|---|---|---|---|
| QA-S5-001 | `CloudUploadCoordinator` / `CloudUploadRetryQueue` が本番経路で未注入。`LocationService.cloudUploadCoordinator` が常に nil → 記録停止時の自動アップロードが本番で発火しない | **Critical** | qa-fixer（Agent A 兼任） | `0f17622` | スプリントゴール検証条件 #2 / #3 が達成不能だった。RootView での生成・注入で同根の派生 3 観点（A-04 / A-05 / A-06）も同時解消 |
| QA-S5-002 | `RootViewIntegrationTests` に `CloudUploadCoordinator` の DI 検証テストが無く、QA-S5-001 のような統合バグがユニットテスト緑のまま素通りした | **High** | qa-fixer（Agent A 兼任） | `0f17622` | Sprint 4 retro Try「DI 経路統合テストの定型化」の取りこぼし。QA-S5-001 と同時に DI 検証テスト 1 件追加で解消 |

QA-S5-001 はスプリントゴール検証条件 #2 / #3 を実質的に達成不能にしていた **Critical バグ**。Sprint 4 末で立てた retro Try「DI 経路統合テストの定型化」が Sprint 5 plan で具体ガイドラインに落ちず、`CloudUploadCoordinator` という新規サービスの追加で同型のバグが再発した。Sprint 5 retro で「DI 経路カバレッジテストの定型化」を継続強化 Try として再設定する（後述 retro.md 参照）。

### Sprint 6 へ申し送り

| ID | 概要 | 重大度 | 申し送り理由 |
|---|---|---|---|
| QA-S5-003 | `GoogleDriveOAuthClientID` と URL Scheme が Info.plist でプレースホルダー | **Medium** | コード側はガード済み（`authenticate()` 内で `clientID.isEmpty` チェック）。jun さん側で Google Cloud Console で発行した iOS OAuth クライアント ID を埋めるオペレーションが必要。Sprint 6 で `GoogleMaps-Info.plist` と同パターンの「`GoogleDriveOAuth-Info.plist`（gitignore + .example 提供）」運用を整理する |
| QA-S5-004 | `CloudUploadRetryQueue` の CSV 出力失敗時に `retryCount` が増えない | **Low / WARN** | 実害は小さい（次回 `enqueue` 時に retryCount は +1 される）。Sprint 6 で「A. CSV 出力失敗も retryCount を加算」「B. `csvFailureCount` 別カウンタ追加」「C. 現状維持」の 3 案から方針判断 |

---

## 品質

- ユニットテスト通過率: **100%（173 / 173 pass）**
  - Sprint 4 末: 121 件 → Sprint 5 末: 172 件 → QA 修正で +1 件 = **173 件（+52 件）**
  - Sprint 5 で追加された主なテストファイル / 領域:
    - GoogleDriveSyncService 周り: 4+（OAuth PKCE / トークンリフレッシュ / Keychain 保存 / アップロード）
    - CloudStoragePickerView 周り: 7（プロバイダ選択 / 認証状態 / 認証フロー連携）
    - 自動同期設定 / Toggle: 5（永続化 / disable 条件 / 認証済プロバイダ未選択時の挙動）
    - CloudUploadCoordinator: 5+（記録停止トリガー / プロバイダディスパッチ / autoSync OFF 時の挙動）
    - CloudUploadRetryQueue: 4+（指数バックオフ / 5 回失敗通知 / processOnAppLaunch / NWPathMonitor 復旧）
    - PinRecord.address 追加: 8（PlaceLookupService 書き戻し / 既存 DB マイグレーション互換 / 3 段フォールバック）
    - RootView DI 検証（QA-S5-002 修正）: +1（`test_locationService_stopRecording_invokesCloudUploadCoordinator_QA_S5_001`）
- ビルド: **warning 0 / error 0**（QA-S5-001 修正後 / メイン代行 `xcodebuild clean test` で確認済）
  - フル再コンパイル時の Swift プロダクションコード由来 warning: **0 件**
  - Sprint 4 申し送りの MapView Coordinator strict concurrency warning（S5-008）: **解消**
  - Sprint 4 申し送りのテスト群 @MainActor warning（S5-009）: **解消**
- 検出バグ: 4 件（Critical 1 + High 1 = Sprint 内修正済 / Medium 1 + Low 1 = Sprint 6 申し送り）
- 残存バグ: Critical/High **0 件**、Medium 1（QA-S5-003: Info.plist プレースホルダー / jun さん側オペレーション）、Low 1（QA-S5-004: CSV 出力失敗時 retryCount / Sprint 6 改善候補）
- API キー漏洩スキャン: コードベース・git 履歴ともに **0 件ヒット**（Sprint 1 から継続）。OAuth クライアント ID は機密値ではないが、アクセストークン / リフレッシュトークンは Keychain Services に保存されている（コードリポジトリには出ない）
- 既存 Sprint 1 / Sprint 2 / Sprint 3 / Sprint 4 のユニットテスト 121 件: **回帰なし**

### QA 詳細リンク

- テスト観点 130 件: `.qa-workspace/sprint-5/test-design/test-points.md`
- バグチケット: `.qa-workspace/sprint-5/tickets/QA-S5-001.md` 〜 `QA-S5-004.md`
- 修正詳細: `.qa-workspace/sprint-5/fixes/QA-S5-001-fix.md`
- QA 最終レポート: `.qa-workspace/sprint-5/report/final-report.md`

---

## シミュレータ動作確認の依頼項目（jun さん向け）

QA はコードレビューとユニットテストで「論理的には動く」ところまで担保しているが、OAuth 認証フロー（外部 Web 認証）と Google Drive への実アップロードはユニットテストでは挙動を完全に再現できない領域のため、Xcode シミュレータでの確認を jun さんにお願いしたい。

| # | 確認項目 | 操作手順 | 期待結果 |
|---|---|---|---|
| 1 | Info.plist の OAuth 設定 | Google Cloud Console で iOS OAuth クライアント ID を発行 → `GPSLogger/Resources/Info.plist` の `GoogleDriveOAuthClientID` の `<string>` に貼り付け → `CFBundleURLSchemes` の reverse client id（`com.googleusercontent.apps.{数字}-{文字}`）に書き換え | アプリ起動時にクラッシュしない。設定 → クラウド同期先で「Google Drive」を選んだときに認証フローが起動可能になる |
| 2 | OAuth 認証成功 | 設定タブ → クラウド同期先 → 「Google Drive」を選択 → ASWebAuthenticationSession のシート起動 → Google アカウントでログイン → 同意画面で許可 | アプリに戻り、認証状態が「認証済」と表示される。Keychain にアクセストークン + リフレッシュトークンが保存される（Keychain Access アプリで `com.junhnam.iOS-GPSlog` のエントリ確認可） |
| 3 | OAuth 認証拒否 | 上記の同意画面で「キャンセル」 or 「拒否」 | 認証状態が変わらず、エラー Alert で「認証がキャンセルされました」等が表示される。アプリがクラッシュしない |
| 4 | 自動同期 ON + 記録停止トリガー | 認証完了後、自動同期 Toggle を ON → 地図画面で記録開始 → 数分間移動（or Simulate Location でルート再生）→ 記録停止 | バックグラウンドで CSV が `GPSログ/{今日}/data.csv` 階層で Drive にアップロードされる。Drive Web UI で確認 |
| 5 | リトライキュー（ネットワーク断時） | シミュレータで機内モード ON にして記録停止 → CSV 出力は成功するが Drive アップロード失敗 → リトライキューに積まれる → 機内モード OFF | ネットワーク回復で `NWPathMonitor` が発火し、`CloudUploadRetryQueue` が再試行 → Drive にアップロードされ、キューから削除される |
| 6 | 5 回失敗時の通知 | Info.plist の OAuth ClientID を意図的に間違えた値にする → 自動同期 ON で 5 回記録停止 | UN（UserNotifications）通知が発火し「Google Drive へのアップロードが 5 回失敗しました」等の通知が表示される |
| 7 | PinRecord.address のカレンダー反映（QA-S4-002 関連） | 滞留ピン作成 → カレンダー同期 ON → カレンダーアプリでイベント詳細を確認 | イベントの場所欄に「placeName → address → 座標」のいずれか（**address が入る場合がある点が Sprint 4 から変わった点**）が文言通りに反映される |

これら 7 項目が確認できれば Sprint 5 のスプリントゴール達成として最終合意取得とさせていただきたい。**項目 1 は jun さん側のオペレーション必須**（Info.plist のプレースホルダー埋め）であり、未実施の状態では項目 2 以降が動かない。

---

## ステークホルダーへの確認事項

1. **Google Cloud Console での iOS OAuth クライアント ID 発行 + Info.plist 反映**（QA-S5-003 / 上記項目 1）
   - 発行手順は Sprint 6 で `.scrum/notes/google-drive-oauth-setup.md` として整備予定
   - Sprint 5 中に jun さん側で値を埋めて push するか、Sprint 6 で gitignore + .example パターンで運用整理するかの方針判断をお願いしたい
2. **Sprint 6 のスコープ確定**（後述「次スプリント方針への接続」参照）
3. **本レビュー文書の合意 + git push 承認**（origin/main から 17 コミット先行）
4. **GitHub Issue クローズ承認**（#35 / #37 / #38 / #39 / #40 / #41 / #42 / #43 = S5-001 / S5-003〜S5-009 想定 8 件。S5-002 = Issue #36 は Sprint 6 へ繰越なので close しない）

---

## 変更されたファイル統計（Sprint 4 完了 `42e1b2c` → HEAD `7a99e9e`）

ハンドオーバー記録によれば 17 コミットが origin/main から先行。Sprint 5 のスコープに伴う主要追加ファイル:

| ファイル | 用途 |
|---|---|
| `GPSLogger/Services/Cloud/CloudStorageProvider.swift` | クラウドストレージプロバイダ共通プロトコル |
| `GPSLogger/Services/Cloud/GoogleDriveSyncService.swift` | Google Drive 軽量実装（Apple 純正のみ） |
| `GPSLogger/Services/Cloud/CloudUploadCoordinator.swift` | 記録停止 → CSV → アップロードの統合経路 |
| `GPSLogger/Services/Cloud/CloudUploadRetryQueue.swift` | リトライキュー + NWPathMonitor + UN 通知 |
| `GPSLogger/Models/PendingUpload.swift` | リトライキュー用 SwiftData @Model |
| `GPSLogger/Features/Settings/CloudStoragePickerView.swift` | プロバイダ選択 UI |
| `GPSLogger/App/RootView.swift` | DI 集約点（QA-S5-001 修正含む） |
| `GPSLoggerTests/RootViewIntegrationTests.swift` | DI 検証テスト + QA-S5-002 修正 |
| `.scrum/process/dev-completion-checklist.md` | Sprint 5 から運用開始の Dev 完了基準 |
| `.scrum/notes/ios26-api-changes.md` | iOS 26 API 変更点（Sprint 4 retro Try で運用継続） |

詳細は `git diff --stat 42e1b2c..7a99e9e` を別途参照（push 承認後にメインセッション側で確認可）。

## コミット履歴（Sprint 5 中の主要 17 件）

```
7a99e9e chore: Sprint 5 board.md を QA 完了状態に更新
4bc7322 chore: Sprint 5 全 8 チケットを Done 化
0f17622 fix: Sprint 5 release blocker - inject CloudUploadCoordinator/RetryQueue in RootView (QA-S5-001/002)
1ae29e9 chore: テスト群の setUp/tearDown を async 版に統一 (S5-009)
3cc209e feat: クラウド保存先選択 UI + 自動同期 ON/OFF 設定 (S5-003, S5-004)
2a75b44 chore: Sprint 5 完了済チケット（S5-001/005/006/007/008）を Done 化
717e90a chore: S5-008 チケットファイルを Done 化
8051930 feat: MapView Coordinator @MainActor 化 (S5-008)
a45a2f3 chore: テストの async-safe ロックと FakeHTTPClient 引数順序
14f4936 feat: 自動アップロード + リトライキュー + 通知 (S5-005/S5-006)
9675c11 fix: 自動アップロード経路の細部調整 (S5-005)
f2cc406 chore: Cloud 系コードを internal 化 + iOS 26 deprecated 解消 + 復旧時バックオフ無視
8c43aaf feat: Google Drive 軽量実装 + OAuth PKCE (S5-001)
d1d1476 feat: PinRecord.address 追加 + addressFromPlaceURL 削除 (S5-007)
a2d915f chore: AppSettings に cloudProviderKind / cloudAutoSyncEnabled 追加
（他 planning / development フェーズ移行のメタコミット 2 件）
```

---

## バッテリー消費懸念への進捗

Sprint 5 の主スコープ（クラウド同期）はバッテリー消費に**大きな影響を与えない設計**を維持できた:

- 自動アップロードはユーザー操作トリガー（記録停止）の単発実行のため、バックグラウンド常時消費の増加要因にならない
- リトライキュー（S5-006）は `NWPathMonitor` でネットワーク回復時のみ動く。アプリがフォアグラウンド or バックグラウンド復帰時のみで、常時動作はしない
- OAuth トークンリフレッシュも記録停止時の単発実行のため影響なし

→ Sprint 3 で確立したバッテリー対策の枠組み（自宅滞在中の完全停止 / SLC 併用 / desiredAccuracy 動的調整 / distanceFilter）から**変化なし**。

未対応（後続スプリント）:
- バックグラウンド復帰時の挙動安定化（Sprint 6）
- App Store 審査向けバッテリー実測（Sprint 6）
- `pausesLocationUpdatesAutomatically` の最終チューニング（Sprint 6）
- MKLocalSearch / SLC の実機検証（Sprint 6 retro Try で継続）

---

## 次スプリント方針への接続（Sprint 6 のスコープ案）

Sprint 5 完了時点で見えている Sprint 6 のスコープ:

### Sprint 5 から繰越（必須）

1. **S5-002（Dropbox SDK 導入 + OAuth 認証）**: Issue #36 sprint-6 ラベル。Apple 純正実装パターン継承で対応可能（公式 SDK 不採用判断は Sprint 5 で確立済）
2. **QA-S5-003（Info.plist プレースホルダー運用整理）**: `GoogleMaps-Info.plist` と同パターンで `GoogleDriveOAuth-Info.plist`（gitignore + .example）化
3. **QA-S5-004（CSV 出力失敗時 retryCount 加算）**: 3 案から方針判断 → 実装

### CLAUDE.md 残機能

4. DB クリア機能（日付指定削除）
5. DB 自動消去（1GB 超で古い順削除）
6. アプリアイコン + ローンチスクリーン
7. App Store 申請メタデータ + プライバシーマニフェスト

### バッテリー / 実機検証

8. バッテリー最適化（精度動的調整 / distanceFilter / 一時停止）
9. バックグラウンド復帰時の挙動安定化
10. MKLocalSearch / SLC の実機検証（Sprint 3 申し送り）

### プロセス改善（retro Try）

11. **DI 経路カバレッジテストの定型化**（Sprint 4 retro Try の継続強化。QA-S5-001 / QA-S5-002 と同型バグの再発防止）
12. **RootView.init の DI 集約リファクタ**（`AppDependencyContainer` のような構造体への分離。任意）

→ Sprint 6 は「リリース準備フェーズ」の色合いが強くなる見込み。Must は #1 / #2 / #4 / #5 / #6 / #7 / #11 を中核に、Should で #3 / #8 / #9 / #10、Could で #12 を組む案を Sprint 6 planning で具体化する。

---

## モデル切替の効果（Sprint 4 → Sprint 5 継続検証）

Sprint 4 から運用開始した `scrum-dev-agent: Sonnet` 化の効果を Sprint 5 でも継続検証:

| 観点 | Sprint 4 | Sprint 5 |
|---|---|---|
| 完了チケット数 / 計画チケット数 | 8 / 8 | 8 / 8（S5-002 は Sprint 6 へ繰越合意済） |
| 追加テスト数 | +42 | +52（QA 修正の +1 含む） |
| Sprint 内コンパイルエラー | 1（hotfix で即解消） | 0 |
| git 競合 | 0 件 | 0 件 |
| **Sprint 内 Critical/High バグ** | **High 1 件**（QA-S4-001） | **Critical 1 + High 1 件**（QA-S5-001/002） |
| Sprint 内修正済 | 1 件 | 2 件 |
| Sonnet サブエージェントの sandbox 制約 | xcodebuild 拒否 → メイン代行で凌ぎ | 同左（jun さん指示で settings.json 変更せず継続） |

**所見**: Sonnet 化の品質低下は依然として観測されない（チケット完遂率 100%・git 競合 0 件・テスト追加数増）。一方で **Sprint 4 と Sprint 5 で連続して Critical / High レベルの統合バグが QA 検出**となっており、これは Sonnet 化の影響というより「Sprint 4 retro Try（DI 経路統合テストの定型化）が Sprint 5 plan で具体ガイドラインに落ちなかった」プロセス側の取りこぼしが原因。Sprint 6 retro Try で「DI 経路カバレッジテストの定型化」を継続強化する（後述 retro.md）。

→ **結論**: Sonnet 化は Sprint 6 以降も継続。意思決定（PO/SM）と観点設計・品質判定（QA Orchestrator）は Opus を維持する戦略を継続する。

---

## 完了基準のチェック

- [x] 全 8 チケット（Must 5 / Should 2 / Could 1）が Done（S5-002 は Sprint 6 へ繰越合意済）
- [x] スプリントゴール検証条件 5 項目すべて静的に確認可能
- [x] フル再ビルド warning 0（S5-008 / S5-009 で Sprint 4 申し送り 2 件解消）
- [x] ユニットテスト pass 100%（173/173）
- [x] Sprint 1 / 2 / 3 / 4 のテスト 121 件の回帰なし
- [x] API キー漏洩スキャン 0 件
- [x] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得・git push 承認 — このレビュー時点で保留中）

---

## ユーザー承認後の手順（コマンドドラフト）

承認をいただいた後、メインセッション（Opus）側で以下を実施予定:

```bash
# 1. ローカル 17 コミット + Sprint 5 review/retro 1 コミット = 計 18 コミットを origin main に push
git push origin main

# 2. GitHub Issues #35 / #37 / #38 / #39 / #40 / #41 / #42 / #43（S5-001 + S5-003〜S5-009 想定）をクローズ
#    Issue #36（S5-002 Dropbox）は Sprint 6 へ繰越のため close しない
gh issue close 35 --comment "Sprint 5 で実装完了"
gh issue close 37 --comment "Sprint 5 で実装完了"
gh issue close 38 --comment "Sprint 5 で実装完了"
gh issue close 39 --comment "Sprint 5 で実装完了"
gh issue close 40 --comment "Sprint 5 で実装完了"
gh issue close 41 --comment "Sprint 5 で実装完了"
gh issue close 42 --comment "Sprint 5 で実装完了"
gh issue close 43 --comment "Sprint 5 で実装完了"

# 3. .scrum/config.md の current_sprint を 6 に、sprint_phase を planning に更新（合意後）

# 4. Sprint 6 planning を開始（Dropbox + リリース準備 + プロセス改善 Try）
```

Issue 番号は実際の GitHub の状態と照合してから実行する。
