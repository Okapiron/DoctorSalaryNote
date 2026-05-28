import SwiftData
import SwiftUI

struct PayRecordFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    private let payRecord: PayRecord?

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

    init(payRecord: PayRecord? = nil) {
        self.payRecord = payRecord
        _selectedEmployerID = State(initialValue: payRecord?.employer?.persistentModelID)
        _paymentYear = State(initialValue: payRecord?.paymentYear ?? Calendar.current.component(.year, from: Date()))
        _paymentMonth = State(initialValue: payRecord?.paymentMonth ?? Calendar.current.component(.month, from: Date()))
        _incomeCategory = State(initialValue: payRecord?.incomeCategory ?? .partTimeSalary)
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

    var body: some View {
        Form {
            Section("支給情報") {
                Picker("勤務先", selection: $selectedEmployerID) {
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

                Picker("収入区分", selection: $incomeCategory) {
                    ForEach(IncomeCategory.allCases) { category in
                        Text(category.label).tag(category)
                    }
                }

                Stepper(value: $paymentYear, in: 2000...2100) {
                    Text("支給年 \(paymentYear)年")
                }

                Picker("支給月", selection: $paymentMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)月").tag(month)
                    }
                }
            }

            Section("金額") {
                currencyField("額面", text: $grossAmountText)
                currencyField("手取り", text: $netAmountText)
                currencyField("控除合計", text: $deductionAmountText)
                currencyField("所得税", text: $incomeTaxAmountText)
                currencyField("住民税", text: $residentTaxAmountText)
                currencyField("社会保険料", text: $socialInsuranceAmountText)
                currencyField("その他控除", text: $otherDeductionAmountText)
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
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
    }

    private func currencyField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.numberPad)
    }

    private func save() {
        guard let selectedEmployer else {
            validationMessage = "勤務先を選択してください。"
            return
        }

        guard let grossAmount = requiredAmount(from: grossAmountText) else {
            validationMessage = "額面は0以上の整数で入力してください。"
            return
        }

        guard let netAmount = requiredAmount(from: netAmountText) else {
            validationMessage = "手取りは0以上の整数で入力してください。"
            return
        }

        guard let deductionAmount = optionalAmount(from: deductionAmountText),
              let incomeTaxAmount = optionalAmount(from: incomeTaxAmountText),
              let residentTaxAmount = optionalAmount(from: residentTaxAmountText),
              let socialInsuranceAmount = optionalAmount(from: socialInsuranceAmountText),
              let otherDeductionAmount = optionalAmount(from: otherDeductionAmountText) else {
            validationMessage = "任意の金額項目も、入力する場合は0以上の整数にしてください。"
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

        try? modelContext.save()
        dismiss()
    }

    private func requiredAmount(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 0 else {
            return nil
        }
        return value
    }

    private func optionalAmount(from text: String) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .some(nil)
        }
        guard let value = Int(trimmed), value >= 0 else {
            return nil
        }
        return .some(value)
    }
}

private extension Int {
    var formText: String {
        String(self)
    }
}
