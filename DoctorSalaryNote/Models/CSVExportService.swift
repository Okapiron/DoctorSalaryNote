import Foundation

enum CSVExportService {
    static func makePayRecordsCSVFile(payRecords: [PayRecord], year: Int?) throws -> URL {
        let filteredRecords = payRecords
            .filter { record in
                guard let year else {
                    return true
                }
                return record.paymentYear == year
            }
            .sorted {
                if $0.paymentYear != $1.paymentYear {
                    return $0.paymentYear < $1.paymentYear
                }
                if $0.paymentMonth != $1.paymentMonth {
                    return $0.paymentMonth < $1.paymentMonth
                }
                return ($0.employer?.name ?? "").localizedStandardCompare($1.employer?.name ?? "") == .orderedAscending
            }

        let rows = [
            [
                "支給年",
                "支給月",
                "勤務先名",
                "収入区分",
                "額面",
                "手取り",
                "控除合計",
                "所得税",
                "住民税",
                "社会保険料",
                "その他控除",
                "メモ"
            ]
        ] + filteredRecords.map { record in
            [
                String(record.paymentYear),
                String(record.paymentMonth),
                record.employer?.name ?? "",
                record.incomeCategory.label,
                String(record.grossAmount),
                String(record.netAmount),
                String(totalDeductions(for: record)),
                optionalAmountText(record.incomeTaxAmount),
                optionalAmountText(record.residentTaxAmount),
                optionalAmountText(record.socialInsuranceAmount),
                optionalAmountText(record.otherDeductionAmount),
                record.memo
            ]
        }

        let csvText = rows
            .map { row in row.map(escapedCSVField).joined(separator: ",") }
            .joined(separator: "\n")

        let fileName = year.map { "医師給与ノート_給与明細_\($0)年.csv" } ?? "医師給与ノート_給与明細_全期間.csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csvText.utf8))
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private static func totalDeductions(for record: PayRecord) -> Int {
        record.deductionAmount ?? max(record.grossAmount - record.netAmount, 0)
    }

    private static func optionalAmountText(_ amount: Int?) -> String {
        amount.map(String.init) ?? ""
    }

    private static func escapedCSVField(_ field: String) -> String {
        let needsEscaping = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
        return needsEscaping ? "\"\(escapedField)\"" : escapedField
    }
}
