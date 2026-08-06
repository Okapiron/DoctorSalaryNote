import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EmployerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @State private var isAddingEmployer = false
    @State private var blockedEmployerName: String?
    @State private var payRecordEmployer: Employer?
    @State private var draggedEmployerID: Int?
    @State private var operationErrorMessage: String?

    private var displayedEmployers: [Employer] {
        employers.sorted { lhs, rhs in
            if lhs.isArchived != rhs.isArchived {
                return !lhs.isArchived
            }

            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if employers.isEmpty {
                ContentUnavailableView(
                    "勤務先がありません",
                    systemImage: "building.2",
                    description: Text("常勤先、外勤先、当直先など、収入が発生する勤務先を右上の追加ボタンから登録できます。")
                )
            } else {
                ForEach(displayedEmployers) { employer in
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
                    .onDrag {
                        let id = employerID(for: employer)
                        draggedEmployerID = id
                        return NSItemProvider(object: "\(id)" as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: EmployerDropDelegate(
                            targetEmployerID: employerID(for: employer),
                            draggedEmployerID: $draggedEmployerID,
                            moveEmployer: reorderEmployer
                        )
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            payRecordEmployer = employer
                        } label: {
                            Label("給与入力", systemImage: "yensign.circle")
                        }
                        .tint(.teal)
                    }
                }
                .onMove(perform: moveEmployers)
                .onDelete(perform: deleteEmployers)
            }
        }
        .navigationTitle("勤務先")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }

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
        .sheet(item: $payRecordEmployer) { employer in
            NavigationStack {
                PayRecordFormView(initialEmployer: employer)
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
            Text("\(blockedEmployerName ?? "この勤務先")には給与明細が登録されています。削除せず、勤務先編集で「無効にする」を使ってください。")
        }
        .alert("変更を保存できませんでした", isPresented: Binding(
            get: { operationErrorMessage != nil },
            set: { if !$0 { operationErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "もう一度お試しください。")
        }
    }

    private func moveEmployers(from source: IndexSet, to destination: Int) {
        var reorderedEmployers = displayedEmployers
        reorderedEmployers.move(fromOffsets: source, toOffset: destination)

        applySortOrder(to: reorderedEmployers)
    }

    private func reorderEmployer(draggedEmployerID: Int, targetEmployerID: Int) {
        guard draggedEmployerID != targetEmployerID else {
            return
        }

        var reorderedEmployers = displayedEmployers
        guard let sourceIndex = reorderedEmployers.firstIndex(where: { employerID(for: $0) == draggedEmployerID }),
              let targetIndex = reorderedEmployers.firstIndex(where: { employerID(for: $0) == targetEmployerID }) else {
            return
        }

        let draggedEmployer = reorderedEmployers.remove(at: sourceIndex)
        reorderedEmployers.insert(draggedEmployer, at: targetIndex)
        applySortOrder(to: reorderedEmployers)
    }

    private func applySortOrder(to reorderedEmployers: [Employer]) {
        for (index, employer) in reorderedEmployers.enumerated() {
            employer.sortOrder = index
            employer.updatedAt = Date()
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            operationErrorMessage = "勤務先の並び順を保存できませんでした。"
        }
    }

    private func employerID(for employer: Employer) -> Int {
        employer.persistentModelID.hashValue
    }

    private func deleteEmployers(at offsets: IndexSet) {
        let targets = offsets.map { displayedEmployers[$0] }
        if let blockedEmployer = targets.first(where: { !$0.payRecords.isEmpty }) {
            blockedEmployerName = blockedEmployer.name
            return
        }

        for employer in targets {
            modelContext.delete(employer)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            operationErrorMessage = "勤務先を削除できませんでした。"
        }
    }
}

private struct EmployerDropDelegate: DropDelegate {
    let targetEmployerID: Int
    @Binding var draggedEmployerID: Int?
    let moveEmployer: (Int, Int) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggedEmployerID else {
            return
        }

        moveEmployer(draggedEmployerID, targetEmployerID)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedEmployerID = nil
        return true
    }
}
