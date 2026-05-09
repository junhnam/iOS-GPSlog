import Foundation
import UIKit

/// ピン詳細シートに渡す表示用データモデル（S6-011）。
///
/// `RestoredPin` から生成する純粋な値型。UI ロジックを一切持たず、
/// 文字列整形・URL 生成のみを担当する。テスト容易性のため View から切り離す。
struct PinDetailModel: Equatable, Sendable {

    // MARK: - 表示用プロパティ

    /// 店舗名。nil = 取得失敗（表示側でフォールバック文言を出す）。
    let placeName: String?

    /// 住所文字列。nil = 取得失敗（非表示）。
    let address: String?

    /// 滞留開始時刻（ローカル時刻の「YYYY/MM/dd HH:mm」書式）。
    let stayedFromText: String

    /// 滞留時間（「約 N 分」または「約 N 時間 M 分」）。
    let stayedDurationText: String

    /// 緯度経度（小数点 5 桁 / 開発確認用）。
    let coordinateText: String

    /// 生の緯度（外部マップ URL 生成に使用）。
    let latitude: Double

    /// 生の経度（外部マップ URL 生成に使用）。
    let longitude: Double

    // MARK: - ファクトリ

    /// `RestoredPin` から `PinDetailModel` を生成する。
    init(pin: RestoredPin) {
        self.placeName = pin.placeName
        self.address = pin.address
        self.latitude = pin.latitude
        self.longitude = pin.longitude

        // 滞留開始時刻フォーマット
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        self.stayedFromText = formatter.string(from: pin.stayedFrom)

        // 滞留時間フォーマット（1 時間超えは「約 N 時間 M 分」）
        let totalMinutes = max(1, Int(pin.stayedDurationSeconds / 60))
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                self.stayedDurationText = "約 \(hours) 時間"
            } else {
                self.stayedDurationText = "約 \(hours) 時間 \(minutes) 分"
            }
        } else {
            self.stayedDurationText = "約 \(totalMinutes) 分"
        }

        // 座標表示（小数点 5 桁）
        self.coordinateText = String(format: "%.5f, %.5f", pin.latitude, pin.longitude)
    }

    // MARK: - URL 生成

    /// Apple Maps を開く URL。
    /// `maps.apple.com` ドメインは iOS が自動的に Maps.app へルーティングする。
    var appleMapsURL: URL {
        var components = URLComponents(string: "http://maps.apple.com/")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")
        ]
        if let name = placeName, !name.isEmpty {
            items.append(URLQueryItem(name: "q", value: name))
        } else {
            items.append(URLQueryItem(name: "q", value: "\(latitude),\(longitude)"))
        }
        components.queryItems = items
        return components.url!
    }

    /// Google Maps を開く URL。
    /// - `canOpenURL` で comgooglemaps:// が利用可能な場合はネイティブアプリ起動。
    /// - 利用不可の場合は Web フォールバック（Safari で google.com/maps を開く）。
    ///
    /// - Parameter canOpenGoogleMaps: `UIApplication.shared.canOpenURL(comgooglemapsURL)` の結果。
    ///   テストでモック注入できるよう引数として受け取る。
    func googleMapsURL(canOpenGoogleMaps: Bool) -> URL {
        if canOpenGoogleMaps {
            var components = URLComponents(string: "comgooglemaps://")!
            components.queryItems = [
                URLQueryItem(name: "q", value: "\(latitude),\(longitude)")
            ]
            if let url = components.url {
                return url
            }
        }
        // Web フォールバック
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(latitude),\(longitude)")
        ]
        return components.url!
    }

    /// placeName も address も空の場合 true（「取得失敗」注記表示に使う）。
    var hasNoPlaceInfo: Bool {
        let nameEmpty = placeName?.isEmpty ?? true
        let addressEmpty = address?.isEmpty ?? true
        return nameEmpty && addressEmpty
    }
}
