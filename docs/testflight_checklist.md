# 医師給与ノート TestFlightチェックリスト

## 目的

TestFlight配布前に、Xcode設定、Privacy、App Store Connectで必要になる情報、実機確認項目を整理する。

## Xcodeプロジェクト設定

- Bundle Identifier: `com.hiroki.DoctorSalaryNote`
- Display Name: `医師給与ノート`
- Deployment Target: iOS 17.0
- Version: 1.1
- Build Number: 34
- Signing: Automatic。Team ID `2WG3Z522JL` を設定済み
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
- ホームの直近6か月が現在月基準で、未登録月の手取り線が結ばれないこと
- OCR中は保存できず、既入力フォームの再取込前に上書き確認が出ること
- OCR候補へ別の勤務先の固有控除項目が混ざらないこと
- 同義の控除項目が重複せず、重複名では保存できないこと
- 書類、給与明細、全データ削除で実ファイルが整理され、失敗時に部分失敗が表示されること
- 支払調書が「なし（任意）」として警告扱いされないこと

## 自動テスト

以下のコマンドで、金額整合性、控除名正規化、CSV、ファイル削除、SwiftDataモデル保存のテストを実行する。

```sh
xcodebuild -project DoctorSalaryNote.xcodeproj -scheme DoctorSalaryNote -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath /private/tmp/DoctorSalaryNoteTestDerivedData CODE_SIGNING_ALLOWED=NO test
```

## アップデート時のデータ移行

- 公開版相当のアプリで勤務先、給与明細、添付書類を保存する
- アプリを削除せず、配布予定ビルドを上書きインストールする
- 既存の勤務先、給与明細、添付書類と実ファイルが残ることを確認する
- 新しく追加したSwiftDataモデルを作成、編集、削除できることを確認する
- データモデルを変更したリリースでは毎回実施する

### 2026-08-06 実施結果

- 公開版相当の `main` で勤務先「移行確認病院」と給与明細 765,432円を保存
- アプリを削除せずVersion 1.1相当の現行ビルドを上書き
- 既存の勤務先、給与明細、メモが保持された
- `EmployerDeductionTemplate` と `PayRecordDeductionItem` の新規ストアが追加された

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
