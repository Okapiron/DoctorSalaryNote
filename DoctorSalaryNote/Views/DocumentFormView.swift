import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DocumentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    private let document: DocumentAttachment?
    private let linkedPayRecord: PayRecord?

    @State private var documentType: DocumentType
    @State private var documentYear: Int
    @State private var selectedEmployerID: PersistentIdentifier?
    @State private var selectedPayRecordID: PersistentIdentifier?
    @State private var memo: String
    @State private var localFilePath: String?
    @State private var storedFileName: String?
    @State private var originalFileName: String?
    @State private var mimeType: String?
    @State private var fileSize: Int?
    @State private var attachmentFileType: AttachmentFileType
    @State private var validationMessage: String?
    @State private var isPickingPDF = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    init(document: DocumentAttachment? = nil, linkedPayRecord: PayRecord? = nil, initialYear: Int = Calendar.current.component(.year, from: Date())) {
        self.document = document
        self.linkedPayRecord = linkedPayRecord
        let initialPayRecord = document?.payRecord ?? linkedPayRecord
        let initialType = document?.documentType ?? (linkedPayRecord?.incomeCategory == .bonus ? .bonusPayslip : .payslip)

        _documentType = State(initialValue: initialType)
        _documentYear = State(initialValue: document?.documentYear ?? initialPayRecord?.paymentYear ?? initialYear)
        _selectedEmployerID = State(initialValue: document?.employer?.persistentModelID ?? initialPayRecord?.employer?.persistentModelID)
        _selectedPayRecordID = State(initialValue: initialPayRecord?.persistentModelID)
        _memo = State(initialValue: document?.memo ?? "")
        _localFilePath = State(initialValue: document?.localFilePath)
        _storedFileName = State(initialValue: document?.storedFileName)
        _originalFileName = State(initialValue: document?.originalFileName)
        _mimeType = State(initialValue: document?.mimeType)
        _fileSize = State(initialValue: document?.fileSize)
        _attachmentFileType = State(initialValue: document?.attachmentFileType ?? .other)
    }

    private var selectedEmployer: Employer? {
        employers.first { $0.persistentModelID == selectedEmployerID }
    }

    private var selectedPayRecord: PayRecord? {
        payRecords.first { $0.persistentModelID == selectedPayRecordID }
    }

    private var payRecordCandidates: [PayRecord] {
        payRecords.filter { record in
            if documentType == .bonusPayslip {
                return record.incomeCategory == .bonus
            }
            if documentType == .payslip {
                return record.incomeCategory != .bonus
            }
            return true
        }
    }

    private var canPreview: Bool {
        localFilePath != nil || storedFileName != nil
    }

    var body: some View {
        Form {
            Section("書類情報") {
                Picker("書類種別", selection: $documentType) {
                    ForEach(DocumentType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .onChange(of: documentType) { _, _ in
                    validationMessage = nil
                    applyPayRecordSelectionIfNeeded()
                }

                if documentType.requiresPayRecord {
                    Picker("紐づける明細（必須）", selection: $selectedPayRecordID) {
                        Text("選択してください").tag(Optional<PersistentIdentifier>.none)
                        ForEach(payRecordCandidates) { record in
                            Text(payRecordLabel(record)).tag(Optional(record.persistentModelID))
                        }
                    }
                    .onChange(of: selectedPayRecordID) { _, _ in
                        applyPayRecordSelectionIfNeeded()
                    }
                } else {
                    Stepper(value: $documentYear, in: 2000...2100) {
                        Text("対象年 \(documentYear)年")
                    }

                    Picker(documentType.requiresEmployer ? "勤務先（必須）" : "勤務先", selection: $selectedEmployerID) {
                        Text(documentType.requiresEmployer ? "選択してください" : "未設定").tag(Optional<PersistentIdentifier>.none)
                        ForEach(employers) { employer in
                            Text(employer.name).tag(Optional(employer.persistentModelID))
                        }
                    }
                }
            }

            Section("ファイル") {
                HStack {
                    Text(originalFileName ?? "未選択")
                        .foregroundStyle(originalFileName == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    if let fileSize {
                        Text(byteCountText(fileSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    isPickingPDF = true
                } label: {
                    Label("PDFを選択", systemImage: "doc")
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("画像を選択", systemImage: "photo")
                }

                if canPreview {
                    NavigationLink {
                        DocumentPreviewView(
                            title: documentType.label,
                            fileType: attachmentFileType,
                            fileURL: previewFileURL
                        )
                    } label: {
                        Label("プレビュー", systemImage: "eye")
                    }
                }
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
        .navigationTitle(document == nil ? "書類追加" : "書類編集")
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
        .fileImporter(
            isPresented: $isPickingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handlePDFImport
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else {
                return
            }
            Task {
                await handlePhotoImport(newItem)
            }
        }
    }

    private var previewFileURL: URL? {
        if let localFilePath {
            return URL(fileURLWithPath: localFilePath)
        }

        guard let document else {
            return nil
        }

        return DocumentFileStore.fileURL(for: document)
    }

    private func applyPayRecordSelectionIfNeeded() {
        guard documentType.requiresPayRecord, let selectedPayRecord else {
            return
        }

        documentYear = selectedPayRecord.paymentYear
        selectedEmployerID = selectedPayRecord.employer?.persistentModelID
    }

    private func save() {
        validationMessage = nil

        var resolvedEmployer = selectedEmployer
        var resolvedPayRecord: PayRecord?
        var resolvedYear = documentYear

        if documentType.requiresPayRecord {
            guard let selectedPayRecord else {
                validationMessage = "給与明細・賞与明細は、紐づける明細を選択してください。"
                return
            }
            resolvedPayRecord = selectedPayRecord
            resolvedEmployer = selectedPayRecord.employer
            resolvedYear = selectedPayRecord.paymentYear
        } else if documentType.requiresEmployer {
            guard resolvedEmployer != nil else {
                validationMessage = "\(documentType.label)は勤務先を選択してください。"
                return
            }
        }

        guard localFilePath != nil || storedFileName != nil else {
            validationMessage = "PDFまたは画像ファイルを選択してください。"
            return
        }

        if let document {
            document.documentType = documentType
            document.documentYear = resolvedYear
            document.employer = resolvedEmployer
            document.payRecord = resolvedPayRecord
            document.attachmentFileType = attachmentFileType
            document.localFilePath = localFilePath
            document.originalFileName = originalFileName
            document.storedFileName = storedFileName
            document.mimeType = mimeType
            document.fileSize = fileSize
            document.memo = memo
            document.updatedAt = Date()
        } else {
            let newDocument = DocumentAttachment(
                employer: resolvedEmployer,
                payRecord: resolvedPayRecord,
                documentYear: resolvedYear,
                documentType: documentType,
                title: "",
                attachmentFileType: attachmentFileType,
                localFilePath: localFilePath,
                originalFileName: originalFileName,
                storedFileName: storedFileName,
                mimeType: mimeType,
                fileSize: fileSize,
                memo: memo
            )
            modelContext.insert(newDocument)
        }

        try? modelContext.save()
        dismiss()
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                validationMessage = "PDFファイルを選択できませんでした。"
                return
            }
            do {
                try replaceFile(with: DocumentFileStore.saveSecurityScopedFile(from: url, fileType: .pdf))
            } catch {
                validationMessage = "PDFの保存に失敗しました。もう一度お試しください。"
            }
        case .failure:
            validationMessage = "PDFの取込に失敗しました。"
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    validationMessage = "画像を読み込めませんでした。"
                }
                return
            }

            let storedFile = try DocumentFileStore.saveData(data, originalFileName: "画像.jpg", fileType: .image)
            await MainActor.run {
                replaceFile(with: storedFile)
                selectedPhotoItem = nil
            }
        } catch {
            await MainActor.run {
                validationMessage = "画像の保存に失敗しました。もう一度お試しください。"
            }
        }
    }

    private func replaceFile(with storedFile: StoredDocumentFile) {
        localFilePath = storedFile.localFilePath
        storedFileName = storedFile.storedFileName
        originalFileName = storedFile.originalFileName
        mimeType = storedFile.mimeType
        fileSize = storedFile.fileSize
        attachmentFileType = storedFile.fileType
        validationMessage = nil
    }

    private func payRecordLabel(_ record: PayRecord) -> String {
        let employerName = record.employer?.name ?? "勤務先未設定"
        return "\(record.paymentYear)年\(record.paymentMonth)月 \(employerName) \(record.incomeCategory.label)"
    }

    private func byteCountText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
