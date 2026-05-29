import Charts
import SwiftData
import SwiftUI

struct HomeSummaryView: View {
    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @Query private var documentAttachments: [DocumentAttachment]

    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private var latestMonthKey: MonthKey {
        if let record = payRecords.first {
            return MonthKey(year: record.paymentYear, month: record.paymentMonth)
        }

        let now = Date()
        let calendar = Calendar.current
        return MonthKey(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
    }

    private var recentMonthSummaries: [HomeMonthSummary] {
        (0..<6).reversed().map { offset in
            let key = latestMonthKey.addingMonths(-offset)
            let records = payRecords.filter {
                $0.paymentYear == key.year && $0.paymentMonth == key.month
            }
            return HomeMonthSummary(key: key, records: records)
        }
    }

    private var latestMonthSummary: HomeMonthSummary {
        HomeMonthSummary(
            key: latestMonthKey,
            records: payRecords.filter {
                $0.paymentYear == latestMonthKey.year && $0.paymentMonth == latestMonthKey.month
            }
        )
    }

    private var selectedYearRecords: [PayRecord] {
        payRecords.filter { $0.paymentYear == selectedYear }
    }

    private var selectedYearSummary: HomeYearSummary {
        HomeYearSummary(year: selectedYear, records: selectedYearRecords)
    }

    private var recentRecords: [PayRecord] {
        Array(payRecords.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthlyTrendSection
                latestMonthSection
                yearSummarySection
                recentRecordsSection
                documentAlertSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ホーム")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
    }

    private var monthlyTrendSection: some View {
        homeCard(tint: .teal) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "直近の月別給与",
                    subtitle: "最近6か月の額面と手取り"
                )

                if payRecords.isEmpty {
                    ContentUnavailableView(
                        "給与明細を登録すると、月別の推移が表示されます",
                        systemImage: "chart.bar.xaxis",
                        description: Text("まずは勤務先と給与明細を登録してください。")
                    )
                    .frame(minHeight: 170)
                } else {
                    Chart {
                        ForEach(recentMonthSummaries) { summary in
                            BarMark(
                                x: .value("月", summary.shortLabel),
                                y: .value("額面", summary.grossTotal)
                            )
                            .foregroundStyle(.cyan.gradient)
                            .cornerRadius(4)
                        }

                        ForEach(recentMonthSummaries) { summary in
                            LineMark(
                                x: .value("月", summary.shortLabel),
                                y: .value("手取り", summary.netTotal)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))

                            PointMark(
                                x: .value("月", summary.shortLabel),
                                y: .value("手取り", summary.netTotal)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Int.self) {
                                    Text(shortYenText(amount))
                                }
                            }
                        }
                    }
                    .frame(height: 190)
                }
            }
        }
    }

    private var latestMonthSection: some View {
        homeCard(tint: .blue) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "\(latestMonthSummary.longLabel)の給与",
                    subtitle: latestMonthSummary.records.isEmpty ? "この月の給与明細はまだありません" : "\(latestMonthSummary.records.count)件の給与明細"
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summaryItem(title: "額面", value: yenText(latestMonthSummary.grossTotal))
                    summaryItem(title: "手取り", value: yenText(latestMonthSummary.netTotal))
                    summaryItem(title: "控除", value: yenText(latestMonthSummary.deductionTotal))
                    summaryItem(title: "給与明細", value: "\(latestMonthSummary.records.count)件")
                }
            }
        }
    }

    private var yearSummarySection: some View {
        homeCard(tint: .indigo) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $selectedYear, in: 2000...2100) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(selectedYear)年の合計")
                            .font(.headline)
                        Text("税務・書類整理で使う年別の集計")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    compactAmount("額面", selectedYearSummary.grossTotal)
                    compactAmount("手取り", selectedYearSummary.netTotal)
                    compactAmount("控除", selectedYearSummary.deductionTotal)
                }
            }
        }
    }

    private func compactAmount(_ title: String, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(shortYenText(amount))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var recentRecordsSection: some View {
        homeCard(tint: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "最近の給与明細", subtitle: "登録した給与明細をすぐ確認")

                if recentRecords.isEmpty {
                    Text("給与明細を登録すると、直近5件がここに表示されます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentRecords) { record in
                            NavigationLink {
                                PayRecordDetailView(payRecord: record)
                            } label: {
                                HStack(spacing: 12) {
                                    RecentPayRecordRow(record: record)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)

                            if record.persistentModelID != recentRecords.last?.persistentModelID {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var documentAlertSection: some View {
        homeCard(tint: .orange) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("書類チェック", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Spacer()
                    Text("\(documentAttachments.count)件")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(documentAttachments.isEmpty ? "書類を登録すると、ここに保存件数が表示されます。" : "源泉徴収票・支払調書の登録状況は、書類タブで確認できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func homeCard<Content: View>(tint _: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .shadow(color: Color.cyan.opacity(0.08), radius: 10, y: 4)
            )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MonthKey: Hashable {
    let year: Int
    let month: Int

    func addingMonths(_ offset: Int) -> MonthKey {
        let zeroBasedIndex = year * 12 + (month - 1) + offset
        return MonthKey(year: zeroBasedIndex / 12, month: zeroBasedIndex % 12 + 1)
    }
}

private struct HomeMonthSummary: Identifiable {
    let key: MonthKey
    let records: [PayRecord]

    var id: MonthKey { key }
    var shortLabel: String { "\(key.month)月" }
    var longLabel: String { "\(key.year)年\(key.month)月" }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmount } }
    var deductionTotal: Int { records.reduce(0) { $0 + ($1.deductionAmount ?? max($1.grossAmount - $1.netAmount, 0)) } }

}

private struct HomeYearSummary {
    let year: Int
    let records: [PayRecord]

    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmount } }
    var deductionTotal: Int { records.reduce(0) { $0 + ($1.deductionAmount ?? max($1.grossAmount - $1.netAmount, 0)) } }
}

private struct RecentPayRecordRow: View {
    let record: PayRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: "\(record.paymentYear)年\(record.paymentMonth)月")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.incomeCategory.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(record.employer?.name ?? "勤務先未設定")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("額面 \(yenText(record.grossAmount))")
                Spacer()
                Text("手取り \(yenText(record.netAmount))")
                    .foregroundStyle(.teal)
            }
            .font(.caption)
        }
        .padding(.vertical, 10)
    }
}

private func yenText(_ amount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return "\(formatter.string(from: NSNumber(value: amount)) ?? String(amount))円"
}

private func shortYenText(_ amount: Int) -> String {
    if amount >= 10_000 {
        let value = Double(amount) / 10_000
        return String(format: "%.1f万円", value)
    }
    return yenText(amount)
}
