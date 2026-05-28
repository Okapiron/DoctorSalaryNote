import Foundation
import SwiftData

enum EmployerType: String, CaseIterable, Codable, Identifiable {
    case fullTime
    case partTime
    case nightDuty
    case spot
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullTime: "常勤"
        case .partTime: "外勤"
        case .nightDuty: "当直"
        case .spot: "スポット"
        case .other: "その他"
        }
    }
}

enum IncomeCategory: String, CaseIterable, Codable, Identifiable {
    case fullTimeSalary
    case partTimeSalary
    case nightDuty
    case dayNightDuty
    case spot
    case bonus
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullTimeSalary: "常勤給与"
        case .partTimeSalary: "外勤給与"
        case .nightDuty: "当直"
        case .dayNightDuty: "日当直"
        case .spot: "スポット"
        case .bonus: "賞与"
        case .other: "その他"
        }
    }
}

enum DocumentType: String, CaseIterable, Codable, Identifiable {
    case payslip
    case bonusPayslip
    case withholdingSlip
    case paymentStatement
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .payslip: "給与明細"
        case .bonusPayslip: "賞与明細"
        case .withholdingSlip: "源泉徴収票"
        case .paymentStatement: "支払調書"
        case .other: "その他"
        }
    }

    var requiresPayRecord: Bool {
        self == .payslip || self == .bonusPayslip
    }

    var requiresEmployer: Bool {
        self == .withholdingSlip || self == .paymentStatement
    }
}

enum AttachmentFileType: String, CaseIterable, Codable, Identifiable {
    case pdf
    case image
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .image: "画像"
        case .other: "その他"
        }
    }
}

enum ViewMode: String, CaseIterable, Codable, Identifiable {
    case calendarYear
    case fiscalYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendarYear: "年別"
        case .fiscalYear: "年度別"
        }
    }
}

@Model
final class Employer {
    var name: String
    var employerTypeRaw: String
    var defaultIncomeCategoryRaw: String?
    var memo: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \PayRecord.employer)
    var payRecords: [PayRecord] = []

    init(
        name: String,
        employerType: EmployerType = .partTime,
        defaultIncomeCategory: IncomeCategory? = nil,
        memo: String = "",
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.employerTypeRaw = employerType.rawValue
        self.defaultIncomeCategoryRaw = defaultIncomeCategory?.rawValue
        self.memo = memo
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var employerType: EmployerType {
        get { EmployerType(rawValue: employerTypeRaw) ?? .other }
        set { employerTypeRaw = newValue.rawValue }
    }

    var defaultIncomeCategory: IncomeCategory? {
        get {
            guard let defaultIncomeCategoryRaw else { return nil }
            return IncomeCategory(rawValue: defaultIncomeCategoryRaw)
        }
        set { defaultIncomeCategoryRaw = newValue?.rawValue }
    }
}

@Model
final class PayRecord {
    var employer: Employer?
    var paymentYear: Int
    var paymentMonth: Int
    var incomeCategoryRaw: String
    var grossAmount: Int
    var netAmount: Int
    var deductionAmount: Int?
    var incomeTaxAmount: Int?
    var residentTaxAmount: Int?
    var socialInsuranceAmount: Int?
    var otherDeductionAmount: Int?
    var memo: String
    var createdAt: Date
    var updatedAt: Date

    init(
        employer: Employer,
        paymentYear: Int,
        paymentMonth: Int,
        incomeCategory: IncomeCategory,
        grossAmount: Int,
        netAmount: Int,
        deductionAmount: Int? = nil,
        incomeTaxAmount: Int? = nil,
        residentTaxAmount: Int? = nil,
        socialInsuranceAmount: Int? = nil,
        otherDeductionAmount: Int? = nil,
        memo: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.employer = employer
        self.paymentYear = paymentYear
        self.paymentMonth = paymentMonth
        self.incomeCategoryRaw = incomeCategory.rawValue
        self.grossAmount = grossAmount
        self.netAmount = netAmount
        self.deductionAmount = deductionAmount
        self.incomeTaxAmount = incomeTaxAmount
        self.residentTaxAmount = residentTaxAmount
        self.socialInsuranceAmount = socialInsuranceAmount
        self.otherDeductionAmount = otherDeductionAmount
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var incomeCategory: IncomeCategory {
        get { IncomeCategory(rawValue: incomeCategoryRaw) ?? .other }
        set { incomeCategoryRaw = newValue.rawValue }
    }
}

@Model
final class DocumentAttachment {
    var employer: Employer?
    var payRecord: PayRecord?
    var documentYear: Int
    var documentTypeRaw: String
    var title: String
    var attachmentFileTypeRaw: String
    var localFilePath: String?
    var originalFileName: String?
    var storedFileName: String?
    var mimeType: String?
    var fileSize: Int?
    var memo: String
    var createdAt: Date
    var updatedAt: Date

    init(
        employer: Employer? = nil,
        payRecord: PayRecord? = nil,
        documentYear: Int,
        documentType: DocumentType = .payslip,
        title: String = "",
        attachmentFileType: AttachmentFileType = .other,
        localFilePath: String? = nil,
        originalFileName: String? = nil,
        storedFileName: String? = nil,
        mimeType: String? = nil,
        fileSize: Int? = nil,
        memo: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.employer = employer
        self.payRecord = payRecord
        self.documentYear = documentYear
        self.documentTypeRaw = documentType.rawValue
        self.title = title
        self.attachmentFileTypeRaw = attachmentFileType.rawValue
        self.localFilePath = localFilePath
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var documentType: DocumentType {
        get { DocumentType(rawValue: documentTypeRaw) ?? .other }
        set { documentTypeRaw = newValue.rawValue }
    }

    var attachmentFileType: AttachmentFileType {
        get { AttachmentFileType(rawValue: attachmentFileTypeRaw) ?? .other }
        set { attachmentFileTypeRaw = newValue.rawValue }
    }
}

@Model
final class AppSettings {
    var defaultViewModeRaw: String
    var fiscalYearStartMonth: Int
    var biometricLockEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        defaultViewMode: ViewMode = .calendarYear,
        fiscalYearStartMonth: Int = 4,
        biometricLockEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.defaultViewModeRaw = defaultViewMode.rawValue
        self.fiscalYearStartMonth = fiscalYearStartMonth
        self.biometricLockEnabled = biometricLockEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var defaultViewMode: ViewMode {
        get { ViewMode(rawValue: defaultViewModeRaw) ?? .calendarYear }
        set { defaultViewModeRaw = newValue.rawValue }
    }

    var isBiometricLockEnabled: Bool {
        get { biometricLockEnabled }
        set { biometricLockEnabled = newValue }
    }
}
