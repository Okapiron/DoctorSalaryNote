# Dr's Salary data_model

## 目的

このファイルは、「Dr's Salary」で扱う主要データの概念モデルを管理する。

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
- bonus
- partTimeSalary
- spot
- other

旧バージョンで保存されたnightDuty、dayNightDutyは互換用に読み取り、アプリ上はpartTimeSalary相当の外勤として扱う。

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

netAmountは任意入力とする。未入力の場合は、手取り集計では0として加算するが、グラフや詳細表示では未入力であることが分かるように扱う。

deductionAmountが未入力でnetAmountが入力されている場合は、grossAmount - netAmountを控除合計の補完値として使う。deductionAmountとnetAmountの両方が未入力の場合は、控除合計も未入力相当として扱う。

grossAmount、netAmount、deductionAmountは、給与明細の基本3項目として常に扱う。ただし永続化上の必須項目はgrossAmountのみとし、netAmountとdeductionAmountは未入力状態と0円を区別する。

## Entity: WorkplaceDeductionDefinition

勤務先ごとの控除内訳項目の表示設定を表す。

### Fields

- id
- workplaceId
- displayName
- ocrAliases
- sortOrder
- isActive
- createdAt
- updatedAt

### Notes

控除項目には大分類を必須としない。給与明細に記載される「短期掛金」「厚生年金」「雇用保険」などの表示名を、その勤務先の項目名としてそのまま保存する。

所得税と住民税は給与明細の共通固定項目として扱い、勤務先別設定には含めない。

ocrAliasesは、同じ項目が帳票によって異なる表記になる場合に、OCRで同義語として探すために使う。

勤務先ごとに不要な項目を非表示にできる。

勤務先ごとに任意の項目を追加、名称変更、並べ替えできる。

項目を非表示または名称変更しても、過去の給与明細に保存された値と表示名は変更しない。

## Entity: PayslipDeductionItem

給与明細ごとの控除内訳を表す。

### Fields

- id
- payslipId
- deductionDefinitionId
- displayNameSnapshot
- amount
- inputSource
- sortOrder
- createdAt
- updatedAt

### inputSource

- manual
- ocr

### Notes

displayNameSnapshotは、勤務先側の項目名が後から変更・非表示になっても、保存時の給与明細表示を維持するために持つ。

amountは未入力の項目をレコードなし、明示的な0円をamount = 0として区別する。

OCRの確からしさは保存前の候補確認に使い、保存後の控除項目には表示しない。

控除合計が入力されている場合、所得税、住民税、勤務先固有項目を引いた残額を「その他（推定）」として扱う。残額が負になる場合は自動補正せず、入力内容の確認を促す。

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

テーマカラーは給与や書類のドメインデータではなく表示設定であるため、SwiftDataのスキーマには追加せずUserDefaultsへ保存する。保存値が不明な場合はブルーへフォールバックする。

## Relationships

### Workplace 1 - N Payslip

1つの勤務先は複数の給与明細を持つ。

給与明細は必ず1つの勤務先に紐づく。

### Workplace 1 - N WorkplaceDeductionDefinition

1つの勤務先は複数の控除内訳項目設定を持てる。

### Payslip 1 - N PayslipDeductionItem

1つの給与明細は複数の控除内訳を持てる。

控除項目設定を非表示にしても、過去のPayslipDeductionItemは保持する。

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
- 既存の社会保険料フィールドは、対象給与明細を次に編集したときに同名のPayslipDeductionItemへ段階的に移行する
- 勤務先別の控除合計・控除内訳推移
- バックアップファイルの形式
- 税理士共有用エクスポート
- 複数端末同期を行う場合の同期ID
