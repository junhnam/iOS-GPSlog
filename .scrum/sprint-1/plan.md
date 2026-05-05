# Sprint 1 Plan

## スプリント情報
- 期間: 1イテレーション（プランニング日: 2026-05-05）
- 体制: Dev x2 + Designer x1
- 対象リポジトリ: junhnam/iOS-GPSlog

## スプリントゴール
**iOS シミュレータ上で、現在地を地図に表示し、移動経路を青いラインで描画できる状態を作る。**

検証方法: シミュレータで `Features > Location > Freeway Drive` を実行し、Google Maps 上に経路が継続して描画されること。

---

## 含まれるチケット（9 件）

### Dev-1（プロジェクト基盤）
| ID | タイトル | 見積 |
|---|---|---|
| S1-001 | Xcode プロジェクト雛形作成 | M |
| S1-002 | SPM + Google Maps SDK 導入 | M |
| S1-003 | Info.plist の権限設定 | S |
| S1-004 | アプリエントリポイント + ナビゲーション骨格 | S |
| S1-009 | README にビルド・実行手順を追記 | S |

### Dev-2（位置情報・地図機能）
| ID | タイトル | 見積 |
|---|---|---|
| S1-005 | LocationManager サービス実装 | M |
| S1-006 | Google Maps ビュー（現在地表示） | M |
| S1-007 | 移動経路ライン描画 | M |

### Designer
| ID | タイトル | 見積 |
|---|---|---|
| S1-008 | メイン画面 UI モック作成 | M |

---

## 担当割り当ての考え方
- **Dev-1 はプロジェクト基盤（プロジェクト雛形・SDK 導入・権限設定・ナビ骨格・README）に集中**。これらはほぼ単一ファイルか設定ファイルへの変更で、Dev-2 とは触る場所がほとんど被らない。
- **Dev-2 は位置情報サービスと地図描画**を担当。ファイルは `Services/Location/` と `Features/Map/` に集約され、Dev-1 とは衝突しない。
- **Designer はモックを 1 ファイル**で完結させ、Dev のファイル群とは独立した `Design/Mockups/` 配下に置く。
- 依存関係: Dev-1 の S1-001/S1-002/S1-003 が先に完了していないと Dev-2 のチケットが着手できない箇所がある。Dev-1 はこの 3 件を最優先で進める。

## ファイル分割マップ（衝突回避）

```
GPSLogger/
├── App/                       ← Dev-1
│   ├── GPSLoggerApp.swift
│   └── RootView.swift
├── Features/
│   ├── Map/                   ← Dev-2
│   │   └── MapView.swift
│   ├── History/               ← Dev-1（プレースホルダのみ）
│   │   └── HistoryPlaceholderView.swift
│   └── Settings/              ← Dev-1（プレースホルダのみ）
│       └── SettingsPlaceholderView.swift
├── Services/
│   └── Location/              ← Dev-2
│       └── LocationService.swift
├── Design/
│   └── Mockups/               ← Designer
│       └── MainScreenMock.swift
├── Resources/
│   ├── Info.plist             ← Dev-1
│   └── GoogleMaps-Info.plist  ← Dev-1
└── README.md                  ← Dev-1
```

## ブランチ運用
- ベース: `main`
- スプリント用: `feature/sprint-1-{ticket-id}`（例: `feature/sprint-1-S1-001`）
- 各チケット完了時に main へマージ（または PR）

## 完了条件（Definition of Done）
1. 全 9 チケットの受け入れ条件にチェックが入っている
2. Xcode でビルドが通る（警告は許容）
3. シミュレータで起動 → 現在地表示 → Freeway Drive で経路描画ができる
4. README の手順通りに jun さん本人が再現できる
5. `.scrum/sprint-1/board.md` の全チケットが Done 列にある

## 想定リスクと対応
| リスク | 対応 |
|---|---|
| Google Maps API キーが未取得でビルドが落ちる | キー未設定時はログ警告のみで起動継続するように S1-002 で対策 |
| SwiftData テンプレートが iOS 26 で挙動変更されている | 雛形作成時に問題があれば SwiftData なし版に切替（Sprint 2 で導入） |
| シミュレータでの位置情報変化が拾えない | `desiredAccuracy = kCLLocationAccuracyBest` + Freeway Drive で検証、ダメなら実機 |

## 補足（PO/SM 判断事項）
- アプリ名は `GPSLogger`（仮）で進めます。リリース前に jun さんと相談して最終決定。
- Bundle ID は `com.junhnam.gpslogger`（仮）。
- Google Maps API キーは jun さん側で発行いただく前提。Sprint 1 中の動作確認には必要なので、早めの取得を推奨。
