import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EmployerFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    private let employer: Employer?

    @State private var name: String
    @State private var employerType: EmployerType
    @State private var defaultIncomeCategoryRaw: String
    @State private var memo: String
    @State private var isArchived: Bool
    @State private var validationMessage: String?
    @State private var isShowingValidation = false

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
            Section {
                TextField("勤務先名", text: $name)
                    .font(.system(size: 16, weight: .semibold))

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
            } header: {
                Text("基本情報")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            if employer != nil {
                Section {
                    if let employer {
                        NavigationLink {
                            EmployerDeductionTemplateListView(employer: employer)
                        } label: {
                            HStack(spacing: 11) {
                                EditorialIconBadge(systemImage: "list.bullet", size: 34)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("控除項目")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("この勤務先の入力とOCRに使用")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("\(employer.deductionTemplates.filter { $0.isActive }.count)項目")
                                    .font(.caption)
                                    .foregroundStyle(appTheme.accentColor)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("給与明細の設定")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                } footer: {
                    Text("短期掛金、厚生年金、雇用保険など、給与明細に固有の項目を設定できます。")
                }
                .listRowBackground(appTheme.accentColor.opacity(0.09))
            }

            Section {
                TextEditor(text: $memo)
                    .frame(minHeight: 110)
            } header: {
                Text("メモ")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            if employer != nil {
                Section {
                    Toggle("この勤務先を無効にする", isOn: $isArchived)
                } header: {
                    Text("利用状態")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                } footer: {
                    Text("無効にしても、保存済みの給与明細や書類はそのまま残ります。")
                }
            }
        }
        .tint(appTheme.accentColor)
        .listSectionSpacing(18)
        .scrollContentBackground(.hidden)
        .background(EditorialStyle.pageBackground)
        .navigationTitle(employer == nil ? "勤務先追加" : "勤務先編集")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("保存できません", isPresented: $isShowingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "入力内容を確認してください。")
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showValidation("勤務先名を入力してください。")
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
            showValidation("勤務先を保存できませんでした。もう一度お試しください。")
        }
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        isShowingValidation = true
    }
}

private struct EmployerDeductionTemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let employer: Employer

    @State private var isAddingTemplate = false
    @State private var operationErrorMessage: String?
    @State private var draggedTemplateID: PersistentIdentifier?

    private var sortedTemplates: [EmployerDeductionTemplate] {
        employer.deductionTemplates.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private var activeTemplates: [EmployerDeductionTemplate] {
        sortedTemplates.filter(\.isActive)
    }

    private var inactiveTemplates: [EmployerDeductionTemplate] {
        sortedTemplates.filter { !$0.isActive }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(employer.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("給与入力とOCRで使用する項目")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(EditorialStyle.pageBackground)
            .listRowSeparator(.hidden)

            if sortedTemplates.isEmpty {
                ContentUnavailableView(
                    "控除項目は未登録です",
                    systemImage: "text.badge.plus",
                    description: Text("短期掛金、厚生年金、雇用保険など、給与明細に記載される名前を追加してください。")
                )
            } else {
                if !activeTemplates.isEmpty {
                    Section {
                        ForEach(Array(activeTemplates.enumerated()), id: \.element.persistentModelID) { index, template in
                            NavigationLink {
                                EmployerDeductionTemplateFormView(
                                    employer: employer,
                                    template: template
                                )
                            } label: {
                                EmployerDeductionTemplateRow(
                                    template: template,
                                    rank: index + 1,
                                    canReorder: true
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
                            .listRowBackground(Color(.systemBackground))
                            .listRowSeparatorTint(EditorialStyle.divider)
                            .onDrag {
                                let id = template.persistentModelID
                                draggedTemplateID = id
                                return NSItemProvider(object: "\(id)" as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: EmployerDeductionTemplateDropDelegate(
                                    targetTemplateID: template.persistentModelID,
                                    draggedTemplateID: $draggedTemplateID,
                                    moveTemplate: reorderTemplate
                                )
                            )
                        }
                        .onMove(perform: moveActiveTemplates)
                        .onDelete { offsets in
                            deleteTemplates(at: offsets, from: activeTemplates)
                        }
                    } header: {
                        deductionSectionHeader(title: "使用中", count: activeTemplates.count)
                    } footer: {
                        Label("右端を長押しして入力画面の表示順を変更", systemImage: "arrow.up.arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }

                if !inactiveTemplates.isEmpty {
                    Section {
                        ForEach(inactiveTemplates) { template in
                            NavigationLink {
                                EmployerDeductionTemplateFormView(
                                    employer: employer,
                                    template: template
                                )
                            } label: {
                                EmployerDeductionTemplateRow(
                                    template: template,
                                    rank: nil,
                                    canReorder: false
                                )
                            }
                            .opacity(0.62)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
                            .listRowBackground(Color(.systemBackground))
                            .listRowSeparatorTint(EditorialStyle.divider)
                        }
                        .onDelete { offsets in
                            deleteTemplates(at: offsets, from: inactiveTemplates)
                        }
                    } header: {
                        deductionSectionHeader(title: "使用しない項目", count: inactiveTemplates.count)
                    } footer: {
                        Text("項目を削除または使用停止にしても、保存済みの給与明細にある項目名と金額は残ります。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(18)
        .scrollContentBackground(.hidden)
        .background(EditorialStyle.pageBackground)
        .navigationTitle("控除項目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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

    private func deductionSectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)項目")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func moveActiveTemplates(from source: IndexSet, to destination: Int) {
        var reordered = activeTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        applySortOrder(to: reordered + inactiveTemplates)
    }

    private func reorderTemplate(
        draggedTemplateID: PersistentIdentifier,
        targetTemplateID: PersistentIdentifier
    ) {
        guard draggedTemplateID != targetTemplateID else {
            return
        }

        var reordered = activeTemplates
        guard let sourceIndex = reordered.firstIndex(where: { $0.persistentModelID == draggedTemplateID }),
              let targetIndex = reordered.firstIndex(where: { $0.persistentModelID == targetTemplateID }) else {
            return
        }

        let draggedTemplate = reordered.remove(at: sourceIndex)
        reordered.insert(draggedTemplate, at: targetIndex)
        applySortOrder(to: reordered + inactiveTemplates)
    }

    private func applySortOrder(to templates: [EmployerDeductionTemplate]) {
        for (index, template) in templates.enumerated() {
            template.sortOrder = index
            template.updatedAt = Date()
        }
        saveListChange(errorMessage: "控除項目の並び順を保存できませんでした。")
    }

    private func deleteTemplates(at offsets: IndexSet, from templates: [EmployerDeductionTemplate]) {
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

private struct EmployerDeductionTemplateRow: View {
    @Environment(\.appTheme) private var appTheme

    let template: EmployerDeductionTemplate
    let rank: Int?
    let canReorder: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(rank.map { String(format: "%02d", $0) } ?? "–")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appTheme.accentColor)
                .monospacedDigit()
                .frame(width: 27, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(template.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !template.isActive {
                        Text("停止中")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if canReorder {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("長押しして並べ替え")
            }
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard template.isActive else {
            return "過去の給与明細にはそのまま残ります"
        }

        guard !template.ocrAliases.isEmpty else {
            return "別名なし"
        }

        return "別名：\(template.ocrAliases.joined(separator: "・"))"
    }
}

private struct EmployerDeductionTemplateDropDelegate: DropDelegate {
    let targetTemplateID: PersistentIdentifier
    @Binding var draggedTemplateID: PersistentIdentifier?
    let moveTemplate: (PersistentIdentifier, PersistentIdentifier) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggedTemplateID else {
            return
        }

        moveTemplate(draggedTemplateID, targetTemplateID)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedTemplateID = nil
        return true
    }
}

private struct EmployerDeductionTemplateFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let employer: Employer
    let template: EmployerDeductionTemplate?

    @State private var displayName: String
    @State private var aliases: [OCRAliasDraft]
    @State private var isActive: Bool
    @State private var validationMessage: String?
    @State private var isShowingValidation = false

    init(employer: Employer, template: EmployerDeductionTemplate? = nil) {
        self.employer = employer
        self.template = template
        _displayName = State(initialValue: template?.displayName ?? "")
        _aliases = State(initialValue: (template?.ocrAliases ?? []).map(OCRAliasDraft.init))
        _isActive = State(initialValue: template?.isActive ?? true)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    EditorialIconBadge(systemImage: "building.2", size: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(employer.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("この勤務先の給与入力とOCRに使用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(EditorialStyle.pageBackground)
            .listRowSeparator(.hidden)

            Section {
                TextField("例：短期掛金", text: $displayName)
                    .font(.system(size: 16, weight: .semibold))
            } header: {
                Text("項目名")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            } footer: {
                Text("給与明細に表示されている名前をそのまま入力してください。")
            }

            Section {
                ForEach(Array(aliases.enumerated()), id: \.element.id) { index, alias in
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(appTheme.accentColor)
                            .monospacedDigit()
                            .frame(width: 25, alignment: .leading)

                        TextField(
                            "OCRで探す別名",
                            text: Binding(
                                get: { aliasValue(for: alias.id) },
                                set: { updateAlias(alias.id, value: $0) }
                            )
                        )
                            .font(.system(size: 15))

                        Button {
                            aliases.removeAll { $0.id == alias.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("別名を削除")
                    }
                }

                Button {
                    aliases.append(OCRAliasDraft(value: ""))
                } label: {
                    Label("別名を追加", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appTheme.accentColor)
                }
            } header: {
                Text("OCR用の別名")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            } footer: {
                Text("給与明細によって表記が異なる名前だけを追加します。")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("入力とOCRで使用する", isOn: $isActive)
                        .font(.system(size: 15, weight: .semibold))

                    Text("オフにすると今後の給与入力候補から外れます。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("利用状態")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            } footer: {
                Text("使用を停止しても、過去の給与明細に保存された項目名と金額はそのまま残ります。")
            }
            .listRowBackground(appTheme.accentColor.opacity(0.08))
        }
        .tint(appTheme.accentColor)
        .listSectionSpacing(18)
        .scrollContentBackground(.hidden)
        .background(EditorialStyle.pageBackground)
        .navigationTitle(template == nil ? "控除項目追加" : "控除項目編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .alert("保存できません", isPresented: $isShowingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "入力内容を確認してください。")
        }
    }

    private func save() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showValidation("項目名を入力してください。")
            return
        }

        let duplicateExists = employer.deductionTemplates.contains { candidate in
            candidate.persistentModelID != template?.persistentModelID &&
                candidate.displayName.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }
        guard !duplicateExists else {
            showValidation("同じ名前の控除項目が登録されています。")
            return
        }

        let cleanedAliases = aliases
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let canonicalAliases = cleanedAliases.map(DeductionNameNormalizer.canonicalKey)
        guard Set(canonicalAliases).count == canonicalAliases.count else {
            showValidation("同じ別名が重複しています。")
            return
        }

        if let template {
            template.displayName = name
            template.ocrAliases = cleanedAliases
            template.isActive = isActive
            template.updatedAt = Date()
        } else {
            let newTemplate = EmployerDeductionTemplate(
                employer: employer,
                displayName: name,
                ocrAliases: cleanedAliases,
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
            showValidation("保存できませんでした。もう一度お試しください。")
        }
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        isShowingValidation = true
    }

    private func aliasValue(for id: UUID) -> String {
        aliases.first(where: { $0.id == id })?.value ?? ""
    }

    private func updateAlias(_ id: UUID, value: String) {
        guard let index = aliases.firstIndex(where: { $0.id == id }) else {
            return
        }
        aliases[index].value = value
    }
}

private struct OCRAliasDraft: Identifiable {
    let id = UUID()
    var value: String
}
