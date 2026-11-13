# 検数ログ（CountLog）

数量検査のエビデンスを残すための iOS アプリ。

数量検査の目的は「数えること」ではなく「エビデンスを残すこと」。広げて一層に並べた品物（と出荷伝票・識別札）を撮影し、端末上のモデルが個数の下書きを出し、人がマーカーを確認・修正して確定する。元写真・マーカー付き写真・個数の記録は1セットで端末に保存され、WebDAV サーバーへ自動アップロードされる。

## 機能

- 対象を1つ囲んで数える「特徴マッチング計数」（Vision の特徴プリント照合）と、囲まずに明暗で数える「自動（明暗）」の2方式
- 番号付きマーカーのタップ追加・削除による修正、感度スライダー＋再計算
- 記録の自動保存（元写真 / マーカー付き写真 / record.json）と WebDAV 自動アップロード（未送信は起動時に再送）
- 撮影プロトコルを提示する「ガイド」タブ、履歴の閲覧、WebDAV 接続設定・接続テスト

詳しい使い方は [docs/manual.md](docs/manual.md) を参照。

## ビルド

前提：XcodeGen（`brew install xcodegen`）

```sh
xcodegen generate
open CountLog.xcodeproj
```

GitHub Actions では `.github/workflows/build.yml` が署名なし IPA をビルドして artifact にアップロードする（workflow_dispatch、または main への push 時）。成果物 `CountLog-unsigned.ipa` は Feather などで再署名してインストールする想定。

## 構成

- `App/CountLogApp.swift` — エントリポイント（撮影 / 履歴 / ガイド / 設定 の4タブ）
- `App/CountFlowView.swift` — 撮影→囲む→数える→確認・修正→確定 のフロー
- `App/CounterEngine.swift` — 端末上の計数エンジン（特徴マッチング / 明暗連結成分）
- `App/RecordStore.swift` — 記録の保存（Application Support/CountLog/records）
- `App/WebDAVUploader.swift` — WebDAV アップロード、接続設定、Keychain
- `App/HistoryView.swift` / `App/GuideView.swift` / `App/SettingsView.swift`

- 対象 OS：iOS 17.0 以上 / Swift 5.9 / サードパーティ依存なし
- bundle id：`jp.onejpkey.countlog`
