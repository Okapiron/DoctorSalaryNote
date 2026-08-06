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
                    if let employer {
                        NavigationLink {
                            EmployerDeductionTemplateListView(employer: employer)
                        } label: {
                            Label("給与明細の控除項目", systemImage: "list.bullet.rectangle")
                        }
                    }
                } footer: {
                    Text("この勤務先の給与明細にある項目名を登録すると、次回のOCRで金額を探します。")
                }

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

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "勤務先を保存できませんでした。もう一度お試しください。"
        }
    }
}

private struct EmployerDeductionTemplateListView: View {
    @Environment(\.modelContext) private var modelContext

    let employer: Employer

    @State private var isAddingTemplate = false
    @State private var operationErrorMessage: String?

    private var sortedTemplates: [EmployerDeductionTemplate] {
        employer.deductionTemplates.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                if sortedTemplates.isEmpty {
                    ContentUnavailableView(
                        "控除項目は未登録です",
                        systemImage: "text.badge.plus",
                        description: Text("短期掛金、厚生年金、雇用保険など、給与明細に記載される名前を追加してください。")
                    )
                } else {
                    ForEach(sortedTemplates) { template in
                        NavigationLink {
                            EmployerDeductionTemplateFormView(
                                employer: employer,
                                template: template
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.displayName)
                                if !template.isActive {
                                    Text("現在は使用しない")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !template.ocrAliases.isEmpty {
                                    Text("別名: \(template.ocrAliases.joined(separator: "・"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .onMove(perform: moveTemplates)
                    .onDelete(perform: deleteTemplates)
                }
            } footer: {
                Text("項目を削除しても、保存済みの給与明細にある項目名と金額は残ります。")
            }
        }
        .navigationTitle("控除項目")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button {
                    isAddingTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("控除項目を追加")
            }
        }
        .sheet(isPresented: $isAddingTemplate) {
            NavigationStack {
                EmployerDeductionTemplateFormView(employer: employer)
            }
        }
        .alert("変更を保存できませんでした", isPresented: Binding(
            get: { operationErrorMessage != nil },
            set: { if !$0 { operationErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "もう一度お試しください。")
        }
    }

    private func moveTemplates(from source: IndexSet, to destination: Int) {
        var reordered = sortedTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in reordered.enumerated() {
            template.sortOrder = index
            template.updatedAt = Date()
        }
        saveListChange(errorMessage: "控除項目の並び順を保存できませんでした。")
    }

    private func deleteTemplates(at offsets: IndexSet) {
        let templates = sortedTemplates
        for offset in offsets {
            modelContext.delete(templates[offset])
        }
        saveListChange(errorMessage: "控除項目を削除できませんでした。")
    }

    private func saveListChange(errorMessage: String) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            operationErrorMessage = errorMessage
        }
    }
}

private struct EmployerDeductionTemplateFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let employer: Employer
    let template: EmployerDeductionTemplate?

    @State private var displayName: String
    @State private var aliasesText: String
    @State private var isActive: Bool
    @State private var validationMessage: String?

    init(employer: Employer, template: EmployerDeductionTemplate? = nil) {
        self.employer = employer
        self.template = template
        _displayName = State(initialValue: template?.displayName ?? "")
        _aliasesText = State(initialValue: template?.ocrAliases.joined(separator: "\n") ?? "")
        _isActive = State(initialValue: template?.isActive ?? true)
    }

    var body: some View {
        Form {
            Section {
                TextField("例: 短期掛金", text: $displayName)
                Toggle("入力とOCRで使用する", isOn: $isActive)
            } header: {
                Text("項目名")
            } footer: {
                Text("給与明細に表示されている名前をそのまま入力してください。")
            }

            Section {
                TextEditor(text: $aliasesText)
                    .frame(minHeight: 100)
            } header: {
                Text("OCR用の別名（任意）")
            } footer: {
                Text("帳票によって表記が違う場合は、1行に1つずつ入力します。")
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(template == nil ? "控除項目追加" : "控除項目編集")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
    }

    private func save() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            validationMessage = "項目名を入力してください。"
            return
        }

        let duplicateExists = employer.deductionTemplates.contains { candidate in
            candidate.persistentModelID != template?.persistentModelID &&
                candidate.displayName.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }
        guard !duplicateExists else {
            validationMessage = "同じ名前の控除項目が登録されています。"
            return
        }

        let aliases = aliasesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let template {
            template.displayName = name
            template.ocrAliases = aliases
            template.isActive = isActive
            template.updatedAt = Date()
        } else {
            let newTemplate = EmployerDeductionTemplate(
                employer: employer,
                displayName: name,
                ocrAliases: aliases,
                sortOrder: employer.deductionTemplates.count,
                isActive: isActive
            )
            modelContext.insert(newTemplate)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "保存できませんでした。もう一度お試しください。"
        }
    }
}
