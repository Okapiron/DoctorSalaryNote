import SwiftData
import SwiftUI

struct PayRecordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

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
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(record.employer?.name ?? "勤務先未設定")
                                        .font(.headline)
                                    Spacer()
                                    Text(record.monthLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Text(record.incomeCategory.label)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("額面 \(record.grossAmount.yenText)")
                                        Text("手取り \(record.netAmount.yenText)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                }
                            }
                            .padding(.vertical, 4)
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
