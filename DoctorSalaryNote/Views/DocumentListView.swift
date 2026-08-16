import SwiftData
import SwiftUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

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
        SortDescriptor(\DocumentAttachment.documentMonth, order: .reverse),
        SortDescriptor(\DocumentAttachment.createdAt, order: .reverse)
    ]) private var documents: [DocumentAttachment]

    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var isAddingDocument = false
    @State private var selectedSummaryID: DocumentSummaryID?
    @State private var deletionErrorMessage: String?

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
            if lhs.grossTotal == rhs.grossTotal {
                if lhs.totalDocumentCount == rhs.totalDocumentCount {
                    return lhs.employerName.localizedStandardCompare(rhs.employerName) == .orderedAscending
                }
                return lhs.totalDocumentCount > rhs.totalDocumentCount
            }
            return lhs.grossTotal > rhs.grossTotal
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
                    Text(verbatim: "\(selectedYear)年")
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color(.systemBackground))
                .listRowSeparatorTint(EditorialStyle.divider)
            }

            Section {
                if workplaceSummaries.isEmpty {
                    ContentUnavailableView(
                        "この年の書類状況はまだありません",
                        systemImage: "doc.text",
                        description: Text("給与明細がある勤務先は、源泉徴収票の未登録もここで確認できます。")
                    )
                } else {
                    ForEach(workplaceSummaries) { summary in
                        DocumentWorkplaceSummaryRow(
                            summary: summary,
                            isSelected: selectedSummaryID == summary.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSummaryID = selectedSummaryID == summary.id ? nil : summary.id
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color(.systemBackground))
                        .listRowSeparatorTint(EditorialStyle.divider)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("勤務先別の書類状況")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("総支給額が多い順")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.bottom, 4)
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                        .listRowBackground(Color(.systemBackground))
                        .listRowSeparatorTint(EditorialStyle.divider)
                    }
                    .onDelete(perform: deleteDocuments)
                }
            } header: {
                HStack {
                    Text(selectedSummary.map { "\($0.employerName)の書類" } ?? "登録済み書類")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedSummaryID != nil {
                        Button("すべて表示") {
                            selectedSummaryID = nil
                        }
                        .font(.caption)
                    } else {
                        Text("新しい順")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .textCase(nil)
                .padding(.bottom, 4)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(16)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .navigationTitle("書類")
        .navigationBarTitleDisplayMode(.inline)
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
        .onChange(of: selectedYear) { _, _ in
            selectedSummaryID = nil
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

    private func makeSummary(for employer: Employer?) -> DocumentWorkplaceSummary {
        let records = yearPayRecords.filter { $0.employer?.persistentModelID == employer?.persistentModelID }
        let employerDocuments = yearDocuments.filter { $0.employer?.persistentModelID == employer?.persistentModelID }
        let hasWithholdingSlip = employerDocuments.contains { $0.documentType == .withholdingSlip }
        let hasPaymentStatement = employerDocuments.contains { $0.documentType == .paymentStatement }
        let grossTotal = records.reduce(0) { $0 + $1.grossAmount }

        return DocumentWorkplaceSummary(
            id: summaryID(for: employer),
            employer: employer,
            employerName: employer?.name ?? "勤務先未設定",
            payRecordCount: records.count,
            totalDocumentCount: employerDocuments.count,
            grossTotal: grossTotal,
            withholdingStatus: hasWithholdingSlip ? .registered : (records.isEmpty ? .none : .missing),
            paymentStatementStatus: hasPaymentStatement ? .registered : .none
        )
    }

    private func summaryID(for employer: Employer?) -> DocumentSummaryID {
        employer.map { .employer($0.persistentModelID) } ?? .unassigned
    }

    private func deleteDocuments(at offsets: IndexSet) {
        let targets = offsets.map { filteredYearDocuments[$0] }
        let fileURLs = targets.compactMap { DocumentFileStore.fileURL(for: $0) }

        for document in targets {
            modelContext.delete(document)
        }

        do {
            try modelContext.save()
            do {
                try DocumentFileStore.deleteFiles(at: fileURLs)
            } catch {
                deletionErrorMessage = "書類情報は削除しましたが、端末内のファイルを整理できませんでした。アプリを再起動して、もう一度お試しください。"
            }
        } catch {
            modelContext.rollback()
            deletionErrorMessage = "書類を削除できませんでした。データを確認して、もう一度お試しください。"
        }
    }
}

private struct DocumentWorkplaceSummary: Identifiable {
    let id: DocumentSummaryID
    let employer: Employer?
    let employerName: String
    let payRecordCount: Int
    let totalDocumentCount: Int
    let grossTotal: Int
    let withholdingStatus: DocumentStatus
    let paymentStatementStatus: DocumentStatus
}

private enum DocumentSummaryID: Hashable {
    case employer(PersistentIdentifier)
    case unassigned
}

private enum DocumentStatus: Equatable {
    case registered
    case missing
    case none

    var label: String {
        switch self {
        case .registered: "登録済"
        case .missing: "未登録"
        case .none: "なし"
        }
    }

    var paymentStatementLabel: String {
        switch self {
        case .registered: "あり"
        case .missing, .none: "なし（任意）"
        }
    }

    var color: Color {
        switch self {
        case .registered: .green
        case .missing: .orange
        case .none: .secondary
        }
    }

    var paymentStatementColor: Color {
        switch self {
        case .registered: .green
        case .missing, .none: .secondary
        }
    }
}

private struct DocumentWorkplaceSummaryRow: View {
    @Environment(\.appTheme) private var appTheme

    let summary: DocumentWorkplaceSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(summary.employerName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(appTheme.accentColor)
                        .accessibilityLabel("絞り込み中")
                }

                Text("\(summary.totalDocumentCount)件")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 2) {
                documentStatus(
                    "源泉徴収票",
                    summary.withholdingStatus.label,
                    color: summary.withholdingStatus.color
                )
                .frame(width: 112, alignment: .leading)

                documentStatus(
                    "支払調書",
                    summary.paymentStatementStatus.paymentStatementLabel,
                    color: summary.paymentStatementStatus.paymentStatementColor
                )
            }
        }
        .frame(minHeight: 70)
        .background {
            if isSelected {
                appTheme.accentColor.opacity(0.06)
                    .padding(.horizontal, -8)
            }
        }
    }

    private func documentStatus(_ title: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .font(.system(size: 13))
        .lineLimit(1)
    }
}

private struct DocumentRow: View {
    @Environment(\.appTheme) private var appTheme

    let document: DocumentAttachment

    var body: some View {
        HStack(spacing: 10) {
            EditorialIconBadge(
                systemImage: document.attachmentFileType == .pdf ? "doc.richtext" : "photo",
                size: 30
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(document.documentType.label)
                    .font(.system(size: 16, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(document.attachmentFileType.label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 62)
    }

    private var subtitle: String {
        let employerName = document.employer?.name ?? "勤務先未設定"
        let month = document.documentMonth
            ?? document.payRecord?.paymentMonth
            ?? Calendar.current.component(.month, from: document.createdAt)
        return "\(document.documentYear)年\(month)月 / \(employerName)"
    }
}
