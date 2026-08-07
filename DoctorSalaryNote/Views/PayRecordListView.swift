import SwiftData
import SwiftUI

struct PayRecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @Query(sort: [
        SortDescriptor(\DocumentAttachment.createdAt, order: .reverse)
    ]) private var documentAttachments: [DocumentAttachment]

    @State private var isAddingPayRecord = false
    @State private var selectedEmployerID: PayRecordEmployerSummaryID?
    @State private var payRecordPage = 0
    @State private var payRecordsPendingDeletion: [PayRecord] = []
    @State private var isShowingPayRecordDeleteConfirmation = false
    @State private var deletionErrorMessage: String?

    private let payRecordsPerPage = 20

    private var employerSummaries: [PayRecordEmployerSummary] {
        var buckets: [PayRecordEmployerSummaryID: (employer: Employer?, records: [PayRecord])] = [:]

        for record in payRecords {
            let id = summaryID(for: record.employer)
            if buckets[id] == nil {
                buckets[id] = (record.employer, [])
            }
            buckets[id]?.records.append(record)
        }

        return buckets.map { id, bucket in
            PayRecordEmployerSummary(
                id: id,
                employer: bucket.employer,
                employerName: bucket.employer?.name ?? "勤務先未設定",
                records: bucket.records
            )
        }
        .sorted { lhs, rhs in
            if lhs.grossTotal == rhs.grossTotal {
                if lhs.recordCount == rhs.recordCount {
                    return lhs.employerName.localizedStandardCompare(rhs.employerName) == .orderedAscending
                }
                return lhs.recordCount > rhs.recordCount
            }
            return lhs.grossTotal > rhs.grossTotal
        }
    }

    private var filteredPayRecords: [PayRecord] {
        guard let selectedEmployerID else {
            return payRecords
        }

        return payRecords.filter {
            summaryID(for: $0.employer) == selectedEmployerID
        }
    }

    private var selectedSummary: PayRecordEmployerSummary? {
        guard let selectedEmployerID else {
            return nil
        }

        return employerSummaries.first { $0.id == selectedEmployerID }
    }

    private var payRecordPageCount: Int {
        max((filteredPayRecords.count + payRecordsPerPage - 1) / payRecordsPerPage, 1)
    }

    private var clampedPayRecordPage: Int {
        min(max(payRecordPage, 0), payRecordPageCount - 1)
    }

    private var displayedPayRecords: [PayRecord] {
        Array(filteredPayRecords.dropFirst(clampedPayRecordPage * payRecordsPerPage).prefix(payRecordsPerPage))
    }

    private var payRecordPageRangeText: String {
        guard !filteredPayRecords.isEmpty else {
            return "0件"
        }

        let start = clampedPayRecordPage * payRecordsPerPage + 1
        let end = min(start + displayedPayRecords.count - 1, filteredPayRecords.count)
        return "\(start)-\(end)件 / \(filteredPayRecords.count)件"
    }

    var body: some View {
        NavigationStack {
            List {
                if payRecords.isEmpty {
                    ContentUnavailableView(
                        "給与明細がありません",
                        systemImage: "list.bullet.rectangle",
                        description: Text("左上の「勤務先」で勤務先を登録し、右上の追加ボタンから給与明細を追加できます。")
                    )
                } else {
                    Section("勤務先別の給与") {
                        ForEach(employerSummaries) { summary in
                            Button {
                                selectedEmployerID = selectedEmployerID == summary.id ? nil : summary.id
                            } label: {
                                PayRecordEmployerSummaryRow(
                                    summary: summary,
                                    isSelected: selectedEmployerID == summary.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section {
                        ForEach(displayedPayRecords) { record in
                            NavigationLink {
                                PayRecordDetailView(
                                    payRecord: record
                                )
                            } label: {
                                PayRecordRow(
                                    record: record,
                                    hasDocument: hasLinkedDocument(for: record)
                                )
                            }
                        }
                        .onDelete(perform: deletePayRecords)
                    } header: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(selectedSummary.map { "\($0.employerName)の給与明細" } ?? "給与明細")
                                Spacer()
                                if selectedEmployerID != nil {
                                    Button("すべて表示") {
                                        selectedEmployerID = nil
                                    }
                                    .font(.caption)
                                }
                            }

                            if payRecordPageCount > 1 {
                                HStack {
                                    Text("\(clampedPayRecordPage + 1)/\(payRecordPageCount)ページ・\(payRecordPageRangeText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    Spacer()
                                    pageControl
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("給与")
            .onChange(of: selectedEmployerID) { _, _ in
                payRecordPage = 0
            }
            .onChange(of: filteredPayRecords.count) { _, _ in
                clampPayRecordPage()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        EmployerListView()
                    } label: {
                        Label("勤務先", systemImage: "building.2")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingPayRecord = true
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingPayRecord) {
                NavigationStack {
                    PayRecordFormView()
                }
            }
            .alert("給与明細を削除しますか？", isPresented: $isShowingPayRecordDeleteConfirmation) {
                Button("削除", role: .destructive) {
                    deletePayRecordsAndLinkedDocuments(payRecordsPendingDeletion)
                    payRecordsPendingDeletion = []
                }
                Button("キャンセル", role: .cancel) {
                    payRecordsPendingDeletion = []
                }
            } message: {
                Text("紐づく書類と保存済みファイルも一緒に削除されます。この操作は元に戻せません。")
            }
            .alert("削除できませんでした", isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    deletionErrorMessage = nil
                }
            } message: {
                Text(deletionErrorMessage ?? "もう一度お試しください。")
            }
        }
    }

    private func deletePayRecords(at offsets: IndexSet) {
        let targets = offsets.map { displayedPayRecords[$0] }
        if targets.contains(where: { hasLinkedDocument(for: $0) }) {
            payRecordsPendingDeletion = targets
            isShowingPayRecordDeleteConfirmation = true
            return
        }

        deletePayRecordsAndLinkedDocuments(targets)
    }

    private func deletePayRecordsAndLinkedDocuments(_ records: [PayRecord]) {
        let documentsToDelete = records.flatMap { linkedDocuments(for: $0) }
        let fileURLs = documentsToDelete.compactMap { DocumentFileStore.fileURL(for: $0) }

        for record in records {
            for document in documentsToDelete.filter({ $0.payRecord?.persistentModelID == record.persistentModelID }) {
                modelContext.delete(document)
            }
            modelContext.delete(record)
        }

        do {
            try modelContext.save()
            do {
                try DocumentFileStore.deleteFiles(at: fileURLs)
            } catch {
                deletionErrorMessage = "給与明細は削除しましたが、端末内の添付ファイルを整理できませんでした。アプリを再起動して、もう一度お試しください。"
            }
            clampPayRecordPage()
        } catch {
            modelContext.rollback()
            deletionErrorMessage = "給与明細を削除できませんでした。データを確認して、もう一度お試しください。"
        }
    }

    private var pageControl: some View {
        HStack(spacing: 0) {
            Button {
                movePayRecordPage(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 34, height: 26)
            }
            .disabled(clampedPayRecordPage == 0)
            .buttonStyle(.borderless)
            .accessibilityLabel("前のページ")

            Divider()
                .frame(height: 18)

            Button {
                movePayRecordPage(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 34, height: 26)
            }
            .disabled(clampedPayRecordPage >= payRecordPageCount - 1)
            .buttonStyle(.borderless)
            .accessibilityLabel("次のページ")
        }
        .foregroundStyle(.primary)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }

    private func movePayRecordPage(by delta: Int) {
        payRecordPage = min(max(clampedPayRecordPage + delta, 0), payRecordPageCount - 1)
    }

    private func clampPayRecordPage() {
        payRecordPage = clampedPayRecordPage
    }

    private func summaryID(for employer: Employer?) -> PayRecordEmployerSummaryID {
        employer.map { .employer($0.persistentModelID) } ?? .unassigned
    }

    private func hasLinkedDocument(for record: PayRecord) -> Bool {
        !linkedDocuments(for: record).isEmpty
    }

    private func linkedDocuments(for record: PayRecord) -> [DocumentAttachment] {
        documentAttachments.filter {
            $0.payRecord?.persistentModelID == record.persistentModelID
        }
    }
}

private struct PayRecordEmployerSummary: Identifiable {
    let id: PayRecordEmployerSummaryID
    let employer: Employer?
    let employerName: String
    let records: [PayRecord]

    var recordCount: Int {
        records.count
    }

    var grossTotal: Int {
        records.reduce(0) { $0 + $1.grossAmount }
    }
}

private enum PayRecordEmployerSummaryID: Hashable {
    case employer(PersistentIdentifier)
    case unassigned
}

private struct PayRecordEmployerSummaryRow: View {
    @Environment(\.appTheme) private var appTheme

    let summary: PayRecordEmployerSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.title3)
                .foregroundStyle(appTheme.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(summary.employerName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.accentColor)
                            .accessibilityLabel("絞り込み中")
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(summary.recordCount)件")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary.grossTotal.yenText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct PayRecordRow: View {
    @Environment(\.appTheme) private var appTheme

    let record: PayRecord
    let hasDocument: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.employer?.name ?? "勤務先未設定")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if hasDocument {
                        Image(systemName: "paperclip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.accentColor)
                            .accessibilityLabel("添付書類あり")
                    }
                }

                Text(record.monthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("総支給額")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(record.grossAmount.yenText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 118, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct PayRecordDetailView: View {
    @Environment(\.appTheme) private var appTheme

    let payRecord: PayRecord

    @Query(sort: [
        SortDescriptor(\DocumentAttachment.createdAt, order: .reverse)
    ]) private var documentAttachments: [DocumentAttachment]

    @State private var isEditing = false

    private var documents: [DocumentAttachment] {
        documentAttachments.filter {
            $0.payRecord?.persistentModelID == payRecord.persistentModelID
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(payRecord.employer?.name ?? "勤務先未設定")
                        .font(.title3.weight(.semibold))
                    Text("\(payRecord.monthLabel)・\(payRecord.incomeCategory.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("金額") {
                amountRow("総支給額（額面）", payRecord.grossAmount)
                amountRow("手取り", payRecord.netAmount)
                amountRow("控除合計", payRecord.deductionTotalForDisplay)

                if let incomeTaxAmount = payRecord.incomeTaxAmount {
                    amountRow("所得税", incomeTaxAmount)
                }
                if let residentTaxAmount = payRecord.residentTaxAmount {
                    amountRow("住民税", residentTaxAmount)
                }

                ForEach(payRecord.sortedDeductionItems) { item in
                    amountRow(item.displayNameSnapshot, item.amount)
                }

                if payRecord.deductionItems.isEmpty,
                   let socialInsuranceAmount = payRecord.socialInsuranceAmount {
                    amountRow("社会保険料", socialInsuranceAmount)
                }
                if let otherDeductionAmount = payRecord.otherDeductionAmount {
                    amountRow(payRecord.deductionItems.isEmpty ? "その他控除" : "その他（推定）", otherDeductionAmount)
                }
            }

            if !payRecord.memo.isEmpty {
                Section("メモ") {
                    Text(payRecord.memo)
                }
            }

            Section("添付書類") {
                if documents.isEmpty {
                    Text("この給与明細に紐づく書類はまだありません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(documents) { document in
                        if let fileURL = DocumentFileStore.fileURL(for: document) {
                            NavigationLink {
                                DocumentPreviewView(
                                    title: document.documentType.label,
                                    fileType: document.attachmentFileType,
                                    fileURL: fileURL
                                )
                            } label: {
                                documentRow(document)
                            }
                        } else {
                            documentRow(document)
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
        .navigationTitle("給与明細")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                PayRecordFormView(payRecord: payRecord)
            }
        }
    }

    private func amountRow(_ title: String, _ amount: Int?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.map(\.yenText) ?? "未入力")
                .font(.headline)
        }
    }

    private func documentRow(_ document: DocumentAttachment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.attachmentFileType == .pdf ? "doc.richtext" : "photo")
                .foregroundStyle(appTheme.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.documentType.label)
                Text(document.originalFileName ?? "ファイル名未設定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private extension PayRecord {
    var monthLabel: String {
        "\(paymentYear)年\(paymentMonth)月"
    }
}

extension Int {
    var yenText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)円"
    }
}
