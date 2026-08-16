import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct DeductionDraft: Identifiable {
    let id: UUID
    var templateKey: UUID?
    var name: String
    var amountText: String
    var inputSource: DeductionItemInputSource

    init(
        id: UUID = UUID(),
        templateKey: UUID? = nil,
        name: String,
        amountText: String = "",
        inputSource: DeductionItemInputSource = .manual
    ) {
        self.id = id
        self.templateKey = templateKey
        self.name = name
        self.amountText = amountText
        self.inputSource = inputSource
    }
}

private enum PayPeriodPicker: String, Identifiable {
    case year
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year: "支給年"
        case .month: "支給月"
        }
    }
}

struct PayRecordFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @Query(sort: [
        SortDescriptor(\DocumentAttachment.createdAt, order: .reverse)
    ]) private var documentAttachments: [DocumentAttachment]

    private let payRecord: PayRecord?
    private let initialEmployer: Employer?
    private let showsImportOptionsOnAppear: Bool
    private let initialEmployerID: PersistentIdentifier?
    private let initialPaymentYear: Int
    private let initialPaymentMonth: Int
    private let initialIncomeCategory: IncomeCategory

    @State private var selectedEmployerID: PersistentIdentifier?
    @State private var paymentYear: Int
    @State private var paymentMonth: Int
    @State private var incomeCategory: IncomeCategory
    @State private var grossAmountText: String
    @State private var netAmountText: String
    @State private var deductionAmountText: String
    @State private var incomeTaxAmountText: String
    @State private var residentTaxAmountText: String
    @State private var otherDeductionAmountText: String
    @State private var deductionDrafts: [DeductionDraft]
    @State private var memo: String
    @State private var validationMessage: String?
    @State private var isShowingValidation = false
    @State private var isAddingEmployer = false
    @State private var isPickingPDF = false
    @State private var isPickingImage = false
    @State private var isShowingCamera = false
    @State private var isShowingInitialImportOptions = false
    @State private var isShowingImportOverwriteWarning = false
    @State private var hasPresentedInitialImportOptions = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingDocumentLocalFilePath: String?
    @State private var pendingDocumentStoredFileName: String?
    @State private var pendingDocumentOriginalFileName: String?
    @State private var pendingDocumentMimeType: String?
    @State private var pendingDocumentFileSize: Int?
    @State private var pendingDocumentFileType: AttachmentFileType = .other
    @State private var pendingDocumentFileURL: URL?
    @State private var isRunningOCR = false
    @State private var ocrStatusMessage: String?
    @State private var saveWarningMessage: String?
    @State private var isShowingSaveWarning = false
    @State private var activePayPeriodPicker: PayPeriodPicker?
    @FocusState private var isTextInputFocused: Bool

    init(
        payRecord: PayRecord? = nil,
        initialEmployer: Employer? = nil,
        showsImportOptionsOnAppear: Bool = false
    ) {
        self.payRecord = payRecord
        self.initialEmployer = initialEmployer
        self.showsImportOptionsOnAppear = showsImportOptionsOnAppear
        let resolvedEmployer = payRecord?.employer ?? initialEmployer
        let resolvedEmployerID = resolvedEmployer?.persistentModelID
        let resolvedPaymentYear = payRecord?.paymentYear ?? Calendar.current.component(.year, from: Date())
        let resolvedPaymentMonth = payRecord?.paymentMonth ?? Calendar.current.component(.month, from: Date())
        let resolvedIncomeCategory = payRecord?.incomeCategory ?? initialEmployer?.defaultIncomeCategory ?? .partTimeSalary
        initialEmployerID = resolvedEmployerID
        initialPaymentYear = resolvedPaymentYear
        initialPaymentMonth = resolvedPaymentMonth
        initialIncomeCategory = resolvedIncomeCategory
        _selectedEmployerID = State(initialValue: resolvedEmployerID)
        _paymentYear = State(initialValue: resolvedPaymentYear)
        _paymentMonth = State(initialValue: resolvedPaymentMonth)
        _incomeCategory = State(initialValue: resolvedIncomeCategory)
        _grossAmountText = State(initialValue: payRecord?.grossAmount.formText ?? "")
        _netAmountText = State(initialValue: payRecord?.netAmount?.formText ?? "")
        _deductionAmountText = State(initialValue: payRecord?.deductionAmount?.formText ?? "")
        _incomeTaxAmountText = State(initialValue: payRecord?.incomeTaxAmount?.formText ?? "")
        _residentTaxAmountText = State(initialValue: payRecord?.residentTaxAmount?.formText ?? "")
        _otherDeductionAmountText = State(initialValue: payRecord?.otherDeductionAmount?.formText ?? "")
        let existingDeductionDrafts = payRecord?.sortedDeductionItems.map { item in
            DeductionDraft(
                templateKey: item.templateKey,
                name: item.displayNameSnapshot,
                amountText: item.amount.formText,
                inputSource: item.inputSource
            )
        } ?? []
        if existingDeductionDrafts.isEmpty,
           let legacySocialInsurance = payRecord?.socialInsuranceAmount {
            _deductionDrafts = State(
                initialValue: [
                    DeductionDraft(
                        name: "社会保険料",
                        amountText: legacySocialInsurance.formText
                    )
                ]
            )
        } else {
            _deductionDrafts = State(initialValue: existingDeductionDrafts)
        }
        _memo = State(initialValue: payRecord?.memo ?? "")
    }

#if DEBUG
    init(screenshotEmployer: Employer) {
        self.init(initialEmployer: screenshotEmployer)
        _paymentYear = State(initialValue: 2026)
        _paymentMonth = State(initialValue: 7)
        _incomeCategory = State(initialValue: .fullTimeSalary)
        _grossAmountText = State(initialValue: "824500")
        _netAmountText = State(initialValue: "641230")
        _deductionAmountText = State(initialValue: "183270")
        _incomeTaxAmountText = State(initialValue: "39200")
        _residentTaxAmountText = State(initialValue: "28600")
        _deductionDrafts = State(initialValue: [
            DeductionDraft(name: "健康保険", amountText: "27900", inputSource: .ocr),
            DeductionDraft(name: "厚生年金", amountText: "73200", inputSource: .ocr),
            DeductionDraft(name: "雇用保険", amountText: "4370", inputSource: .ocr)
        ])
        _ocrStatusMessage = State(
            initialValue: "書類から自動入力しました。原本と照合してから保存してください。"
        )
    }
#endif

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

            if let ocrStatusMessage, !isRunningOCR {
                Section {
                    Label(
                        ocrStatusMessage,
                        systemImage: ocrStatusMessage.contains("要確認")
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ocrStatusMessage.contains("要確認")
                            ? Color.orange
                            : appTheme.accentColor
                    )
                }
                .listRowBackground(Color(.systemBackground))
            }

            if payRecord == nil {
                Section {
                    Button {
                        presentImportOptions()
                    } label: {
                        HStack(spacing: 12) {
                            EditorialIconBadge(systemImage: "doc.viewfinder", size: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("給与明細を取り込む")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("写真・画像・PDFから入力をサポート")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(appTheme.accentColor.opacity(0.10))
                .listRowSeparator(.hidden)
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
                          let employer = employers.first(where: { $0.persistentModelID == newValue }) else {
                        return
                    }
                    if let defaultCategory = employer.defaultIncomeCategory {
                        incomeCategory = defaultCategory
                    }
                    mergeDeductionTemplates(from: employer)
                }

                Picker("収入区分（必須）", selection: $incomeCategory) {
                    ForEach(IncomeCategory.allCases) { category in
                        Text(category.label).tag(category)
                    }
                }

                payPeriodRow(title: "支給年", value: "\(paymentYear)年", picker: .year)
                payPeriodRow(title: "支給月", value: "\(paymentMonth)月", picker: .month)
            }

            Section {
                currencyField("額面（必須）", text: $grossAmountText)
                currencyField("手取り", text: $netAmountText)
                currencyField("控除合計", text: $deductionAmountText)
            } header: {
                Text("金額")
            } footer: {
                Text("金額は円単位で保存します。入力内容の整合性は保存前に確認できます。")
            }

            Section {
                currencyField("所得税", text: $incomeTaxAmountText)
                currencyField("住民税", text: $residentTaxAmountText)

                ForEach($deductionDrafts) { $draft in
                    deductionDraftRow(draft: $draft)
                        .dropDestination(for: String.self) { items, _ in
                            guard let sourceValue = items.first,
                                  let sourceID = UUID(uuidString: sourceValue) else {
                                return false
                            }
                            return moveDeductionDraft(sourceID: sourceID, targetID: draft.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("削除", role: .destructive) {
                                deductionDrafts.removeAll { $0.id == draft.id }
                            }
                        }
                }

                Button {
                    deductionDrafts.append(DeductionDraft(name: ""))
                } label: {
                    Label("控除項目を追加", systemImage: "plus.circle")
                }

                if let estimatedOtherDeduction {
                    LabeledContent {
                        Text(estimatedOtherDeduction >= 0 ? estimatedOtherDeduction.currencyText : "要確認")
                            .foregroundStyle(estimatedOtherDeduction >= 0 ? Color.secondary : Color.orange)
                    } label: {
                        Text("その他（推定）")
                    }
                    if estimatedOtherDeduction < 0 {
                        Label(
                            "控除内訳の合計が控除合計を超えています。原本と入力内容を確認してください。",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                if deductionAmountText.isEmpty, !otherDeductionAmountText.isEmpty {
                    currencyField("その他控除（従来項目）", text: $otherDeductionAmountText)
                }
            } header: {
                Text("控除の内訳")
            } footer: {
                Text("勤務先固有の控除項目は、この勤務先の次回入力とOCRにも引き継がれます。その他は控除合計から所得税・住民税・個別項目を引いた推定値です。")
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
                    .focused($isTextInputFocused)
            }

            Section("添付書類") {
                if let payRecord {
                    if linkedDocuments.isEmpty {
                        Text("この給与明細に紐づく書類はまだありません。")
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
                } else {
                    pendingDocumentSection
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EditorialStyle.pageBackground)
        .scrollDismissesKeyboard(.interactively)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isTextInputFocused = false
                }
        }
        .overlay {
            if isRunningOCR {
                ZStack {
                    Color(.systemBackground)
                        .opacity(0.80)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(appTheme.accentColor)

                        Text("給与明細を読み取り中")
                            .font(.headline)

                        Text("画像と文字を端末内で解析しています")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(EditorialStyle.divider, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(payRecord == nil ? "給与明細追加" : "給与明細編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    cancel()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(isRunningOCR)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    isTextInputFocused = false
                }
            }
        }
        .sheet(isPresented: $isAddingEmployer) {
            NavigationStack {
                EmployerFormView()
            }
        }
        .sheet(item: $activePayPeriodPicker) { picker in
            payPeriodPickerSheet(picker)
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $isPickingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handlePDFImport
        )
        .photosPicker(
            isPresented: $isPickingImage,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else {
                return
            }
            Task {
                await handlePhotoImport(newItem)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                handleCapturedImage(image)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if payRecord == nil,
               selectedEmployerID == nil,
               selectableEmployers.count == 1 {
                selectedEmployerID = selectableEmployers[0].persistentModelID
            }

            if let selectedEmployer {
                mergeDeductionTemplates(from: selectedEmployer)
            }

            guard payRecord == nil,
                  showsImportOptionsOnAppear,
                  !hasPresentedInitialImportOptions else {
                return
            }
            hasPresentedInitialImportOptions = true
            isShowingInitialImportOptions = true
        }
        .confirmationDialog(
            "給与明細を取り込む",
            isPresented: $isShowingInitialImportOptions,
            titleVisibility: .visible
        ) {
            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isShowingCamera = true
                } else {
                    showValidation("Simulatorではカメラを使用できません。写真またはPDFを選択してください。")
                }
            } label: {
                Label("カメラで撮影", systemImage: "camera")
            }

            Button {
                isPickingImage = true
            } label: {
                Label("写真から選択", systemImage: "photo")
            }

            Button {
                isPickingPDF = true
            } label: {
                Label("PDFを選択", systemImage: "doc")
            }

            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("給与明細を撮影または選択すると、支給年月や金額の入力候補を読み取ります。PDFはスクリーンショットにせず、そのまま選択できます。")
        }
        .alert("入力済みの内容を置き換えますか？", isPresented: $isShowingImportOverwriteWarning) {
            Button("キャンセル", role: .cancel) {}
            Button("書類を選ぶ") {
                showImportOptions()
            }
        } message: {
            Text("書類から読み取れた項目は、現在の入力内容を置き換えます。未入力の項目はそのままです。")
        }
        .interactiveDismissDisabled(payRecord == nil && pendingDocumentFileURL != nil)
        .alert("保存できません", isPresented: $isShowingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "入力内容を確認してください。")
        }
        .alert("計算結果を確認してください", isPresented: $isShowingSaveWarning) {
            Button("入力に戻る", role: .cancel) {}
            Button("このまま保存") {
                save(ignoringWarnings: true)
            }
        } message: {
            Text(saveWarningMessage ?? "金額の整合性を確認してください。")
        }
    }

    private func presentImportOptions() {
        isTextInputFocused = false

        if hasUserEnteredFormData {
            isShowingImportOverwriteWarning = true
            return
        }

        showImportOptions()
    }

    private func showImportOptions() {
        Task { @MainActor in
            await Task.yield()
            isShowingInitialImportOptions = true
        }
    }

    private var hasUserEnteredFormData: Bool {
        selectedEmployerID != initialEmployerID ||
            paymentYear != initialPaymentYear ||
            paymentMonth != initialPaymentMonth ||
            incomeCategory != initialIncomeCategory ||
            !grossAmountText.isEmpty ||
            !netAmountText.isEmpty ||
            !deductionAmountText.isEmpty ||
            !incomeTaxAmountText.isEmpty ||
            !residentTaxAmountText.isEmpty ||
            !otherDeductionAmountText.isEmpty ||
            deductionDrafts.contains { !$0.amountText.isEmpty } ||
            !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            pendingDocumentFileURL != nil
    }

    @ViewBuilder
    private var pendingDocumentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("保存時に、この給与明細へ給与明細または賞与明細として紐づけます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let pendingDocumentFileURL {
            NavigationLink {
                DocumentPreviewView(
                    title: pendingDocumentType.label,
                    fileType: pendingDocumentFileType,
                    fileURL: pendingDocumentFileURL
                )
            } label: {
                pendingDocumentSummaryRow
            }
        } else {
            pendingDocumentSummaryRow
        }

        Button {
            isPickingPDF = true
        } label: {
            Label("PDFを選択", systemImage: "doc")
        }
        .buttonStyle(.borderless)

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Label("画像を選択", systemImage: "photo")
        }
        .buttonStyle(.borderless)

        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                isShowingCamera = true
            } else {
                showValidation("この端末ではカメラを使用できません。画像選択またはPDF選択を使ってください。")
            }
        } label: {
            Label(pendingDocumentFileURL == nil ? "カメラで撮影" : "カメラで撮り直す", systemImage: "camera")
        }
        .buttonStyle(.borderless)
    }

    private var pendingDocumentSummaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: pendingDocumentFileType == .image ? "photo" : "doc")
                .foregroundStyle(pendingDocumentFileURL == nil ? Color.secondary : appTheme.accentColor)
                .frame(width: 24)

            Text(pendingDocumentOriginalFileName ?? "未選択")
                .foregroundStyle(pendingDocumentOriginalFileName == nil ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if let pendingDocumentFileSize {
                Text(byteCountText(pendingDocumentFileSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pendingDocumentType: DocumentType {
        incomeCategory == .bonus ? .bonusPayslip : .payslip
    }

    private func currencyField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            TextField("0", text: Binding(
                get: {
                    text.wrappedValue
                },
                set: { newValue in
                    text.wrappedValue = groupedAmountText(from: newValue)
                }
            ))
            .keyboardType(.numberPad)
            .focused($isTextInputFocused)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .frame(maxWidth: 180)
        }
    }

    private func payPeriodRow(
        title: String,
        value: String,
        picker: PayPeriodPicker
    ) -> some View {
        Button {
            isTextInputFocused = false
            activePayPeriodPicker = picker
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(value)
                        .foregroundStyle(appTheme.accentColor)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)、\(value)")
        .accessibilityHint("ダブルタップして選択")
    }

    @ViewBuilder
    private func payPeriodPickerSheet(_ picker: PayPeriodPicker) -> some View {
        NavigationStack {
            Group {
                switch picker {
                case .year:
                    Picker("支給年", selection: $paymentYear) {
                        ForEach(2000...2100, id: \.self) { year in
                            Text(verbatim: "\(year)年")
                                .tag(year)
                        }
                    }
                case .month:
                    Picker("支給月", selection: $paymentMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(verbatim: "\(month)月")
                                .tag(month)
                        }
                    }
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(picker.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        activePayPeriodPicker = nil
                    }
                }
            }
        }
    }

    private func deductionDraftRow(draft: Binding<DeductionDraft>) -> some View {
        HStack(spacing: 8) {
            TextField("項目名", text: draft.name)
                .textInputAutocapitalization(.never)
                .focused($isTextInputFocused)

            TextField("0", text: Binding(
                get: { draft.amountText.wrappedValue },
                set: { draft.amountText.wrappedValue = groupedAmountText(from: $0) }
            ))
            .keyboardType(.numberPad)
            .focused($isTextInputFocused)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .frame(maxWidth: 120)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
                .draggable(draft.wrappedValue.id.uuidString)
                .accessibilityLabel("長押しして並べ替え")
        }
    }

    private func moveDeductionDraft(sourceID: UUID, targetID: UUID) -> Bool {
        guard sourceID != targetID,
              let sourceIndex = deductionDrafts.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = deductionDrafts.firstIndex(where: { $0.id == targetID }) else {
            return false
        }

        withAnimation {
            let movedDraft = deductionDrafts.remove(at: sourceIndex)
            deductionDrafts.insert(movedDraft, at: min(targetIndex, deductionDrafts.count))
        }
        return true
    }

    private var estimatedOtherDeduction: Int? {
        guard let deductionAmount = parsedOptionalAmount(from: deductionAmountText) else {
            return nil
        }

        let incomeTax = parsedOptionalAmount(from: incomeTaxAmountText) ?? 0
        let residentTax = parsedOptionalAmount(from: residentTaxAmountText) ?? 0
        let customTotal = deductionDrafts.reduce(0) { result, draft in
            result + (parsedOptionalAmount(from: draft.amountText) ?? 0)
        }
        return deductionAmount - incomeTax - residentTax - customTotal
    }

    private func amountConsistencyWarnings(
        grossAmount: Int,
        netAmount: Int?,
        deductionAmount: Int?
    ) -> [String] {
        let itemizedTotal = (parsedOptionalAmount(from: incomeTaxAmountText) ?? 0) +
            (parsedOptionalAmount(from: residentTaxAmountText) ?? 0) +
            deductionDrafts.reduce(0) {
                $0 + (parsedOptionalAmount(from: $1.amountText) ?? 0)
            }
        return AmountConsistencyValidator.warnings(
            grossAmount: grossAmount,
            netAmount: netAmount,
            deductionAmount: deductionAmount,
            itemizedDeductionTotal: itemizedTotal
        )
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

    private func save(ignoringWarnings: Bool = false) {
        guard !isRunningOCR else {
            showValidation("書類の読み取りが完了してから保存してください。")
            return
        }

        guard let selectedEmployer else {
            showValidation("勤務先を選択してください。")
            return
        }

        guard let grossAmount = requiredAmount(from: grossAmountText) else {
            showValidation("額面は0以上の整数で入力してください。")
            return
        }

        guard let netAmount = optionalAmount(from: netAmountText) else {
            showValidation("手取りは0以上の整数で入力してください。")
            return
        }

        guard let deductionAmount = optionalAmount(from: deductionAmountText),
              let incomeTaxAmount = optionalAmount(from: incomeTaxAmountText),
              let residentTaxAmount = optionalAmount(from: residentTaxAmountText),
              optionalAmount(from: otherDeductionAmountText) != nil else {
            showValidation("任意の金額項目も、入力する場合は0以上の整数にしてください。")
            return
        }

        guard let validatedDeductionDrafts = validatedDeductionDrafts() else {
            return
        }

        if !ignoringWarnings {
            let warnings = amountConsistencyWarnings(
                grossAmount: grossAmount,
                netAmount: netAmount,
                deductionAmount: deductionAmount
            )
            if !warnings.isEmpty {
                saveWarningMessage = warnings.joined(separator: "\n\n") +
                    "\n\n入力内容に問題がなければ、このまま保存できます。"
                isShowingSaveWarning = true
                return
            }
        }

        let resolvedOtherDeductionAmount: Int?
        if deductionAmount != nil {
            resolvedOtherDeductionAmount = estimatedOtherDeduction.flatMap { $0 >= 0 ? $0 : nil }
        } else {
            resolvedOtherDeductionAmount = parsedOptionalAmount(from: otherDeductionAmountText)
        }

        let targetRecord: PayRecord

        if let payRecord {
            targetRecord = payRecord
            payRecord.employer = selectedEmployer
            payRecord.paymentYear = paymentYear
            payRecord.paymentMonth = paymentMonth
            payRecord.incomeCategory = incomeCategory
            payRecord.grossAmount = grossAmount
            payRecord.netAmount = netAmount
            payRecord.deductionAmount = deductionAmount
            payRecord.incomeTaxAmount = incomeTaxAmount
            payRecord.residentTaxAmount = residentTaxAmount
            payRecord.socialInsuranceAmount = nil
            payRecord.otherDeductionAmount = resolvedOtherDeductionAmount
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
                socialInsuranceAmount: nil,
                otherDeductionAmount: resolvedOtherDeductionAmount,
                memo: memo
            )
            modelContext.insert(newRecord)
            targetRecord = newRecord

            if let pendingDocumentLocalFilePath,
               let pendingDocumentStoredFileName,
               let pendingDocumentOriginalFileName,
               let pendingDocumentMimeType,
               let pendingDocumentFileSize {
                let document = DocumentAttachment(
                    employer: selectedEmployer,
                    payRecord: newRecord,
                    documentYear: paymentYear,
                    documentMonth: paymentMonth,
                    documentType: pendingDocumentType,
                    title: "",
                    attachmentFileType: pendingDocumentFileType,
                    localFilePath: pendingDocumentLocalFilePath,
                    originalFileName: pendingDocumentOriginalFileName,
                    storedFileName: pendingDocumentStoredFileName,
                    mimeType: pendingDocumentMimeType,
                    fileSize: pendingDocumentFileSize,
                    memo: ""
                )
                modelContext.insert(document)
            }
        }


        replaceDeductionItems(
            for: targetRecord,
            employer: selectedEmployer,
            drafts: validatedDeductionDrafts
        )

        do {
            try modelContext.save()
            pendingDocumentFileURL = nil
            dismiss()
        } catch {
            modelContext.rollback()
            showValidation("保存に失敗しました。もう一度お試しください。")
        }
    }

    private func validatedDeductionDrafts() -> [DeductionDraft]? {
        var result: [DeductionDraft] = []
        var names = Set<String>()

        for draft in deductionDrafts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasAmount = !normalizedAmountText(from: draft.amountText).isEmpty
            if !hasAmount {
                continue
            }
            guard !name.isEmpty else {
                showValidation("控除項目の名前を入力してください。")
                return nil
            }
            guard let amount = parsedOptionalAmount(from: draft.amountText) else {
                showValidation("「\(name)」の金額を0以上の整数で入力してください。")
                return nil
            }
            guard amount >= 0 else {
                showValidation("「\(name)」の金額を0以上の整数で入力してください。")
                return nil
            }

            let normalizedName = canonicalDeductionName(name)
            guard names.insert(normalizedName).inserted else {
                showValidation("同じ名前の控除項目が重複しています。")
                return nil
            }

            var validated = draft
            validated.name = name
            validated.amountText = amount.formText
            result.append(validated)
        }

        return result
    }

    private func replaceDeductionItems(
        for record: PayRecord,
        employer: Employer,
        drafts: [DeductionDraft]
    ) {
        record.deductionItems.forEach(modelContext.delete)

        for (index, draft) in drafts.enumerated() {
            guard let amount = parsedOptionalAmount(from: draft.amountText) else {
                continue
            }

            let template = deductionTemplate(for: draft, employer: employer)
            let item = PayRecordDeductionItem(
                payRecord: record,
                templateKey: template.templateKey,
                displayNameSnapshot: draft.name,
                amount: amount,
                sortOrder: index,
                inputSource: draft.inputSource
            )
            modelContext.insert(item)
        }
    }

    private func deductionTemplate(
        for draft: DeductionDraft,
        employer: Employer
    ) -> EmployerDeductionTemplate {
        let existingTemplate = employer.deductionTemplates.first { template in
            template.templateKey == draft.templateKey ||
                canonicalDeductionName(template.displayName) == canonicalDeductionName(draft.name)
        }

        if let existingTemplate {
            existingTemplate.displayName = draft.name
            existingTemplate.isActive = true
            existingTemplate.updatedAt = Date()
            return existingTemplate
        }

        let template = EmployerDeductionTemplate(
            employer: employer,
            displayName: draft.name,
            sortOrder: employer.deductionTemplates.count
        )
        modelContext.insert(template)
        return template
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                showValidation("PDFファイルを選択できませんでした。")
                return
            }
            do {
                try replacePendingDocument(with: DocumentFileStore.saveSecurityScopedFile(from: url, fileType: .pdf))
            } catch {
                showValidation("PDFの保存に失敗しました。もう一度お試しください。")
            }
        case .failure:
            showValidation("PDFの取込に失敗しました。")
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem) async {
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: sourceData),
                  let data = image.jpegData(compressionQuality: 0.95) else {
                await MainActor.run {
                    showValidation("画像を読み込めませんでした。")
                }
                return
            }

            let storedFile = try DocumentFileStore.saveData(data, originalFileName: "画像.jpg", fileType: .image)
            await MainActor.run {
                replacePendingDocument(with: storedFile)
                selectedPhotoItem = nil
            }
        } catch {
            await MainActor.run {
                showValidation("画像の保存に失敗しました。もう一度お試しください。")
            }
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            showValidation("撮影した画像を保存できませんでした。もう一度お試しください。")
            return
        }

        do {
            let storedFile = try DocumentFileStore.saveData(data, originalFileName: "撮影画像.jpg", fileType: .image)
            replacePendingDocument(with: storedFile)
        } catch {
            showValidation("撮影した画像の保存に失敗しました。もう一度お試しください。")
        }
    }

    private func replacePendingDocument(with storedFile: StoredDocumentFile) {
        let newFileURL = DocumentFileStore.fileURL(forLocalFilePath: storedFile.localFilePath)

        if pendingDocumentFileURL != newFileURL {
            do {
                try DocumentFileStore.deleteFile(at: pendingDocumentFileURL)
            } catch {
                do {
                    try DocumentFileStore.deleteFile(at: newFileURL)
                } catch {
                    showValidation("以前の添付ファイルと新しいファイルを整理できませんでした。アプリを再起動して、もう一度お試しください。")
                    return
                }
                showValidation("以前の添付ファイルを整理できないため、差し替えを中止しました。もう一度お試しください。")
                return
            }
        }

        pendingDocumentLocalFilePath = storedFile.localFilePath
        pendingDocumentStoredFileName = storedFile.storedFileName
        pendingDocumentOriginalFileName = storedFile.originalFileName
        pendingDocumentMimeType = storedFile.mimeType
        pendingDocumentFileSize = storedFile.fileSize
        pendingDocumentFileType = storedFile.fileType
        pendingDocumentFileURL = newFileURL
        validationMessage = nil
        startOCRIfNeeded(for: newFileURL, fileType: storedFile.fileType)
    }

    private func startOCRIfNeeded(for fileURL: URL?, fileType: AttachmentFileType) {
        guard payRecord == nil,
              let fileURL,
              fileType == .pdf || fileType == .image else {
            return
        }

        isRunningOCR = true
        ocrStatusMessage = nil

        Task { @MainActor in
            do {
                let initialEmployer = selectedEmployer
                var candidate = try await OCRExtractionService.extractPayRecordCandidate(
                    from: fileURL,
                    fileType: fileType,
                    deductionFieldSpecs: ocrDeductionFieldSpecs(for: initialEmployer)
                )

                if initialEmployer == nil,
                   let detectedEmployer = suggestedEmployer(for: candidate),
                   detectedEmployer.deductionTemplates.contains(where: \.isActive) {
                    candidate = try await OCRExtractionService.extractPayRecordCandidate(
                        from: fileURL,
                        fileType: fileType,
                        deductionFieldSpecs: ocrDeductionFieldSpecs(for: detectedEmployer)
                    )
                }

                guard pendingDocumentFileURL == fileURL else {
                    return
                }

                isRunningOCR = false
                if candidate.hasUsableValue {
                    applyOCRCandidate(candidate)
                } else {
                    ocrStatusMessage = "文字は読み取りましたが、支給年月や金額の候補を特定できませんでした。必要な項目は手入力してください。"
                }
            } catch {
                guard pendingDocumentFileURL == fileURL else {
                    return
                }

                isRunningOCR = false
                let reason = error.localizedDescription
                ocrStatusMessage = "書類を読み取れませんでした。\(reason)"
            }
        }
    }

    private func applyOCRCandidate(
        _ candidate: OCRPayRecordCandidate
    ) {
        var appliedFields = Set<OCRField>()

        if let employerID = suggestedEmployer(for: candidate)?.persistentModelID {
            selectedEmployerID = employerID
            appliedFields.insert(.employer)
        }

        if let paymentYear = candidate.paymentYear {
            self.paymentYear = paymentYear
            appliedFields.insert(.paymentDate)
        }

        if let paymentMonth = candidate.paymentMonth {
            self.paymentMonth = paymentMonth
            appliedFields.insert(.paymentDate)
        }

        if let grossAmount = candidate.grossAmount {
            grossAmountText = grossAmount.formText
            appliedFields.insert(.grossAmount)
        }

        if let netAmount = candidate.netAmount {
            netAmountText = netAmount.formText
            appliedFields.insert(.netAmount)
        }

        if let deductionAmount = candidate.deductionAmount {
            deductionAmountText = deductionAmount.formText
            appliedFields.insert(.deductionAmount)
        }

        if let incomeTaxAmount = candidate.incomeTaxAmount {
            incomeTaxAmountText = incomeTaxAmount.formText
            appliedFields.insert(.incomeTaxAmount)
        }

        if let residentTaxAmount = candidate.residentTaxAmount {
            residentTaxAmountText = residentTaxAmount.formText
            appliedFields.insert(.residentTaxAmount)
        }

        let customCandidates = candidate.customDeductionCandidates.filter {
            $0.amountCandidate.value > 0
        }
        for customCandidate in customCandidates {
            let amount = customCandidate.amountCandidate.value
            if let index = deductionDrafts.firstIndex(where: { draft in
                let matchesTemplate = customCandidate.templateKey.map {
                    draft.templateKey == $0
                } ?? false
                return matchesTemplate ||
                    canonicalDeductionName(draft.name) == canonicalDeductionName(customCandidate.displayName)
            }) {
                deductionDrafts[index].amountText = amount.formText
                deductionDrafts[index].inputSource = .ocr
            } else {
                deductionDrafts.append(
                    DeductionDraft(
                        templateKey: customCandidate.templateKey,
                        name: customCandidate.displayName,
                        amountText: amount.formText,
                        inputSource: .ocr
                    )
                )
            }
        }

        validationMessage = nil
        let appliedFieldText = appliedFieldLabels(
            for: appliedFields,
            customDeductionCount: customCandidates.count
        )
        let reviewPrefix = candidateContainsValuesRequiringReview(candidate) ? "要確認の候補を含みます。" : ""
        ocrStatusMessage = "書類から自動入力しました（\(appliedFieldText)）。\(reviewPrefix)原本と照合してから保存してください。"
    }

    private func candidateContainsValuesRequiringReview(
        _ candidate: OCRPayRecordCandidate
    ) -> Bool {
        if let dateCandidate = candidate.paymentDateCandidate,
           isLowConfidence(dateCandidate.confidence) {
            return true
        }

        let amountCandidates = [
            candidate.grossCandidate,
            candidate.netCandidate,
            candidate.deductionCandidate,
            candidate.incomeTaxCandidate,
            candidate.residentTaxCandidate
        ].compactMap { $0 }
        if amountCandidates.contains(where: {
            $0.isInferred || isLowConfidence($0.confidence)
        }) {
            return true
        }

        return candidate.customDeductionCandidates.contains {
            $0.amountCandidate.value > 0 &&
                ($0.amountCandidate.isInferred || isLowConfidence($0.amountCandidate.confidence))
        }
    }

    private func isLowConfidence(_ confidence: OCRCandidateConfidence) -> Bool {
        if case .low = confidence {
            return true
        }
        return false
    }

    private func appliedFieldLabels(
        for selectedFields: Set<OCRField>,
        customDeductionCount: Int
    ) -> String {
        let orderedFields: [(OCRField, String)] = [
            (.employer, "勤務先"),
            (.paymentDate, "支給年月"),
            (.grossAmount, "額面"),
            (.netAmount, "手取り"),
            (.deductionAmount, "控除合計"),
            (.incomeTaxAmount, "所得税"),
            (.residentTaxAmount, "住民税")
        ]
        let labels = orderedFields.compactMap { field, label in
            selectedFields.contains(field) ? label : nil
        }
        var resolvedLabels = labels
        if customDeductionCount > 0 {
            resolvedLabels.append("控除内訳\(customDeductionCount)件")
        }
        return resolvedLabels.joined(separator: "・")
    }

    private func suggestedEmployer(for candidate: OCRPayRecordCandidate) -> Employer? {
        let recognizedText = normalizedSearchText(candidate.recognizedText)

        let matchedEmployer = selectableEmployers
            .filter { employer in
                let employerName = normalizedSearchText(employer.name)
                return !employerName.isEmpty && recognizedText.contains(employerName)
            }
            .max { lhs, rhs in
                normalizedSearchText(lhs.name).count < normalizedSearchText(rhs.name).count
            }

        if let matchedEmployer {
            return matchedEmployer
        }

        return selectableEmployers.count == 1 ? selectableEmployers[0] : nil
    }

    private func normalizedSearchText(_ text: String) -> String {
        let halfWidthText = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidthText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .lowercased()
    }

    private func cancel() {
        if payRecord == nil {
            do {
                try DocumentFileStore.deleteFile(at: pendingDocumentFileURL)
            } catch {
                showValidation("取り込み中の添付ファイルを整理できませんでした。アプリを再起動して、もう一度キャンセルしてください。")
                return
            }
        }
        dismiss()
    }

    private func byteCountText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
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

    private func parsedOptionalAmount(from text: String) -> Int? {
        let normalizedText = normalizedAmountText(from: text)
        guard !normalizedText.isEmpty,
              let value = Int(normalizedText),
              value >= 0 else {
            return nil
        }
        return value
    }

    private func mergeDeductionTemplates(from employer: Employer) {
        let existingTemplateKeys = Set(deductionDrafts.compactMap(\.templateKey))
        let existingNames = Set(deductionDrafts.map { canonicalDeductionName($0.name) })
        let additions = employer.deductionTemplates
            .filter(\.isActive)
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            .filter {
                !existingTemplateKeys.contains($0.templateKey) &&
                    !existingNames.contains(canonicalDeductionName($0.displayName))
            }
            .map {
                DeductionDraft(templateKey: $0.templateKey, name: $0.displayName)
            }
        deductionDrafts.append(contentsOf: additions)
    }

    private func ocrDeductionFieldSpecs(for employer: Employer?) -> [OCRDeductionFieldSpec] {
        var specs: [OCRDeductionFieldSpec] = []
        var knownNames = Set<String>()
        let sourceEmployers = employer.map { [$0] } ?? []
        let templates = sourceEmployers
            .flatMap(\.deductionTemplates)
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        for template in templates where template.isActive {
            let normalizedName = canonicalDeductionName(template.displayName)
            guard knownNames.insert(normalizedName).inserted else {
                continue
            }
            specs.append(
                OCRDeductionFieldSpec(
                    id: template.templateKey,
                    templateKey: template.templateKey,
                    displayName: template.displayName,
                    keywords: template.ocrKeywords,
                    sortPriority: template.sortOrder
                )
            )
        }

        let commonNames = [
            "短期掛金", "健康保険", "介護保険", "厚生年金", "長期掛金",
            "雇用保険", "共済掛金", "組合費", "財形", "社宅費"
        ]
        specs.append(contentsOf: commonNames.enumerated().compactMap { index, name in
            guard knownNames.insert(canonicalDeductionName(name)).inserted else {
                return nil
            }
            return OCRDeductionFieldSpec(
                id: UUID(),
                templateKey: nil,
                displayName: name,
                keywords: [name],
                sortPriority: 10_000 + index
            )
        })
        return specs
    }

    private func canonicalDeductionName(_ name: String) -> String {
        DeductionNameNormalizer.canonicalKey(name)
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

    var currencyText: String {
        "\(formText)円"
    }
}
