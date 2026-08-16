import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EmployerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @Query private var documents: [DocumentAttachment]

    @State private var isAddingEmployer = false
    @State private var blockedEmployerName: String?
    @State private var payRecordEmployer: Employer?
    @State private var draggedEmployerID: PersistentIdentifier?
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

    private var activeEmployers: [Employer] {
        displayedEmployers.filter { !$0.isArchived }
    }

    private var archivedEmployers: [Employer] {
        displayedEmployers.filter(\.isArchived)
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
                if !activeEmployers.isEmpty {
                    Section {
                        ForEach(Array(activeEmployers.enumerated()), id: \.element.persistentModelID) { index, employer in
                            employerLink(employer, rank: index + 1, canReorder: true)
                        }
                        .onMove(perform: moveActiveEmployers)
                        .onDelete { offsets in
                            deleteEmployers(at: offsets, from: activeEmployers)
                        }
                    } header: {
                        employerSectionHeader(
                            title: "登録済みの勤務先",
                            count: activeEmployers.count
                        )
                    } footer: {
                        Label("右端を長押しして表示順を変更", systemImage: "arrow.up.arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }

                if !archivedEmployers.isEmpty {
                    Section {
                        ForEach(archivedEmployers) { employer in
                            employerLink(employer, rank: nil, canReorder: false)
                                .opacity(0.62)
                        }
                        .onDelete { offsets in
                            deleteEmployers(at: offsets, from: archivedEmployers)
                        }
                    } header: {
                        employerSectionHeader(
                            title: "無効な勤務先",
                            count: archivedEmployers.count
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(18)
        .scrollContentBackground(.hidden)
        .background(EditorialStyle.pageBackground)
        .navigationTitle("勤務先")
        .navigationBarTitleDisplayMode(.inline)
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
            Text("\(blockedEmployerName ?? "この勤務先")には給与明細または書類が登録されています。削除せず、勤務先編集で「無効にする」を使ってください。")
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

    @ViewBuilder
    private func employerLink(
        _ employer: Employer,
        rank: Int?,
        canReorder: Bool
    ) -> some View {
        NavigationLink {
            EmployerFormView(employer: employer)
        } label: {
            EmployerManagementRow(
                employer: employer,
                rank: rank,
                canReorder: canReorder
            )
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
        .listRowBackground(Color(.systemBackground))
        .listRowSeparatorTint(EditorialStyle.divider)
        .onDrag {
            guard canReorder else {
                return NSItemProvider()
            }

            let id = employerID(for: employer)
            draggedEmployerID = id
            return NSItemProvider(object: "\(id)" as NSString)
        }
        .onDrop(
            of: canReorder ? [UTType.text] : [],
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
            .tint(appTheme.accentColor)
        }
    }

    private func employerSectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)件")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func moveActiveEmployers(from source: IndexSet, to destination: Int) {
        var reorderedEmployers = activeEmployers
        reorderedEmployers.move(fromOffsets: source, toOffset: destination)

        applySortOrder(to: reorderedEmployers + archivedEmployers)
    }

    private func reorderEmployer(
        draggedEmployerID: PersistentIdentifier,
        targetEmployerID: PersistentIdentifier
    ) {
        guard draggedEmployerID != targetEmployerID else {
            return
        }

        var reorderedEmployers = activeEmployers
        guard let sourceIndex = reorderedEmployers.firstIndex(where: { employerID(for: $0) == draggedEmployerID }),
              let targetIndex = reorderedEmployers.firstIndex(where: { employerID(for: $0) == targetEmployerID }) else {
            return
        }

        let draggedEmployer = reorderedEmployers.remove(at: sourceIndex)
        reorderedEmployers.insert(draggedEmployer, at: targetIndex)
        applySortOrder(to: reorderedEmployers + archivedEmployers)
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

    private func employerID(for employer: Employer) -> PersistentIdentifier {
        employer.persistentModelID
    }

    private func deleteEmployers(at offsets: IndexSet, from source: [Employer]) {
        let targets = offsets.map { source[$0] }
        if let blockedEmployer = targets.first(where: hasAssociatedData) {
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

    private func hasAssociatedData(_ employer: Employer) -> Bool {
        if !employer.payRecords.isEmpty {
            return true
        }

        return documents.contains {
            $0.employer?.persistentModelID == employer.persistentModelID
        }
    }
}

private struct EmployerManagementRow: View {
    @Environment(\.appTheme) private var appTheme

    let employer: Employer
    let rank: Int?
    let canReorder: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(rank.map { String(format: "%02d", $0) } ?? "–")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appTheme.accentColor)
                .monospacedDigit()
                .frame(width: 27, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(employer.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if employer.isArchived {
                        Text("無効")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if canReorder {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("長押しして並べ替え")
            }
        }
        .frame(minHeight: 66)
        .contentShape(Rectangle())
    }

    private var metadata: String {
        if employer.isArchived {
            return "\(employer.employerType.label) / 過去の給与明細は保持"
        }

        if let category = employer.defaultIncomeCategory {
            return "\(employer.employerType.label) / 既定：\(category.label)"
        }

        return "\(employer.employerType.label) / 既定：未設定"
    }
}

private struct EmployerDropDelegate: DropDelegate {
    let targetEmployerID: PersistentIdentifier
    @Binding var draggedEmployerID: PersistentIdentifier?
    let moveEmployer: (PersistentIdentifier, PersistentIdentifier) -> Void

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
