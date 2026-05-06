# iOS 26 API 変更点メモ

最終更新: 2026-05-06（Sprint 4 開始前）
背景: Sprint 3 で `CLGeocoder` の deprecated を Sprint 開始時に把握できず、Sprint 末で warning が顕在化した（QA-S3-002）。同種の事故を Sprint 4 以降で再発させないため、iOS 26 で deprecated になった API・推奨置換を集約する。本ノートは Sprint 3 retro Try「iOS 26 の API 変更点を `.scrum/notes/ios26-api-changes.md` に集約」を受けて作成。

新規 Swift ファイル追加時 / 外部 API を使う実装着手前に **必ず本ノートを参照**すること。

---

## 1. `CLGeocoder` → `MKReverseGeocodingRequest`

### 状況

- iOS 26 で `CLGeocoder` 全体が deprecated。`reverseGeocodeLocation(_:completionHandler:)` および `async` 版も対象。
- `cancelGeocode()` も同様。
- 警告は `warning: 'CLGeocoder' was deprecated in iOS 26.0: Use MapKit`。

### 推奨置換

- 単発の逆ジオコーディング: `MKReverseGeocodingRequest`（iOS 26 新 API、MapKit）
- 構造化された住所が欲しい場合: `MKMapItem.placemark` の `CLPlacemark` を引き続き利用可（`MKMapItem` 自体は deprecated ではない）
- キャンセルは `Task` の `cancel()` で代替（`MKReverseGeocodingRequest` の async API は Task キャンセルで中断される）

### Sprint 4 での対応

- **S4-001** で `HomeRegistrationView.swift` と `PlaceLookupService.swift`（`AppleGeocoder`）を移行。
- ステータス: **対応済（2026-05-06 / Sprint 4 / Dev-2）**
  - `AppleGeocoder.reverseGeocode(location:)` を `MKReverseGeocodingRequest(location:).mapItems` ベースに置換
  - `HomeRegistrationView.triggerReverseGeocode` を `Task` + `MKReverseGeocodingRequest(location:preferredLocale:)` ベースに置換
  - `CLGeocoder.cancelGeocode()` は `Task.cancel()` で代替
  - `MKMapItem.placemark`（CLPlacemark）を `PlacemarkAddressFormatter.format` に通す既存変換層を再利用

---

## 2. EventKit 権限 API（参考: 既知だが Sprint 4 で初導入のため記録）

### 状況

- iOS 17 で `requestAccess(to: .event)` が deprecated。iOS 26 でも引き続き未推奨。
- `requestFullAccessToEvents(completion:)` または async 版 `requestFullAccessToEvents()` が推奨。

### Info.plist キー

- 旧: `NSCalendarsUsageDescription`
- 新: `NSCalendarsFullAccessUsageDescription`（iOS 17+）+ 必要に応じて `NSCalendarsWriteOnlyAccessUsageDescription`

### Sprint 4 での対応

- **S4-002** で `requestFullAccessIfNeeded()` を `EKEventStore.requestFullAccessToEvents` で実装。
- `Info.plist` に `NSCalendarsFullAccessUsageDescription` を追加。

---

## 3. SwiftUI `.fileExporter` / `.fileImporter`（参考）

### 状況

- iOS 16+ で `.fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)` が標準提供。
- iOS 17+ で onCompletion の Result 型が `Result<URL, Error>` に統一され、複数ファイル版も追加。
- iOS 26 では特に変更なしだが、`.fileExporter` を使うと `UIDocumentPickerViewController` の直接ラップは不要になる。

### Sprint 4 での対応

- **S4-006** で `.fileExporter` を第一候補として実装。`FileDocument` プロトコル準拠の薄いラッパー（`CSVExportDocument`）を作成。

---

## 4. CLLocationManager `requestWhenInUseAuthorization()`（変更なし）

iOS 26 でも引き続き利用可能。`requestAlwaysAuthorization()` も同様。バックグラウンド位置情報の権限フローは Sprint 1 で確立済の仕組みをそのまま継続。

---

## 5. `MKLocalSearch`（変更なし）

iOS 26 でも引き続き利用可能。Sprint 3 で導入した `Services/Place/PlaceLookupService.swift` の `AppleLocalSearcher` 実装は変更不要。

---

## 6. SwiftData / `#Predicate`（参考: ios26-swiftdata.md と相互参照）

iOS 26 + Swift 6 の SwiftData の挙動は `.scrum/notes/ios26-swiftdata.md` に集約済み。新規モデル追加時はそちらのチェックリストを優先する。本ノートは「外部 API の deprecation」を中心に扱う分業。

---

## チェックリスト（新規 Swift ファイル追加 / 外部 API 利用前）

- [ ] 利用予定の外部 API が iOS 26 で deprecated になっていないか Apple ドキュメントで確認した
- [ ] 本ノートに該当エントリがある場合、置換方針に従って実装する
- [ ] `xcodebuild -clean -build` でフル再コンパイルし warning 0 を確認する
- [ ] 新規エントリを発見した場合、本ノートに追記する（更新日時 + Sprint 番号 + 対応予定 / 対応済を記載）

---

## 改訂履歴

| 日付 | 内容 |
|---|---|
| 2026-05-06 | 初版（Sprint 3 retro Try / Sprint 4 開始前）。CLGeocoder / EventKit / fileExporter / CLLocationManager / MKLocalSearch / SwiftData の現状を整理 |
