# 医師給与ノート TestFlightチェックリスト

## 目的

TestFlight配布前に、Xcode設定、Privacy、App Store Connectで必要になる情報、実機確認項目を整理する。

## Xcodeプロジェクト設定

- Bundle Identifier: `com.hiroki.DoctorSalaryNote`
- Display Name: `医師給与ノート`
- Deployment Target: iOS 17.0
- Version: 1.0
- Build Number: 1
- Signing: Automatic。Team ID `9C3F9RM96M` を設定済み
- Launch Screen: Xcodeの生成設定あり
- App Icon: Asset Catalogに設定済み
- Face ID利用説明: `給与情報を保護するため、Face IDを使用します。`

## Privacy / 権限

- Face ID / Touch ID: LocalAuthenticationを使用。Face ID説明文は設定済み
- PhotosPicker: ユーザーが選択した画像のみを取り込む実装。直接フォトライブラリ全体を読む実装ではない
- fileImporter: ユーザーが選択したPDFのみを取り込む実装
- 外部通信: URLSession、CloudKit、サーバー送信、クラウド同期の実装なし
- CSV共有: ユーザー操作によるShareLinkのみ

## App Store Connectで準備するもの

- Privacy Policy URL: `https://okapiron.github.io/DoctorSalaryNote/privacy_policy.html`
- Support URL: `https://okapiron.github.io/DoctorSalaryNote/support.html`
- App Store説明文
- スクリーンショット
- App Icon: 設定済み
- データ収集有無の回答
- 暗号化・輸出コンプライアンスの確認

## 実機 / Simulator確認項目

- 初回起動
- 勤務先登録、編集、無効化、削除禁止
- 給与明細登録、編集、削除
- ホーム集計への反映
- 分析画面への反映
- 書類追加、編集、削除
- PDF / 画像プレビュー
- CSV出力と共有
- Face ID / Touch IDロック
- 全データ削除

## Archive前の要対応

- Apple DeveloperアカウントをXcodeに追加し、Provisioning Profileを作成できる状態にする
- App Store ConnectでBundle Identifier `com.hiroki.DoctorSalaryNote` のアプリ登録を行う
- Apple Distribution証明書またはXcodeの自動署名で配布用署名を準備する
- 実機でFace ID / Touch ID、ファイル取込、共有を確認する
- App Store ConnectのPrivacy回答を確定する

## 2026-05-29 確認結果

- Debug Simulatorビルド成功
- Release Simulatorビルド成功
- 署名なしのiOS Archive成功
- 署名ありArchiveは、Xcodeアカウント未設定およびProvisioning Profile未作成のため未完了
