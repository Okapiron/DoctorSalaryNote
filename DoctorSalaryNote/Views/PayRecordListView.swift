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
    @State private var selectedEmployerID: Int?

    private var employerSummaries: [PayRecordEmployerSummary] {
        var buckets: [Int: (employer: Employer?, records: [PayRecord])] = [:]

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
            if lhs.recordCount == rhs.recordCount {
                if lhs.grossTotal == rhs.grossTotal {
                    return lhs.employerName.localizedStandardCompare(rhs.employerName) == .orderedAscending
                }
                return lhs.grossTotal > rhs.grossTotal
            }
            return lhs.recordCount > rhs.recordCount
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
                        ForEach(filteredPayRecords) { record in
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
                    }
                }
            }
            .navigationTitle("給与")
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
        }
    }

    private func deletePayRecords(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredPayRecords[index])
        }

        try? modelContext.save()
    }

    private func summaryID(for employer: Employer?) -> Int {
        employer?.persistentModelID.hashValue ?? -1
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
    let id: Int
    let employer: Employer?
    let employerName: String
    let records: [PayRecord]

    var recordCount: Int {
        records.count
    }

    var grossTotal: Int {
        records.reduce(0) { $0 + $1.grossAmount }
    }

    var netTotal: Int {
        records.reduce(0) { $0 + $1.netAmount }
    }

    var latestRecord: PayRecord? {
        records.sorted { lhs, rhs in
            if lhs.paymentYear == rhs.paymentYear {
                if lhs.paymentMonth == rhs.paymentMonth {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.paymentMonth > rhs.paymentMonth
            }
            return lhs.paymentYear > rhs.paymentYear
        }
        .first
    }
}

private struct PayRecordEmployerSummaryRow: View {
    let summary: PayRecordEmployerSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.title3)
                .foregroundStyle(.cyan)
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
                            .foregroundStyle(.cyan)
                            .accessibilityLabel("絞り込み中")
                    }
                }

                Text(summary.latestRecord.map { "直近 \($0.monthLabel)・\($0.incomeCategory.label)" } ?? "給与明細なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                            .foregroundStyle(.cyan)
                            .accessibilityLabel("添付書類あり")
                    }
                }

                Text("給与明細・\(record.monthLabel)・\(record.incomeCategory.label)")
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
                amountRow("控除合計", payRecord.deductionTotal)

                if let incomeTaxAmount = payRecord.incomeTaxAmount {
                    amountRow("所得税", incomeTaxAmount)
                }
                if let residentTaxAmount = payRecord.residentTaxAmount {
                    amountRow("住民税", residentTaxAmount)
                }
                if let socialInsuranceAmount = payRecord.socialInsuranceAmount {
                    amountRow("社会保険料", socialInsuranceAmount)
                }
                if let otherDeductionAmount = payRecord.otherDeductionAmount {
                    amountRow("その他控除", otherDeductionAmount)
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

    private func amountRow(_ title: String, _ amount: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.yenText)
                .font(.headline)
        }
    }

    private func documentRow(_ document: DocumentAttachment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.attachmentFileType == .pdf ? "doc.richtext" : "photo")
                .foregroundStyle(.cyan)
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

    var deductionTotal: Int {
        deductionAmount ?? max(grossAmount - netAmount, 0)
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
