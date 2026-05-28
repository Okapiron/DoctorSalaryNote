# 医師給与ノート data_model

## 目的

このファイルは、「医師給与ノート」で扱う主要データの概念モデルを管理する。

実装クラス名や永続化フレームワークの詳細ではなく、アプリとして必要なデータ、関係、制約を定義する。

## 基本方針

- データは端末内に保存する
- 外部サーバーへ給与情報を送信しない
- 金額は日本円の整数として扱う
- 年別集計と年度別集計の両方に対応できる構造にする
- 後続フェーズで添付ファイル、書類管理、CSV出力を追加できる余地を残す

## Entity: Workplace

勤務先を表す。

### Fields

- id
- name
- workplaceType
- memo
- sortOrder
- isArchived
- createdAt
- updatedAt

### workplaceType

- fullTime
- partTime
- nightDuty
- spot
- other

### Notes

給与明細が紐づいている勤務先は、削除よりもアーカイブを優先する。

アーカイブ済み勤務先は過去データの表示に使い、新規入力候補からは除外できるようにする。

## Entity: Payslip

給与明細または収入記録を表す。

### Fields

- id
- workplaceId
- paymentYear
- paymentMonth
- paymentDate
- incomeType
- grossAmount
- netAmount
- deductionAmount
- memo
- createdAt
- updatedAt

### incomeType

- fullTimeSalary
- partTimeSalary
- nightDuty
- dayNightDuty
- spot
- bonus
- other

### Required Fields

- workplaceId
- paymentYear
- paymentMonth
- incomeType
- grossAmount

### Optional Fields

- paymentDate
- netAmount
- deductionAmount
- memo

### Notes

支給年月は集計の基本キーとして扱う。

支払日が未入力の場合も、支給年月によって年別・年度別集計に含める。

## Entity: Document

源泉徴収票、支払調書、雇用契約書などの書類を表す。

このEntityは後続フェーズで実装する想定。

### Fields

- id
- workplaceId
- documentYear
- documentType
- title
- fileAttachmentId
- memo
- createdAt
- updatedAt

### documentType

- payslip
- withholdingSlip
- paymentStatement
- employmentContract
- other

### Notes

書類管理は年別を基本とする。

年度別では管理しない。

## Entity: FileAttachment

端末内に保存された添付ファイルを表す。

このEntityは後続フェーズで実装する想定。

### Fields

- id
- ownerType
- ownerId
- originalFileName
- storedFileName
- mimeType
- fileSize
- createdAt

### ownerType

- payslip
- document

### Notes

ファイル実体は端末内に保存する。

データベースにはファイル参照情報を保存し、ファイル本体を直接保存するかどうかは実装時に判断する。

## Entity: AppSettings

アプリ全体の設定を表す。

このEntityは後続フェーズで実装する想定。

### Fields

- id
- defaultYearMode
- fiscalYearStartMonth
- biometricLockEnabled
- createdAt
- updatedAt

### defaultYearMode

- calendarYear
- fiscalYear

### Notes

日本向けの標準年度は4月開始とする。

将来の拡張として年度開始月を変更できる余地を残す。

## Relationships

### Workplace 1 - N Payslip

1つの勤務先は複数の給与明細を持つ。

給与明細は必ず1つの勤務先に紐づく。

### Workplace 1 - N Document

1つの勤務先は複数の書類を持てる。

勤務先に紐づかない書類を許容するかは、書類管理フェーズで再検討する。

### Payslip 1 - N FileAttachment

1つの給与明細は複数の添付ファイルを持てる。

MVPでは添付なしでも成立する。

### Document 1 - 1 FileAttachment

1つの書類レコードは基本的に1つの添付ファイルを持つ。

複数ファイル対応が必要になった場合は後続で拡張する。

## Aggregation Rules

### Calendar Year

paymentYearが対象年に一致するPayslipを集計する。

対象範囲は1月から12月。

### Fiscal Year

年度開始月は4月とする。

例：2026年度は2026年4月から2027年3月まで。

### Amounts

- grossAmount: 額面合計に使う
- netAmount: 手取り合計に使う
- deductionAmount: 控除合計に使う

netAmountまたはdeductionAmountが未入力の場合、その項目の集計では0または未入力として扱う。

## Validation

- nameは空にしない
- paymentYearは有効な西暦年にする
- paymentMonthは1から12にする
- grossAmountは0以上にする
- netAmountは未入力または0以上にする
- deductionAmountは未入力または0以上にする

## Future Considerations

- CSV出力用の列定義
- OCR結果の一時保存
- バックアップファイルの形式
- 税理士共有用エクスポート
- 複数端末同期を行う場合の同期ID
