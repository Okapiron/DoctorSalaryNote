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
    @State private var documentDraft: DocumentDraft?
    @State private var selectedSummaryID: Int?

    private var yearPayRecords: [PayRecord] {
        payRecords.filter { $0.paymentYear == selectedYear }
    }

    private var yearDocuments: [DocumentAttachment] {
        documents.filter { $0.documentYear == selectedYear }
    }

    private var filteredYearDocuments: [DocumentAttachment] {
        guard let selectedSummaryID else {
            return yearDocuments
        }

        return yearDocuments.filter { document in
            summaryID(for: document.employer) == selectedSummaryID
        }
    }

    private var selectedSummary: DocumentWorkplaceSummary? {
        guard let selectedSummaryID else {
            return nil
        }

        return workplaceSummaries.first { $0.id == selectedSummaryID }
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
        .sorted { lhs, rhs in
            if lhs.totalDocumentCount == rhs.totalDocumentCount {
                if lhs.payRecordCount == rhs.payRecordCount {
                    return lhs.employerName.localizedStandardCompare(rhs.employerName) == .orderedAscending
                }
                return lhs.payRecordCount > rhs.payRecordCount
            }
            return lhs.totalDocumentCount > rhs.totalDocumentCount
        }

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
                        Text(verbatim: "\(selectedYear)年")
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
                        Button {
                            selectedSummaryID = selectedSummaryID == summary.id ? nil : summary.id
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(summary.employerName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(summary.totalDocumentCount)件")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 10) {
                                    documentStatusPill("源泉徴収票", summary.withholdingStatus.label, color: summary.withholdingStatus.color)
                                    documentStatusPill("支払調書", summary.paymentStatementStatus.paymentStatementLabel, color: summary.paymentStatementStatus.color)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSummaryID == summary.id ? Color.cyan.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedSummaryID == summary.id ? Color.cyan.opacity(0.45) : Color.black.opacity(0.04), lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)

                        if summary.withholdingStatus == .missing, let employer = summary.employer {
                            VStack(alignment: .leading) {
                                Button {
                                    documentDraft = DocumentDraft(
                                        documentType: .withholdingSlip,
                                        year: selectedYear,
                                        employer: employer
                                    )
                                } label: {
                                    Label("源泉徴収票を登録", systemImage: "plus.circle")
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                                .tint(.teal)
                            }
                            .padding(.top, -6)
                            .listRowInsets(EdgeInsets(top: 0, leading: 30, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }

            Section {
                if filteredYearDocuments.isEmpty {
                    Text("この年の書類はまだ登録されていません。右上の追加ボタンからPDFや画像を登録できます。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredYearDocuments) { document in
                        NavigationLink {
                            DocumentFormView(document: document)
                        } label: {
                            DocumentRow(document: document)
                        }
                    }
                    .onDelete(perform: deleteDocuments)
                }
            } header: {
                HStack {
                    Text(selectedSummary.map { "\($0.employerName)の書類" } ?? "登録済み書類")
                    Spacer()
                    if selectedSummaryID != nil {
                        Button("すべて表示") {
                            selectedSummaryID = nil
                        }
                        .font(.caption)
                    }
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
        .sheet(item: $documentDraft) { draft in
            NavigationStack {
                DocumentFormView(
                    initialYear: draft.year,
                    initialDocumentType: draft.documentType,
                    initialEmployer: draft.employer
                )
            }
        }
    }

    private func documentStatusPill(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.systemBackground).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func makeSummary(for employer: Employer?) -> DocumentWorkplaceSummary {
        let records = yearPayRecords.filter { $0.employer?.persistentModelID == employer?.persistentModelID }
        let employerDocuments = yearDocuments.filter { $0.employer?.persistentModelID == employer?.persistentModelID }
        let hasWithholdingSlip = employerDocuments.contains { $0.documentType == .withholdingSlip }
        let hasPaymentStatement = employerDocuments.contains { $0.documentType == .paymentStatement }

        return DocumentWorkplaceSummary(
            id: summaryID(for: employer),
            employer: employer,
            employerName: employer?.name ?? "勤務先未設定",
            payRecordCount: records.count,
            totalDocumentCount: employerDocuments.count,
            withholdingStatus: hasWithholdingSlip ? .registered : (records.isEmpty ? .none : .missing),
            paymentStatementStatus: hasPaymentStatement ? .registered : .none
        )
    }

    private func summaryID(for employer: Employer?) -> Int {
        employer?.persistentModelID.hashValue ?? -1
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            let document = filteredYearDocuments[index]
            DocumentFileStore.deleteFile(for: document)
            modelContext.delete(document)
        }

        try? modelContext.save()
    }
}

private struct DocumentWorkplaceSummary: Identifiable {
    let id: Int
    let employer: Employer?
    let employerName: String
    let payRecordCount: Int
    let totalDocumentCount: Int
    let withholdingStatus: DocumentStatus
    let paymentStatementStatus: DocumentStatus
}

private struct DocumentDraft: Identifiable {
    let id = UUID()
    let documentType: DocumentType
    let year: Int
    let employer: Employer
}

private enum DocumentStatus: Equatable {
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

    var paymentStatementLabel: String {
        switch self {
        case .registered: "あり"
        case .missing, .none: "なし"
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
        HStack(spacing: 12) {
            Image(systemName: document.attachmentFileType == .pdf ? "doc.richtext" : "photo")
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.documentType.label)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(document.attachmentFileType.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let employerName = document.employer?.name ?? "勤務先未設定"
        if let payRecord = document.payRecord {
            return "\(payRecord.paymentMonth)月・\(employerName)"
        }
        return employerName
    }
}
