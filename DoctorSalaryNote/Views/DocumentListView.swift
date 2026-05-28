import SwiftData
import SwiftUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @Query(sort: [
        SortDescriptor(\DocumentAttachment.documentYear, order: .reverse),
        SortDescriptor(\DocumentAttachment.createdAt, order: .reverse)
    ]) private var documents: [DocumentAttachment]

    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var isAddingDocument = false

    private var yearPayRecords: [PayRecord] {
        payRecords.filter { $0.paymentYear == selectedYear }
    }

    private var yearDocuments: [DocumentAttachment] {
        documents.filter { $0.documentYear == selectedYear }
    }

    private var workplaceSummaries: [DocumentWorkplaceSummary] {
        let employerIDsFromPayRecords = yearPayRecords.compactMap { $0.employer?.persistentModelID }
        let employerIDsFromDocuments = yearDocuments.compactMap { $0.employer?.persistentModelID }
        let uniqueEmployerIDs = Set(employerIDsFromPayRecords + employerIDsFromDocuments)

        var summaries = uniqueEmployerIDs.compactMap { employerID -> DocumentWorkplaceSummary? in
            guard let employer = employers.first(where: { $0.persistentModelID == employerID }) else {
                return nil
            }
            return makeSummary(for: employer)
        }
        .sorted { $0.employerName.localizedStandardCompare($1.employerName) == .orderedAscending }

        if yearDocuments.contains(where: { $0.employer == nil }) {
            summaries.append(makeSummary(for: nil))
        }

        return summaries
    }

    var body: some View {
        List {
            Section {
                Stepper(value: $selectedYear, in: 2000...2100) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selectedYear)年")
                            .font(.title3.weight(.semibold))
                        Text("書類管理は年別で表示します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("勤務先別の書類状況") {
                if workplaceSummaries.isEmpty {
                    ContentUnavailableView(
                        "この年の書類状況はまだありません",
                        systemImage: "doc.text",
                        description: Text("給与明細がある勤務先は、源泉徴収票の未登録もここで確認できます。")
                    )
                } else {
                    ForEach(workplaceSummaries) { summary in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(summary.employerName)
                                .font(.headline)

                            Label("給与・賞与明細: \(summary.payslipDocumentCount)件 / 登録明細 \(summary.payRecordCount)件", systemImage: "doc.plaintext")
                                .font(.subheadline)

                            HStack {
                                statusText("源泉徴収票", summary.withholdingStatus)
                                Spacer()
                                statusText("支払調書", summary.paymentStatementStatus)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("登録済み書類") {
                if yearDocuments.isEmpty {
                    Text("この年の書類はまだ登録されていません。右上の追加ボタンからPDFや画像を登録できます。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(yearDocuments) { document in
                        NavigationLink {
                            DocumentFormView(document: document)
                        } label: {
                            DocumentRow(document: document)
                        }
                    }
                    .onDelete(perform: deleteDocuments)
                }
            }
        }
        .navigationTitle("書類")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingDocument = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingDocument) {
            NavigationStack {
                DocumentFormView(initialYear: selectedYear)
            }
        }
    }

    private func statusText(_ title: String, _ status: DocumentStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(status.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)
        }
    }

    private func makeSummary(for employer: Employer?) -> DocumentWorkplaceSummary {
        let records = yearPayRecords.filter { $0.employer?.persistentModelID == employer?.persistentModelID }
        let employerDocuments = yearDocuments.filter { $0.employer?.persistentModelID == employer?.persistentModelID }
        let payslipDocumentCount = employerDocuments.filter {
            $0.documentType == .payslip || $0.documentType == .bonusPayslip
        }.count
        let hasWithholdingSlip = employerDocuments.contains { $0.documentType == .withholdingSlip }
        let hasPaymentStatement = employerDocuments.contains { $0.documentType == .paymentStatement }

        return DocumentWorkplaceSummary(
            id: employer?.persistentModelID.hashValue ?? -1,
            employerName: employer?.name ?? "勤務先未設定",
            payRecordCount: records.count,
            payslipDocumentCount: payslipDocumentCount,
            withholdingStatus: hasWithholdingSlip ? .registered : (records.isEmpty ? .none : .missing),
            paymentStatementStatus: hasPaymentStatement ? .registered : .none
        )
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            let document = yearDocuments[index]
            DocumentFileStore.deleteFile(for: document)
            modelContext.delete(document)
        }

        try? modelContext.save()
    }
}

private struct DocumentWorkplaceSummary: Identifiable {
    let id: Int
    let employerName: String
    let payRecordCount: Int
    let payslipDocumentCount: Int
    let withholdingStatus: DocumentStatus
    let paymentStatementStatus: DocumentStatus
}

private enum DocumentStatus {
    case registered
    case missing
    case none

    var label: String {
        switch self {
        case .registered: "登録済み"
        case .missing: "未登録"
        case .none: "なし"
        }
    }

    var color: Color {
        switch self {
        case .registered: .green
        case .missing: .orange
        case .none: .secondary
        }
    }
}

private struct DocumentRow: View {
    let document: DocumentAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(document.documentType.label)
                    .font(.headline)
                Spacer()
                Text("\(document.documentYear)年")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(document.employer?.name ?? "勤務先未設定")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let originalFileName = document.originalFileName {
                Label(originalFileName, systemImage: document.attachmentFileType == .pdf ? "doc.richtext" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
