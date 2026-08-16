import SwiftData
import XCTest
@testable import DoctorSalaryNote

final class PayrollValidationTests: XCTestCase {
    func testDeductionAliasesUseOneCanonicalKey() {
        XCTAssertEqual(
            DeductionNameNormalizer.canonicalKey("短期掛金（健康保険）"),
            DeductionNameNormalizer.canonicalKey("健康保険")
        )
        XCTAssertEqual(
            DeductionNameNormalizer.canonicalKey("長期掛金"),
            DeductionNameNormalizer.canonicalKey("厚生年金")
        )
    }

    func testAmountConsistencyFindsArithmeticMismatch() {
        let warnings = AmountConsistencyValidator.warnings(
            grossAmount: 600_000,
            netAmount: 500_000,
            deductionAmount: 90_000,
            itemizedDeductionTotal: 95_000
        )

        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings[0].contains("差額は 10,000円"))
        XCTAssertTrue(warnings[1].contains("5,000円"))
    }

    func testAmountConsistencyAllowsValidAmounts() {
        XCTAssertTrue(
            AmountConsistencyValidator.warnings(
                grossAmount: 600_000,
                netAmount: 500_000,
                deductionAmount: 100_000,
                itemizedDeductionTotal: 95_000
            ).isEmpty
        )
    }

    @MainActor
    func testCurrentSchemaPersistsNewDeductionModels() throws {
        let schema = Schema([
            Employer.self,
            PayRecord.self,
            EmployerDeductionTemplate.self,
            PayRecordDeductionItem.self,
            DocumentAttachment.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let employer = Employer(name: "テスト病院")
        let record = PayRecord(
            employer: employer,
            paymentYear: 2026,
            paymentMonth: 8,
            incomeCategory: .fullTimeSalary,
            grossAmount: 600_000,
            netAmount: 500_000
        )
        let template = EmployerDeductionTemplate(
            employer: employer,
            displayName: "短期掛金",
            ocrAliases: ["健康保険"]
        )
        let item = PayRecordDeductionItem(
            payRecord: record,
            templateKey: template.templateKey,
            displayNameSnapshot: "短期掛金",
            amount: 30_000,
            sortOrder: 0,
            inputSource: .ocr
        )
        let document = DocumentAttachment(
            employer: employer,
            payRecord: record,
            documentYear: 2026,
            documentMonth: 8,
            documentType: .payslip
        )

        context.insert(employer)
        context.insert(record)
        context.insert(template)
        context.insert(item)
        context.insert(document)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Employer>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PayRecord>()).first?.grossAmount, 600_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EmployerDeductionTemplate>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PayRecordDeductionItem>()).first?.amount, 30_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DocumentAttachment>()).first?.documentMonth, 8)
    }

    @MainActor
    func testCSVUsesBOMAndEscapesUserText() throws {
        let employer = Employer(name: "病院,本院")
        let record = PayRecord(
            employer: employer,
            paymentYear: 2026,
            paymentMonth: 8,
            incomeCategory: .fullTimeSalary,
            grossAmount: 600_000,
            netAmount: 500_000,
            memo: "確認\n済み"
        )

        let fileURL = try CSVExportService.makePayRecordsCSVFile(payRecords: [record], year: 2026)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let data = try Data(contentsOf: fileURL)

        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(text.contains("\"病院,本院\""))
        XCTAssertTrue(text.contains("\"確認\n済み\""))
        XCTAssertTrue(text.contains(",100000,"))
    }

    func testDocumentFileDeletionRemovesPhysicalFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoctorSalaryNote-delete-test-\(UUID().uuidString)")
        try Data("test".utf8).write(to: fileURL)

        try DocumentFileStore.deleteFile(at: fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
