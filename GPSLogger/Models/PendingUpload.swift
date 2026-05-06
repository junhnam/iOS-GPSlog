import Foundation
import SwiftData

/// クラウドアップロードのリトライキューを永続化する SwiftData モデル（S5-006）。
///
/// 受け入れ条件:
///   - `(tripRecord.id, retryCount, lastError)` をローカル永続化
///   - SwiftData の専用テーブルとして扱い、TripRecord 本体とリレーションは持たない
///     （モデル境界を細く保つため・Sprint 6 で関係更新するならその時に検討）
///
/// 設計判断:
///   - `tripDate` を `(year-month-day) 0:00` に正規化した Date で保持
///     （TripRecord.date と同じ正規化規約に従い、後で TripRecord と突き合わせ可能）
///   - `providerKind` は `CloudProviderKind.rawValue` を文字列で保持
///     （SwiftData は enum を直接保存できないため）
///   - `lastErrorMessage` は人が読める日本語の説明（CloudStorageError の case 名 + メッセージ）
///   - `lastTriedAt` でバックオフの次回実行時刻を計算する
///
/// iOS 26 SwiftData ノート遵守:
///   - 単一エンティティでリレーション無しなので `@Relationship` 配列の落とし穴は無関係
///   - 既存 DB に PendingUpload テーブルを増やすマイグレーション挙動は SwiftData 自動対応
@Model
final class PendingUpload {
    /// 対象の TripRecord.date と同じ正規化日時。日付主キーで TripRecord と突き合わせる。
    var tripDate: Date

    /// リトライ済み回数（0 から開始）。`retryCount >= maxAttempts` で打ち切り通知。
    var retryCount: Int

    /// 最終リトライ時刻。バックオフ計算に使う。
    var lastTriedAt: Date

    /// 最後に発生したエラーの人が読める表現（ログ・UI 表示用）。
    var lastErrorMessage: String?

    /// クラウドプロバイダ種別（`CloudProviderKind.rawValue`）。
    /// 文字列として保存し、復元時に `CloudProviderKind(rawValue:)` で復号する。
    var providerKindRaw: String

    /// 5 回失敗時の通知が既に送られたか。重複通知防止フラグ。
    var notifiedFinalFailure: Bool

    init(tripDate: Date,
                providerKind: CloudProviderKind,
                retryCount: Int = 0,
                lastTriedAt: Date = Date(),
                lastErrorMessage: String? = nil,
                notifiedFinalFailure: Bool = false) {
        self.tripDate = tripDate
        self.providerKindRaw = providerKind.rawValue
        self.retryCount = retryCount
        self.lastTriedAt = lastTriedAt
        self.lastErrorMessage = lastErrorMessage
        self.notifiedFinalFailure = notifiedFinalFailure
    }

    /// `providerKindRaw` から復元した `CloudProviderKind`。
    /// 不正な rawValue の場合は nil（未知のプロバイダはリトライ対象外として扱う）。
    var providerKind: CloudProviderKind? {
        CloudProviderKind(rawValue: providerKindRaw)
    }
}
