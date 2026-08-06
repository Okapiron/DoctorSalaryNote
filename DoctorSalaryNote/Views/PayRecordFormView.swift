import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct PendingOCRApplication {
    let candidate: OCRPayRecordCandidate
    let selectedFields: Set<OCRField>
    let selectedCustomDeductionIDs: Set<UUID>
    let employerID: PersistentIdentifier?
}

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
    private let showsImportOptionsOnAppear: Bool

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
    @State private var availableOCRCandidate: OCRPayRecordCandidate?
    @State private var ocrCandidateForReview: OCRPayRecordCandidate?
    @State private var pendingOCRApplication: PendingOCRApplication?

    init(
        payRecord: PayRecord? = nil,
        initialEmployer: Employer? = nil,
        showsImportOptionsOnAppear: Bool = false
    ) {
        self.payRecord = payRecord
        self.initialEmployer = initialEmployer
        self.showsImportOptionsOnAppear = showsImportOptionsOnAppear
        let resolvedEmployer = payRecord?.employer ?? initialEmployer
        _selectedEmployerID = State(initialValue: resolvedEmployer?.persistentModelID)
        _paymentYear = State(initialValue: payRecord?.paymentYear ?? Calendar.current.component(.year, from: Date()))
        _paymentMonth = State(initialValue: payRecord?.paymentMonth ?? Calendar.current.component(.month, from: Date()))
        _incomeCategory = State(initialValue: payRecord?.incomeCategory ?? initialEmployer?.defaultIncomeCategory ?? .partTimeSalary)
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
                currencyField("手取り", text: $netAmountText)
                currencyField("控除合計", text: $deductionAmountText)
                currencyField("所得税", text: $incomeTaxAmountText)
                currencyField("住民税", text: $residentTaxAmountText)

                ForEach($deductionDrafts) { $draft in
                    deductionDraftRow(draft: $draft)
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
                Text("金額")
            } footer: {
                Text("勤務先固有の控除項目は、この勤務先の次回入力とOCRにも引き継がれます。その他は控除合計から所得税・住民税・個別項目を引いた推定値です。")
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
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
        .navigationTitle(payRecord == nil ? "給与明細追加" : "給与明細編集")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    cancel()
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
        .sheet(item: $ocrCandidateForReview, onDismiss: applyPendingOCRApplication) { candidate in
            OCRCandidateReviewView(
                candidate: candidate,
                employers: selectableEmployers,
                suggestedEmployerID: suggestedEmployer(for: candidate)?.persistentModelID,
                fileURL: pendingDocumentFileURL,
                fileType: pendingDocumentFileType,
                fileTitle: pendingDocumentOriginalFileName ?? pendingDocumentType.label,
                onCancel: {
                    pendingOCRApplication = nil
                    ocrCandidateForReview = nil
                },
                onApply: { selectedFields, selectedCustomDeductionIDs, employerID in
                    pendingOCRApplication = PendingOCRApplication(
                        candidate: candidate,
                        selectedFields: selectedFields,
                        selectedCustomDeductionIDs: selectedCustomDeductionIDs,
                        employerID: employerID
                    )
                    ocrCandidateForReview = nil
                }
            )
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
            "今月の記録を取り込む",
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

            Button("手入力で始める") {}
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("給与明細を撮影または選択すると、支給年月や金額の入力候補を読み取ります。PDFはスクリーンショットにせず、そのまま選択できます。")
        }
        .interactiveDismissDisabled(payRecord == nil && pendingDocumentFileURL != nil)
        .alert("保存できません", isPresented: $isShowingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "入力内容を確認してください。")
        }
    }

    @ViewBuilder
    private var pendingDocumentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("保存時に、この給与明細へ給与明細または賞与明細として紐づけます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isRunningOCR {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("書類から入力候補を読み取っています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let ocrStatusMessage {
                Text(ocrStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let availableOCRCandidate {
                Button {
                    presentOCRCandidate(availableOCRCandidate)
                } label: {
                    Label("読み取り結果を確認", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
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
                .foregroundStyle(pendingDocumentFileURL == nil ? Color.secondary : Color.cyan)
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
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .frame(maxWidth: 180)
        }
    }

    private func deductionDraftRow(draft: Binding<DeductionDraft>) -> some View {
        HStack(spacing: 8) {
            TextField("項目名", text: draft.name)
                .textInputAutocapitalization(.never)

            TextField("0", text: Binding(
                get: { draft.amountText.wrappedValue },
                set: { draft.amountText.wrappedValue = groupedAmountText(from: $0) }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .frame(maxWidth: 120)

            Button(role: .destructive) {
                deductionDrafts.removeAll { $0.id == draft.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("控除項目を削除")
        }
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
            dismiss()
        } catch {
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

            let normalizedName = normalizedSearchText(name)
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
                normalizedSearchText(template.displayName) == normalizedSearchText(draft.name)
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
            DocumentFileStore.deleteFile(at: pendingDocumentFileURL)
        }

        pendingDocumentLocalFilePath = storedFile.localFilePath
        pendingDocumentStoredFileName = storedFile.storedFileName
        pendingDocumentOriginalFileName = storedFile.originalFileName
        pendingDocumentMimeType = storedFile.mimeType
        pendingDocumentFileSize = storedFile.fileSize
        pendingDocumentFileType = storedFile.fileType
        pendingDocumentFileURL = newFileURL
        availableOCRCandidate = nil
        ocrCandidateForReview = nil
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

        Task {
            do {
                let candidate = try await OCRExtractionService.extractPayRecordCandidate(
                    from: fileURL,
                    fileType: fileType,
                    deductionFieldSpecs: ocrDeductionFieldSpecs
                )
                await MainActor.run {
                    guard pendingDocumentFileURL == fileURL else {
                        return
                    }

                    isRunningOCR = false
                    if candidate.hasUsableValue {
                        availableOCRCandidate = candidate
                        ocrStatusMessage = "入力候補を見つけました。「読み取り結果を確認」からフォームへ反映できます。"

                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            guard pendingDocumentFileURL == fileURL,
                                  availableOCRCandidate?.id == candidate.id,
                                  ocrCandidateForReview == nil else {
                                return
                            }
                            presentOCRCandidate(candidate)
                        }
                    } else {
                        ocrStatusMessage = "文字は読み取りましたが、支給年月や金額の候補を特定できませんでした。必要な項目は手入力してください。"
                    }
                }
            } catch {
                await MainActor.run {
                    guard pendingDocumentFileURL == fileURL else {
                        return
                    }

                    isRunningOCR = false
                    let reason = error.localizedDescription
                    ocrStatusMessage = "書類を読み取れませんでした。\(reason)"
                }
            }
        }
    }

    private func applyOCRCandidate(
        _ candidate: OCRPayRecordCandidate,
        selectedFields: Set<OCRField>,
        selectedCustomDeductionIDs: Set<UUID>,
        employerID: PersistentIdentifier?
    ) {
        if selectedFields.contains(.employer),
           let employerID {
            selectedEmployerID = employerID
        }

        if selectedFields.contains(.paymentDate),
           let paymentYear = candidate.paymentYear {
            self.paymentYear = paymentYear
        }

        if selectedFields.contains(.paymentDate),
           let paymentMonth = candidate.paymentMonth {
            self.paymentMonth = paymentMonth
        }

        if selectedFields.contains(.grossAmount),
           let grossAmount = candidate.grossAmount {
            grossAmountText = grossAmount.formText
        }

        if selectedFields.contains(.netAmount),
           let netAmount = candidate.netAmount {
            netAmountText = netAmount.formText
        }

        if selectedFields.contains(.deductionAmount),
           let deductionAmount = candidate.deductionAmount {
            deductionAmountText = deductionAmount.formText
        }

        if selectedFields.contains(.incomeTaxAmount),
           let incomeTaxAmount = candidate.incomeTaxAmount {
            incomeTaxAmountText = incomeTaxAmount.formText
        }

        if selectedFields.contains(.residentTaxAmount),
           let residentTaxAmount = candidate.residentTaxAmount {
            residentTaxAmountText = residentTaxAmount.formText
        }

        for customCandidate in candidate.customDeductionCandidates
            where selectedCustomDeductionIDs.contains(customCandidate.id) {
            if let index = deductionDrafts.firstIndex(where: { draft in
                draft.templateKey == customCandidate.templateKey ||
                    normalizedSearchText(draft.name) == normalizedSearchText(customCandidate.displayName)
            }) {
                deductionDrafts[index].amountText = customCandidate.amountCandidate.value.formText
                deductionDrafts[index].inputSource = .ocr
            } else {
                deductionDrafts.append(
                    DeductionDraft(
                        templateKey: customCandidate.templateKey,
                        name: customCandidate.displayName,
                        amountText: customCandidate.amountCandidate.value.formText,
                        inputSource: .ocr
                    )
                )
            }
        }

        validationMessage = nil
        let appliedFields = appliedFieldLabels(
            for: selectedFields,
            customDeductionCount: selectedCustomDeductionIDs.count
        )
        ocrStatusMessage = "フォームに反映しました（\(appliedFields)）。内容を照合し、右上の「保存」を押してください。"
    }

    private func applyPendingOCRApplication() {
        guard let application = pendingOCRApplication else {
            return
        }

        applyOCRCandidate(
            application.candidate,
            selectedFields: application.selectedFields,
            selectedCustomDeductionIDs: application.selectedCustomDeductionIDs,
            employerID: application.employerID
        )
        availableOCRCandidate = nil
        pendingOCRApplication = nil
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

    private func presentOCRCandidate(_ candidate: OCRPayRecordCandidate) {
        ocrCandidateForReview = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard availableOCRCandidate?.id == candidate.id else {
                return
            }
            ocrCandidateForReview = candidate
        }
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
            DocumentFileStore.deleteFile(at: pendingDocumentFileURL)
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
        let existingNames = Set(deductionDrafts.map { normalizedSearchText($0.name) })
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
                    !existingNames.contains(normalizedSearchText($0.displayName))
            }
            .map {
                DeductionDraft(templateKey: $0.templateKey, name: $0.displayName)
            }
        deductionDrafts.append(contentsOf: additions)
    }

    private var ocrDeductionFieldSpecs: [OCRDeductionFieldSpec] {
        var specs: [OCRDeductionFieldSpec] = []
        var knownNames = Set<String>()
        let sourceEmployers = selectedEmployer.map { [$0] } ?? employers
        let templates = sourceEmployers.flatMap(\.deductionTemplates)
        for template in templates where template.isActive {
            let normalizedName = normalizedSearchText(template.displayName)
            guard knownNames.insert(normalizedName).inserted else {
                continue
            }
            specs.append(
                OCRDeductionFieldSpec(
                    id: template.templateKey,
                    templateKey: template.templateKey,
                    displayName: template.displayName,
                    keywords: template.ocrKeywords
                )
            )
        }

        let commonNames = [
            "短期掛金", "健康保険", "介護保険", "厚生年金", "長期掛金",
            "雇用保険", "共済掛金", "組合費", "財形", "社宅費"
        ]
        specs.append(contentsOf: commonNames.compactMap { name in
            guard !knownNames.contains(normalizedSearchText(name)) else {
                return nil
            }
            return OCRDeductionFieldSpec(
                id: UUID(),
                templateKey: nil,
                displayName: name,
                keywords: [name]
            )
        })
        return specs
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

private struct OCRCandidateReviewView: View {
    let candidate: OCRPayRecordCandidate
    let employers: [Employer]
    let fileURL: URL?
    let fileType: AttachmentFileType
    let fileTitle: String
    let onCancel: () -> Void
    let onApply: (Set<OCRField>, Set<UUID>, PersistentIdentifier?) -> Void

    @State private var selectedEmployerID: PersistentIdentifier?
    @State private var usePaymentDate: Bool
    @State private var useGrossAmount: Bool
    @State private var useNetAmount: Bool
    @State private var useDeductionAmount: Bool
    @State private var useIncomeTaxAmount: Bool
    @State private var useResidentTaxAmount: Bool
    @State private var selectedCustomDeductionIDs: Set<UUID>

    init(
        candidate: OCRPayRecordCandidate,
        employers: [Employer],
        suggestedEmployerID: PersistentIdentifier?,
        fileURL: URL?,
        fileType: AttachmentFileType,
        fileTitle: String,
        onCancel: @escaping () -> Void,
        onApply: @escaping (Set<OCRField>, Set<UUID>, PersistentIdentifier?) -> Void
    ) {
        self.candidate = candidate
        self.employers = employers
        self.fileURL = fileURL
        self.fileType = fileType
        self.fileTitle = fileTitle
        self.onCancel = onCancel
        self.onApply = onApply
        _selectedEmployerID = State(initialValue: suggestedEmployerID)
        _usePaymentDate = State(
            initialValue: candidate.paymentDateCandidate?.isInitiallySelected ?? false
        )
        _useGrossAmount = State(
            initialValue: candidate.grossCandidate?.isInitiallySelected ?? false
        )
        _useNetAmount = State(
            initialValue: candidate.netCandidate?.isInitiallySelected ?? false
        )
        _useDeductionAmount = State(
            initialValue: candidate.deductionCandidate?.isInitiallySelected ?? false
        )
        _useIncomeTaxAmount = State(
            initialValue: candidate.incomeTaxCandidate?.isInitiallySelected ?? false
        )
        _useResidentTaxAmount = State(
            initialValue: candidate.residentTaxCandidate?.isInitiallySelected ?? false
        )
        _selectedCustomDeductionIDs = State(
            initialValue: Set(
                candidate.customDeductionCandidates
                    .filter { $0.amountCandidate.isInitiallySelected }
                    .map(\.id)
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("書類から読み取った入力候補です。使う項目だけを選び、原本と照合してから反映してください。確信度が低い候補は「要確認」と表示します。推定値は初期選択していません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let fileURL {
                    Section("原本") {
                        NavigationLink {
                            DocumentPreviewView(
                                title: fileTitle,
                                fileType: fileType,
                                fileURL: fileURL
                            )
                        } label: {
                            Label("書類を確認", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }

                Section("勤務先") {
                    if employers.isEmpty {
                        Text("勤務先が未登録です。候補を反映した後、勤務先を追加してください。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("勤務先（必須）", selection: $selectedEmployerID) {
                            Text("後で選択").tag(Optional<PersistentIdentifier>.none)
                            ForEach(employers) { employer in
                                Text(employer.name).tag(Optional(employer.persistentModelID))
                            }
                        }
                    }
                }

                Section("読み取り候補") {
                    candidateSelectionRow(
                        title: "支給年月",
                        value: paymentDateText,
                        confidenceText: confidenceText(candidate.paymentDateCandidate?.confidence),
                        sourceText: candidate.paymentDateCandidate?.sourceText,
                        isSelected: $usePaymentDate
                    )
                    candidateSelectionRow(
                        title: "総支給額（額面）",
                        value: amountText(candidate.grossAmount),
                        confidenceText: confidenceText(candidate.grossCandidate),
                        sourceText: candidate.grossCandidate?.sourceText,
                        isSelected: $useGrossAmount
                    )
                    candidateSelectionRow(
                        title: "振込額（手取り）",
                        value: amountText(candidate.netAmount),
                        confidenceText: confidenceText(candidate.netCandidate),
                        sourceText: candidate.netCandidate?.sourceText,
                        isSelected: $useNetAmount
                    )
                    candidateSelectionRow(
                        title: "控除合計",
                        value: amountText(candidate.deductionAmount),
                        confidenceText: confidenceText(candidate.deductionCandidate),
                        sourceText: candidate.deductionCandidate?.sourceText,
                        isSelected: $useDeductionAmount
                    )
                    candidateSelectionRow(
                        title: "所得税",
                        value: amountText(candidate.incomeTaxAmount),
                        confidenceText: confidenceText(candidate.incomeTaxCandidate),
                        sourceText: candidate.incomeTaxCandidate?.sourceText,
                        isSelected: $useIncomeTaxAmount
                    )
                    candidateSelectionRow(
                        title: "住民税",
                        value: amountText(candidate.residentTaxAmount),
                        confidenceText: confidenceText(candidate.residentTaxCandidate),
                        sourceText: candidate.residentTaxCandidate?.sourceText,
                        isSelected: $useResidentTaxAmount
                    )
                }

                if !candidate.customDeductionCandidates.isEmpty {
                    Section {
                        ForEach(candidate.customDeductionCandidates) { customCandidate in
                            candidateSelectionRow(
                                title: customCandidate.displayName,
                                value: amountText(customCandidate.amountCandidate.value),
                                confidenceText: confidenceText(customCandidate.amountCandidate),
                                sourceText: customCandidate.amountCandidate.sourceText,
                                isSelected: Binding(
                                    get: { selectedCustomDeductionIDs.contains(customCandidate.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedCustomDeductionIDs.insert(customCandidate.id)
                                        } else {
                                            selectedCustomDeductionIDs.remove(customCandidate.id)
                                        }
                                    }
                                )
                            )
                        }
                    } header: {
                        Text("勤務先固有の控除")
                    } footer: {
                        Text("反映して保存した項目は勤務先ごとに記憶し、次回のOCR候補に使います。")
                    }
                }

                if candidate.deductionCandidate?.isInferred == true {
                    Section {
                        Label(
                            "控除合計は、総支給額と振込額の差から推定した候補です。原本に控除合計の記載がある場合は、その金額を優先してください。",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("読み取り結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("使わない", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("フォームに反映") {
                        onApply(selectedFields, selectedCustomDeductionIDs, selectedEmployerID)
                    }
                    .disabled(selectedFields.isEmpty && selectedCustomDeductionIDs.isEmpty)
                }
            }
        }
    }

    private var selectedFields: Set<OCRField> {
        var fields = Set<OCRField>()
        if selectedEmployerID != nil {
            fields.insert(.employer)
        }
        if usePaymentDate, candidate.paymentDateCandidate != nil {
            fields.insert(.paymentDate)
        }
        if useGrossAmount, candidate.grossCandidate != nil {
            fields.insert(.grossAmount)
        }
        if useNetAmount, candidate.netCandidate != nil {
            fields.insert(.netAmount)
        }
        if useDeductionAmount, candidate.deductionCandidate != nil {
            fields.insert(.deductionAmount)
        }
        if useIncomeTaxAmount, candidate.incomeTaxCandidate != nil {
            fields.insert(.incomeTaxAmount)
        }
        if useResidentTaxAmount, candidate.residentTaxCandidate != nil {
            fields.insert(.residentTaxAmount)
        }
        return fields
    }

    private var paymentDateText: String? {
        guard let year = candidate.paymentYear,
              let month = candidate.paymentMonth else {
            return nil
        }
        return "\(year)年\(month)月"
    }

    @ViewBuilder
    private func candidateSelectionRow(
        title: String,
        value: String?,
        confidenceText: String?,
        sourceText: String?,
        isSelected: Binding<Bool>
    ) -> some View {
        if value == nil {
            HStack {
                Text(title)
                Spacer()
                Text("候補なし")
                    .foregroundStyle(.secondary)
            }
        } else {
            Toggle(isOn: isSelected) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let confidenceText {
                            Text(confidenceText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(confidenceText.contains("要確認") ? .orange : .cyan)
                        }
                    }

                    Text(value ?? "")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()

                    if let sourceText, !sourceText.isEmpty {
                        Text("根拠: \(sourceText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func confidenceText(_ confidence: OCRCandidateConfidence?) -> String? {
        guard let confidence, case .low = confidence else {
            return nil
        }
        return "要確認"
    }

    private func confidenceText(_ candidate: OCRAmountCandidate?) -> String? {
        guard let candidate else {
            return nil
        }
        if candidate.isInferred {
            return "推定・要確認"
        }
        guard case .low = candidate.confidence else {
            return nil
        }
        return "要確認"
    }

    private func amountText(_ amount: Int?) -> String? {
        guard let amount else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedAmount = formatter.string(from: NSNumber(value: amount)) ?? String(amount)
        return "\(formattedAmount)円"
    }
}
