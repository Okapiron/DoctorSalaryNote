import PhotosUI
import SwiftData
import SwiftUI
import UIKit
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
    @State private var isShowingValidation = false
    @State private var isPickingPDF = false
    @State private var isShowingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingOldFileURLToDelete: URL?
    @State private var pendingNewFileURL: URL?

    init(
        document: DocumentAttachment? = nil,
        linkedPayRecord: PayRecord? = nil,
        initialYear: Int = Calendar.current.component(.year, from: Date()),
        initialDocumentType: DocumentType? = nil,
        initialEmployer: Employer? = nil
    ) {
        self.document = document
        self.linkedPayRecord = linkedPayRecord
        let initialPayRecord = document?.payRecord ?? linkedPayRecord
        let initialType = document?.documentType ?? initialDocumentType ?? (linkedPayRecord?.incomeCategory == .bonus ? .bonusPayslip : .payslip)

        _documentType = State(initialValue: initialType)
        _documentYear = State(initialValue: document?.documentYear ?? initialPayRecord?.paymentYear ?? initialYear)
        _selectedEmployerID = State(initialValue: document?.employer?.persistentModelID ?? initialPayRecord?.employer?.persistentModelID ?? initialEmployer?.persistentModelID)
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
                    if payRecordCandidates.isEmpty {
                        Text("給与明細・賞与明細の書類を添付するには、先に給与タブで対象の給与明細を登録してください。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Picker("紐づける給与明細（必須）", selection: $selectedPayRecordID) {
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
                        Text(verbatim: "対象年 \(documentYear)年")
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
                if canPreview {
                    NavigationLink {
                        DocumentPreviewView(
                            title: documentType.label,
                            fileType: attachmentFileType,
                            fileURL: previewFileURL
                        )
                    } label: {
                        fileSummaryRow
                    }
                } else {
                    fileSummaryRow
                }

                Button {
                    isPickingPDF = true
                } label: {
                    Label("PDFを選択", systemImage: "doc")
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("画像を選択", systemImage: "photo")
                }

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                    } else {
                        showValidation("この端末ではカメラを使用できません。画像選択またはPDF選択を使ってください。")
                    }
                } label: {
                    Label(canPreview ? "カメラで撮り直す" : "カメラで撮影", systemImage: "camera")
                }
            }

            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 120)
            }
            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(document == nil ? "書類追加" : "書類編集")
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
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                handleCapturedImage(image)
            }
            .ignoresSafeArea()
        }
        .alert("保存できません", isPresented: $isShowingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "入力内容を確認してください。")
        }
    }

    private var previewFileURL: URL? {
        if let localFilePath {
            return DocumentFileStore.fileURL(forLocalFilePath: localFilePath)
        }

        guard let document else {
            return nil
        }

        return DocumentFileStore.fileURL(for: document)
    }

    private var fileSummaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: attachmentFileType == .image ? "photo" : "doc")
                .foregroundStyle(canPreview ? Color.cyan : Color.secondary)
                .frame(width: 24)

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
                showValidation("給与明細・賞与明細は、紐づける給与明細を選択してください。未登録の場合は先に給与明細を追加してください。")
                return
            }
            resolvedPayRecord = selectedPayRecord
            resolvedEmployer = selectedPayRecord.employer
            resolvedYear = selectedPayRecord.paymentYear
        } else if documentType.requiresEmployer {
            guard resolvedEmployer != nil else {
                showValidation("\(documentType.label)は勤務先を選択してください。")
                return
            }
        }

        guard localFilePath != nil || storedFileName != nil else {
            showValidation("PDFまたは画像ファイルを選択してください。")
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

        do {
            try modelContext.save()
            DocumentFileStore.deleteFile(at: pendingOldFileURLToDelete)
            dismiss()
        } catch {
            showValidation("書類の保存に失敗しました。もう一度お試しください。")
        }
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                showValidation("PDFファイルを選択できませんでした。")
                return
            }
            do {
                try replaceFile(with: DocumentFileStore.saveSecurityScopedFile(from: url, fileType: .pdf))
            } catch {
                showValidation("PDFの保存に失敗しました。もう一度お試しください。")
            }
        case .failure:
            showValidation("PDFの取込に失敗しました。")
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    showValidation("画像を読み込めませんでした。")
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
            replaceFile(with: storedFile)
        } catch {
            showValidation("撮影した画像の保存に失敗しました。もう一度お試しください。")
        }
    }

    private func replaceFile(with storedFile: StoredDocumentFile) {
        let newFileURL = DocumentFileStore.fileURL(forLocalFilePath: storedFile.localFilePath)

        if let pendingNewFileURL, pendingNewFileURL != newFileURL {
            DocumentFileStore.deleteFile(at: pendingNewFileURL)
        } else if let previousFileURL = previewFileURL, previousFileURL != newFileURL {
            if document == nil {
                DocumentFileStore.deleteFile(at: previousFileURL)
            } else {
                pendingOldFileURLToDelete = previousFileURL
            }
        }

        localFilePath = storedFile.localFilePath
        storedFileName = storedFile.storedFileName
        originalFileName = storedFile.originalFileName
        mimeType = storedFile.mimeType
        fileSize = storedFile.fileSize
        attachmentFileType = storedFile.fileType
        pendingNewFileURL = newFileURL
        validationMessage = nil
    }

    private func cancel() {
        DocumentFileStore.deleteFile(at: pendingNewFileURL)
        dismiss()
    }

    private func payRecordLabel(_ record: PayRecord) -> String {
        let employerName = record.employer?.name ?? "勤務先未設定"
        return "\(record.paymentYear)年\(record.paymentMonth)月 \(employerName) \(record.incomeCategory.label)"
    }

    private func byteCountText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        isShowingValidation = true
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
