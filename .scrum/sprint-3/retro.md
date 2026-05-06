# Sprint 3 Retrospective

開催日: 2026-05-06
参加: PO/SM / Dev-1 / Dev-2 / QA（Single-Agent モードで Agent A が代行）

---

## Keep（続けること）

- **Sprint 2 の retro Try をほぼ全て実装に取り込めた**。retro #4「`restoreTodayTrip` のエラー昇格」は S3-008 として、retro Try「iOS 26 SwiftData の特殊事情をプロジェクト内に記録」は S3-009 として、Sprint 6 候補だった Significant Location Changes は S3-006 として先取り実装した。「retro が実際の planning に反映される」サイクルが回った。
- **CLAUDE.md / README から `.scrum/notes/ios26-swiftdata.md` への相互リンク**を貼ったことで、新規モデル追加時の落とし穴回避ノートが「探さないと見つからないドキュメント」ではなく「コーディング前に必ず通る場所」になった。Sprint 3 では新規モデル（AppSettings / HomeLocation）追加時に SwiftData 落とし穴の再発ゼロ。
- **DI 構造の徹底**（HomeDetector / PlaceLookupService / LocationProviderProtocol）。各機能を純粋関数 or プロトコル抽象で組み立てたことで、ユニットテストが 35 件追加できた（Sprint 2 末 44 → Sprint 3 末 79）。CLLocationManager や MKLocalSearch のように実機 / OS 依存の API も、テスト側でフェイクを差し込めて高速に検証できた。
- **API キー漏洩 0 件を継続**。`AIza` で grep 0、`GoogleMaps-Info.plist` 実体は `.gitignore` 経由で追跡外。Sprint 1 で築いた仕組みが Sprint 3 でも崩れていない。
- **Swift 6 strict concurrency 対応の継続**。Sprint 1〜2 で確立した `@MainActor` クラス + `nonisolated` delegate + `Task @MainActor` の戻りパターンを Sprint 3 全体（AppSettings / SettingsView / HomeRegistrationView / HomeDetector / PlaceLookupService / LocationService 拡張）でも徹底。新たに導入した `LocationProviderProtocol` も `Sendable` を意識した抽象化で、warning 0 を維持。
- **Dev-1 / Dev-2 の作業ファイル分割が引き続き機能**。`Models/` `Features/Settings/` `Features/Map/MapView` 周辺を Dev-1、`Services/Home/` `Services/Place/` `Services/Location/LocationService.swift` を Dev-2、共有ファイル（`MapView.swift` / `RootView.swift`）は事前合意した範囲だけを触る運用で、Sprint 3 でも git 競合 0 件。
- **QA で「組み立てバグ」を捕まえられた**（QA-S3-001）。ユニットテストでは個々の機能が DI 経由で正しく動くことしか検証できなかったが、QA フェーズの統合経路の静的レビューで「MapView 内 LocationService 初期化時に AppSettings / placeProvider が nil のまま」を発見できた。**ユニットテスト pass = プロダクトが動く、ではない**ことを再認識した。回帰防止に RootViewIntegrationTests を追加。

## Problem（問題だったこと）

- **Critical バグ（QA-S3-001）が QA フェーズで発見された**。スプリントゴール検証条件 1 / 2 / 4 が実機経路で機能しない統合バグで、もし QA フェーズがなかったら jun さんがシミュレータで動作確認した瞬間に発覚していた。Dev フェーズ完了時点で「ユニットテスト 100% = OK」とサインしていたら、Sprint 3 の品質が大きく落ちていた。**統合経路の静的レビュー観点を Dev フェーズの完了基準にも組み込むべき**だった。
- **iOS 26 で `CLGeocoder` が deprecated になっていることを Sprint 3 開始時に把握できていなかった**（QA-S3-002）。S3-002（HomeRegistrationView）と S3-007（PlaceLookupService）の両方で CLGeocoder を使ってしまい、Sprint 3 末で warning が顕在化。事前に「iOS 26 の API 変更点」をプロジェクトノートに集約しておけば回避できた可能性がある。
- **plan.md のユニットテスト計画（22 件）に対して実装は 35 件と大幅超過**。観点漏れを潰すためには良い結果だが、計画見積もりの精度は低かった。Dev-1 / Dev-2 とも「テストしないと不安だから書く」という主観判断だった。テスト観点の必要十分を planning 段階で整理する仕組みが弱い。
- **Single-Agent QA モードの継続**。Sprint 3 でも Task ツールが使えず、Agent A が B（テスト実装）/ C・D・E（テスト実行）/ F（バグ修正）を兼任。60 観点を直列実行する負荷は Sprint 1 / Sprint 2 と変わらず、本来の並列実行のメリットを得られなかった。
- **ローカル 13 コミットが未 push の状態**。Sprint 1 / Sprint 2 と同じく、Sprint 中にこまめに push する運用にはまだ至れていない。
- **シミュレータでの実機相当の動作確認が未完了**のまま Sprint レビューに入っている。Sprint 2 では jun さんが Freeway Drive を流して総移動距離 3.74 km 復元を目視確認できたが、Sprint 3 は自宅判定 / SLC / トリガーモード / 復元エラー通知のいずれも「Simulate Location でシナリオを組む必要がある」ため、実機相当の確認が後ろ倒しになっている。

## Try（次に試すこと）

- **Dev フェーズ完了基準に「統合経路の静的レビュー」を追加**。ユニットテスト 100% に加えて、「RootView → MapView → LocationService の DI 経路で全プロパティが期待通り注入されているか」を Dev-1 / Dev-2 が完了報告時にチェックする。これで QA-S3-001 のような統合バグを Dev フェーズで捕まえられるようにする。
- **iOS 26 の API 変更点を `.scrum/notes/ios26-api-changes.md` に集約**。`CLGeocoder` deprecated を起点に、Sprint 4 開始前に既知の deprecated API 一覧を作る。新規 Swift ファイル追加時に必ず参照する。
- **plan.md のテスト観点を「最低数」ではなく「観点リスト」で書く**。Sprint 4 から、各チケットに「カバーすべき観点（境界 / エラー / 後方互換 / 統合）」を箇条書きで明記し、テスト数の上振れを許容しつつ観点漏れを防ぐ。
- **Sprint 4 開始時に Task ツール可否を再確認**。Sprint 1 / 2 / 3 retro でも Try に挙げているが継続。ダメなら Single-Agent 前提で観点を絞り込み、QA 観点を 60 → 40 程度に圧縮する代替案を検討する。
- **Dev フェーズ完了直後に push 候補をユーザーに提示する運用**を Sprint 4 でも継続。Sprint 3 では Sprint 完了時の 1 回提示になったが、Sprint 4 では Dev フェーズ終了時にも提示する。
- **シミュレータの Simulate Location シナリオを `.scrum/notes/simulator-scenarios.md` に整理**。Sprint 3 で必要な「自宅座標固定 / 自宅 → Freeway Drive 切替 / 短距離往復」などの Simulate Location 設定手順を jun さんが追体験できるように手順化する。Sprint 4 のレビュー時にすぐ動作確認できるようにする。
- **GitHub Issue クローズの一括コマンドをレビュー文書末尾に必ず添付**は Sprint 1 / 2 / 3 でできているので継続。

---

## メトリクス

| 指標 | Sprint 3 | Sprint 2 比較 |
|---|---|---|
| 計画チケット数 | 9 | +1（Sprint 2 は 8） |
| 完了チケット数 | 9 | +1 |
| 完了率 | 100% | 同等 |
| 持ち越しチケット | 0 | 同等 |
| Sprint 中コミット数 | 13 | -1（Sprint 2 は 14） |
| 変更ファイル数 | 40 | -7 |
| 追加行数 / 削除行数 | +3309 / -73 | +569 / -7（Sprint 2 は +2740 / -80） |
| ユニットテスト数 | 79 | +35（Sprint 2 末は 44） |
| ユニットテスト pass 率 | 100% | 同等 |
| ビルド warning / error | 0 / 0（フル再ビルド時 deprecated 1） | -（Sprint 2 は 0/0） |
| バグチケット起票数 | 2（QA-S3-001 / QA-S3-002） | -1（Sprint 2 は 3） |
| 残存バグ | 0 | 同等 |
| QA 観点充足 | 60 / 60 | -15（Sprint 2 は 75） |
| **Critical バグ Sprint 内修正** | **1（QA-S3-001）** | **+1（Sprint 2 は 0）** |

Critical バグが 1 件出たのは Sprint 1 / 2 にはなかった事象。Try の「Dev フェーズ完了基準に統合経路レビューを追加」で次スプリント以降に再発を防ぐ。

## アクションアイテム（Sprint 4 開始前までに）

- [ ] jun さん: シミュレータで Sprint 3 review.md「シミュレータ動作確認の依頼項目」5 項目（うち 4 項目は必須、1 項目は任意）の確認
- [ ] PO/SM: ユーザー承認後、ローカル 13 コミットを `origin main` に push
- [ ] PO/SM: ユーザー承認後、GitHub Issues #18〜#26（S3-001 〜 S3-009 想定）をクローズ（コメント: "Sprint 3 で実装完了"）
- [ ] PO/SM: `.scrum/config.md` の `current_sprint` を 4 に、`sprint_phase` を `planning` に更新（合意後）
- [ ] PO/SM: Sprint 4（カレンダー同期 + CSV エクスポート + QA-S3-002 CLGeocoder 移行）の planning を実施
- [ ] PO/SM: Sprint 4 planning 時に申し送り 7 件のうち取り込むものを決定（特に #1 CLGeocoder 移行は優先度判断必須）
- [ ] PO/SM: `.scrum/notes/ios26-api-changes.md` を Sprint 4 開始前に作成
- [ ] PO/SM: `.scrum/notes/simulator-scenarios.md` を Sprint 4 開始前に作成
