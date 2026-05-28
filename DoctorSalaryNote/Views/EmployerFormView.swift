import SwiftData
import SwiftUI

struct EmployerFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let employer: Employer?

    @State private var name: String
    @State private var employerType: EmployerType
    @State private var defaultIncomeCategoryRaw: String
    @State private var memo: String
    @State private var isArchived: Bool
    @State private var validationMessage: String?

    init(employer: Employer? = nil) {
        self.employer = employer
        _name = State(initialValue: employer?.name ?? "")
        _employerType = State(initialValue: employer?.employerType ?? .partTime)
        _defaultIncomeCategoryRaw = State(initialValue: employer?.defaultIncomeCategoryRaw ?? "")
        _memo = State(initialValue: employer?.memo ?? "")
        _isArchived = State(initialValue: employer?.isArchived ?? false)
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("勤務先名", text: $name)

                Picker("勤務先区分", selection: $employerType) {
                    ForEach(EmployerType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }

                Picker("既定の収入区分", selection: $defaultIncomeCategoryRaw) {
                    Text("未設定").tag("")
                    ForEach(IncomeCategory.allCases) { category in
                        Text(category.label).tag(category.rawValue)
                    }
                }
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
            }

            if employer != nil {
                Section {
                    Toggle("無効にする", isOn: $isArchived)
                }
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(employer == nil ? "勤務先追加" : "勤務先編集")
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

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "勤務先名を入力してください。"
            return
        }

        let selectedCategory = IncomeCategory(rawValue: defaultIncomeCategoryRaw)

        if let employer {
            employer.name = trimmedName
            employer.employerType = employerType
            employer.defaultIncomeCategory = selectedCategory
            employer.memo = memo
            employer.isArchived = isArchived
            employer.updatedAt = Date()
        } else {
            let newEmployer = Employer(
                name: trimmedName,
                employerType: employerType,
                defaultIncomeCategory: selectedCategory,
                memo: memo
            )
            modelContext.insert(newEmployer)
        }

        try? modelContext.save()
        dismiss()
    }
}
