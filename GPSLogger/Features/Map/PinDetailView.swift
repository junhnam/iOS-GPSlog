import SwiftUI
import UIKit

/// 滞留ピンの詳細を表示するモーダルシート（S6-011）。
///
/// 表示内容:
///   - 店舗名（placeName あり: そのまま表示 / なし: フォールバック文言）
///   - 住所（あれば表示）
///   - 滞留時間 / 滞留開始時刻 / 座標
///   - Apple Maps 起動ボタン
///   - Google Maps 起動ボタン（インストール判定あり）
///   - 閉じるボタン
///
/// 設計方針:
///   - presentation layer のみ。ロジックは `PinDetailModel` が持つ。
///   - `PinDetailModel` を props として受け取る純粋 View。
@MainActor
struct PinDetailView: View {
    let model: PinDetailModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 店舗情報
                Section {
                    if model.hasNoPlaceInfo {
                        // placeName も address も空の場合の注記
                        Label {
                            Text("お店情報の取得に失敗しました。座標のみ表示しています。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        .accessibilityIdentifier("pin_detail_no_place_info")
                    } else {
                        // 店舗名
                        if let name = model.placeName, !name.isEmpty {
                            LabeledContent("店舗名", value: name)
                                .accessibilityIdentifier("pin_detail_place_name")
                        } else {
                            LabeledContent("店舗名") {
                                Text("お店情報を取得中または取得失敗")
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            .accessibilityIdentifier("pin_detail_place_name_fallback")
                        }
                        // 住所（あれば表示）
                        if let address = model.address, !address.isEmpty {
                            LabeledContent("住所", value: address)
                                .accessibilityIdentifier("pin_detail_address")
                        }
                    }
                } header: {
                    Text("店舗情報")
                }

                // MARK: - 滞留情報
                Section {
                    LabeledContent("滞留開始", value: model.stayedFromText)
                        .accessibilityIdentifier("pin_detail_stayed_from")
                    LabeledContent("滞留時間", value: model.stayedDurationText)
                        .accessibilityIdentifier("pin_detail_duration")
                    LabeledContent("座標", value: model.coordinateText)
                        .font(.footnote.monospaced())
                        .accessibilityIdentifier("pin_detail_coordinate")
                } header: {
                    Text("滞留情報")
                }

                // MARK: - 外部マップ起動
                Section {
                    Button {
                        openAppleMaps()
                    } label: {
                        Label("Apple Maps で開く", systemImage: "map")
                    }
                    .accessibilityIdentifier("pin_detail_open_apple_maps")

                    Button {
                        openGoogleMaps()
                    } label: {
                        Label("Google Maps で開く", systemImage: "globe")
                    }
                    .accessibilityIdentifier("pin_detail_open_google_maps")
                } header: {
                    Text("外部マップ")
                }
            }
            .navigationTitle("滞留ピン詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        onDismiss()
                    }
                    .accessibilityIdentifier("pin_detail_close_button")
                }
            }
        }
    }

    // MARK: - Private

    private func openAppleMaps() {
        let url = model.appleMapsURL
        UIApplication.shared.open(url)
    }

    private func openGoogleMaps() {
        guard let schemeURL = URL(string: "comgooglemaps://") else { return }
        let canOpen = UIApplication.shared.canOpenURL(schemeURL)
        let url = model.googleMapsURL(canOpenGoogleMaps: canOpen)
        UIApplication.shared.open(url)
    }
}

#if DEBUG
#Preview {
    let pin = RestoredPin(
        latitude: 35.65916,
        longitude: 139.70106,
        stayedFrom: Date(timeIntervalSince1970: 1_746_700_000),
        stayedDurationSeconds: 1380,
        placeName: "渋谷スクランブルスクエア",
        address: "東京都 渋谷区 渋谷 2-24-12"
    )
    let model = PinDetailModel(pin: pin)
    PinDetailView(model: model, onDismiss: {})
}
#endif
