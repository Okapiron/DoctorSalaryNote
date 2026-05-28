import SwiftData
import SwiftUI

struct EmployerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @State private var isAddingEmployer = false
    @State private var blockedEmployerName: String?

    var body: some View {
        List {
            if employers.isEmpty {
                ContentUnavailableView(
                    "勤務先がありません",
                    systemImage: "building.2",
                    description: Text("右上の追加ボタンから登録できます。")
                )
            } else {
                ForEach(employers) { employer in
                    NavigationLink {
                        EmployerFormView(employer: employer)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(employer.name)
                                    .font(.headline)
                                if employer.isArchived {
                                    Text("無効")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(employer.employerType.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let category = employer.defaultIncomeCategory {
                                Text("既定: \(category.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteEmployers)
            }
        }
        .navigationTitle("勤務先")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingEmployer = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingEmployer) {
            NavigationStack {
                EmployerFormView()
            }
        }
        .alert("削除できません", isPresented: Binding(
            get: { blockedEmployerName != nil },
            set: { if !$0 { blockedEmployerName = nil } }
        )) {
            Button("OK", role: .cancel) {
                blockedEmployerName = nil
            }
        } message: {
            Text("\(blockedEmployerName ?? "この勤務先")には給与明細が登録されています。先に関連する明細を削除してください。")
        }
    }

    private func deleteEmployers(at offsets: IndexSet) {
        for index in offsets {
            let employer = employers[index]
            guard employer.payRecords.isEmpty else {
                blockedEmployerName = employer.name
                return
            }
            modelContext.delete(employer)
        }

        try? modelContext.save()
    }
}
