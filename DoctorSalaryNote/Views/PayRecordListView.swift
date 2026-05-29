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

    var body: some View {
        NavigationStack {
            List {
                if payRecords.isEmpty {
                    ContentUnavailableView(
                        "明細がありません",
                        systemImage: "list.bullet.rectangle",
                        description: Text("左上の「勤務先」で勤務先を登録し、右上の追加ボタンから給与明細を追加できます。")
                    )
                } else {
                    ForEach(payRecords) { record in
                        NavigationLink {
                            PayRecordFormView(payRecord: record)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(record.employer?.name ?? "勤務先未設定")
                                            .font(.headline)
                                            .lineLimit(1)

                                        if hasLinkedDocument(for: record) {
                                            Image(systemName: "paperclip")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.cyan)
                                                .accessibilityLabel("添付書類あり")
                                        }
                                    }

                                    Text("\(record.monthLabel)・\(record.incomeCategory.label)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("額面")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(record.grossAmount.yenText)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete(perform: deletePayRecords)
                }
            }
            .navigationTitle("明細")
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
            modelContext.delete(payRecords[index])
        }

        try? modelContext.save()
    }

    private func hasLinkedDocument(for record: PayRecord) -> Bool {
        documentAttachments.contains {
            $0.payRecord?.persistentModelID == record.persistentModelID
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
