import Foundation
import SwiftData
import SwiftUI

struct PayRecordFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @Query(sort: [
        SortDescriptor(\DocumentAttachment.createdAt, order: .reverse)
    ]) private var documentAttachments: [DocumentAttachment]

    private let payRecord: PayRecord?
    private let initialEmployer: Employer?

    @State private var selectedEmployerID: PersistentIdentifier?
    @State private var paymentYear: Int
    @State private var paymentMonth: Int
    @State private var incomeCategory: IncomeCategory
    @State private var grossAmountText: String
    @State private var netAmountText: String
    @State private var deductionAmountText: String
    @State private var incomeTaxAmountText: String
    @State private var residentTaxAmountText: String
    @State private var socialInsuranceAmountText: String
    @State private var otherDeductionAmountText: String
    @State private var memo: String
    @State private var validationMessage: String?
    @State private var isShowingValidation = false
    @State private var isAddingEmployer = false

    init(payRecord: PayRecord? = nil, initialEmployer: Employer? = nil) {
        self.payRecord = payRecord
        self.initialEmployer = initialEmployer
        let resolvedEmployer = payRecord?.employer ?? initialEmployer
        _selectedEmployerID = State(initialValue: resolvedEmployer?.persistentModelID)
        _paymentYear = State(initialValue: payRecord?.paymentYear ?? Calendar.current.component(.year, from: Date()))
        _paymentMonth = State(initialValue: payRecord?.paymentMonth ?? Calendar.current.component(.month, from: Date()))
        _incomeCategory = State(initialValue: payRecord?.incomeCategory ?? initialEmployer?.defaultIncomeCategory ?? .partTimeSalary)
        _grossAmountText = State(initialValue: payRecord?.grossAmount.formText ?? "")
        _netAmountText = State(initialValue: payRecord?.netAmount.formText ?? "")
        _deductionAmountText = State(initialValue: payRecord?.deductionAmount?.formText ?? "")
        _incomeTaxAmountText = State(initialValue: payRecord?.incomeTaxAmount?.formText ?? "")
        _residentTaxAmountText = State(initialValue: payRecord?.residentTaxAmount?.formText ?? "")
        _socialInsuranceAmountText = State(initialValue: payRecord?.socialInsuranceAmount?.formText ?? "")
        _otherDeductionAmountText = State(initialValue: payRecord?.otherDeductionAmount?.formText ?? "")
        _memo = State(initialValue: payRecord?.memo ?? "")
    }

    private var selectableEmployers: [Employer] {
        employers.filter { employer in
            !employer.isArchived || employer.persistentModelID == payRecord?.employer?.persistentModelID
        }
    }

    private var selectedEmployer: Employer? {
        employers.first { $0.persistentModelID == selectedEmployerID }
    }

    private var linkedDocuments: [DocumentAttachment] {
        guard let payRecord else {
            return []
        }

        return documentAttachments.filter {
            $0.payRecord?.persistentModelID == payRecord.persistentModelID &&
            ($0.documentType == .payslip || $0.documentType == .bonusPayslip)
        }
    }

    var body: some View {
        Form {
            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            Section("支給情報") {
                if selectableEmployers.isEmpty {
                    Text("給与明細を登録するには、先に勤務先が必要です。常勤先、外勤先、当直先などを登録してください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        isAddingEmployer = true
                    } label: {
                        Label("勤務先を追加", systemImage: "building.2")
                    }
                }

                Picker("勤務先（必須）", selection: $selectedEmployerID) {
                    Text("選択してください").tag(Optional<PersistentIdentifier>.none)
                    ForEach(selectableEmployers) { employer in
                        Text(employer.name).tag(Optional(employer.persistentModelID))
                    }
                }
                .onChange(of: selectedEmployerID) { _, newValue in
                    guard payRecord == nil,
                          let employer = employers.first(where: { $0.persistentModelID == newValue }),
                          let defaultCategory = employer.defaultIncomeCategory else {
                        return
                    }
                    incomeCategory = defaultCategory
                }

                Picker("収入区分（必須）", selection: $incomeCategory) {
                    ForEach(IncomeCategory.allCases) { category in
                        Text(category.label).tag(category)
                    }
                }

                Stepper(value: $paymentYear, in: 2000...2100) {
                    Text(verbatim: "支給年 \(paymentYear)年")
                }

                Picker("支給月", selection: $paymentMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)月").tag(month)
                    }
                }
            }

            Section {
                currencyField("額面（必須）", text: $grossAmountText)
                currencyField("手取り（必須）", text: $netAmountText)
                currencyField("控除合計", text: $deductionAmountText)
                currencyField("所得税", text: $incomeTaxAmountText)
                currencyField("住民税", text: $residentTaxAmountText)
                currencyField("社会保険料", text: $socialInsuranceAmountText)
                currencyField("その他控除", text: $otherDeductionAmountText)
            } header: {
                Text("金額")
            } footer: {
                Text("金額は円単位の整数で保存します。カンマや「円」を含めても入力できます。")
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
            }

            if let payRecord {
                Section("添付書類") {
                    if linkedDocuments.isEmpty {
                        Text("この明細に紐づく書類はまだありません。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedDocuments) { document in
                            if let fileURL = DocumentFileStore.fileURL(for: document) {
                                NavigationLink {
                                    DocumentPreviewView(
                                        title: document.documentType.label,
                                        fileType: document.attachmentFileType,
                                        fileURL: fileURL
                                    )
                                } label: {
                                    documentLabel(document)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.documentType.label)
                                    Text(document.originalFileName ?? "ファイル名未設定")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    NavigationLink {
                        DocumentFormView(linkedPayRecord: payRecord)
                    } label: {
                        Label("書類を添付", systemImage: "paperclip")
                    }
                }
            }
        }
        .navigationTitle(payRecord == nil ? "明細追加" : "明細編集")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .sheet(isPresented: $isAddingEmployer) {
            NavigationStack {
                EmployerFormView()
            }
        }
        .alert("保存できません", isPresented: $isShowingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "入力内容を確認してください。")
        }
    }

    private func currencyField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: Binding(
            get: {
                text.wrappedValue
            },
            set: { newValue in
                text.wrappedValue = groupedAmountText(from: newValue)
            }
        ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
    }

    private func documentLabel(_ document: DocumentAttachment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(document.documentType.label)
                Spacer()
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(document.originalFileName ?? "ファイル名未設定")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func save() {
        guard let selectedEmployer else {
            showValidation("勤務先を選択してください。")
            return
        }

        guard let grossAmount = requiredAmount(from: grossAmountText) else {
            showValidation("額面は0以上の整数で入力してください。")
            return
        }

        guard let netAmount = requiredAmount(from: netAmountText) else {
            showValidation("手取りは0以上の整数で入力してください。")
            return
        }

        guard let deductionAmount = optionalAmount(from: deductionAmountText),
              let incomeTaxAmount = optionalAmount(from: incomeTaxAmountText),
              let residentTaxAmount = optionalAmount(from: residentTaxAmountText),
              let socialInsuranceAmount = optionalAmount(from: socialInsuranceAmountText),
              let otherDeductionAmount = optionalAmount(from: otherDeductionAmountText) else {
            showValidation("任意の金額項目も、入力する場合は0以上の整数にしてください。")
            return
        }

        if let payRecord {
            payRecord.employer = selectedEmployer
            payRecord.paymentYear = paymentYear
            payRecord.paymentMonth = paymentMonth
            payRecord.incomeCategory = incomeCategory
            payRecord.grossAmount = grossAmount
            payRecord.netAmount = netAmount
            payRecord.deductionAmount = deductionAmount
            payRecord.incomeTaxAmount = incomeTaxAmount
            payRecord.residentTaxAmount = residentTaxAmount
            payRecord.socialInsuranceAmount = socialInsuranceAmount
            payRecord.otherDeductionAmount = otherDeductionAmount
            payRecord.memo = memo
            payRecord.updatedAt = Date()
        } else {
            let newRecord = PayRecord(
                employer: selectedEmployer,
                paymentYear: paymentYear,
                paymentMonth: paymentMonth,
                incomeCategory: incomeCategory,
                grossAmount: grossAmount,
                netAmount: netAmount,
                deductionAmount: deductionAmount,
                incomeTaxAmount: incomeTaxAmount,
                residentTaxAmount: residentTaxAmount,
                socialInsuranceAmount: socialInsuranceAmount,
                otherDeductionAmount: otherDeductionAmount,
                memo: memo
            )
            modelContext.insert(newRecord)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            showValidation("保存に失敗しました。もう一度お試しください。")
        }
    }

    private func requiredAmount(from text: String) -> Int? {
        let normalizedText = normalizedAmountText(from: text)
        guard !normalizedText.isEmpty, let value = Int(normalizedText), value >= 0 else {
            return nil
        }
        return value
    }

    private func optionalAmount(from text: String) -> Int?? {
        let normalizedText = normalizedAmountText(from: text)
        guard !normalizedText.isEmpty else {
            return .some(nil)
        }
        guard let value = Int(normalizedText), value >= 0 else {
            return nil
        }
        return .some(value)
    }

    private func normalizedAmountText(from text: String) -> String {
        let halfWidthText = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidthText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "円", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func groupedAmountText(from text: String) -> String {
        let normalizedText = normalizedAmountText(from: text)
        let digits = normalizedText.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits) else {
            return ""
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? digits
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        isShowingValidation = true
    }
}

private extension Int {
    var formText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
