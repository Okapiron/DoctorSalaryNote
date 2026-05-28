import Charts
import SwiftData
import SwiftUI

struct HomeSummaryView: View {
    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @Query private var appSettings: [AppSettings]
    @Query private var documentAttachments: [DocumentAttachment]

    @State private var viewMode: ViewMode = .calendarYear
    @State private var selectedPeriod: Int = Calendar.current.component(.year, from: Date())

    private var fiscalYearStartMonth: Int {
        let configuredMonth = appSettings.first?.fiscalYearStartMonth ?? 4
        return min(max(configuredMonth, 1), 12)
    }

    private var selectedPeriodTitle: String {
        switch viewMode {
        case .calendarYear:
            "\(selectedPeriod)年"
        case .fiscalYear:
            "\(selectedPeriod)年度"
        }
    }

    private var selectedRecords: [PayRecord] {
        payRecords.filter {
            periodKey(for: $0, viewMode: viewMode, fiscalYearStartMonth: fiscalYearStartMonth) == selectedPeriod
        }
    }

    private var summary: HomeSummary {
        HomeSummary(records: selectedRecords)
    }

    private var chartItems: [GrossTrendItem] {
        let latestPeriod = max(selectedPeriod, payRecords.map {
            periodKey(for: $0, viewMode: viewMode, fiscalYearStartMonth: fiscalYearStartMonth)
        }.max() ?? selectedPeriod)

        return (0..<5).reversed().map { offset in
            let period = latestPeriod - offset
            let grossAmount = payRecords
                .filter { periodKey(for: $0, viewMode: viewMode, fiscalYearStartMonth: fiscalYearStartMonth) == period }
                .reduce(0) { $0 + $1.grossAmount }

            return GrossTrendItem(
                period: period,
                label: periodLabel(for: period),
                grossAmount: grossAmount
            )
        }
    }

    private var recentRecords: [PayRecord] {
        Array(payRecords.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("表示方法", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewMode) { _, newMode in
                    selectedPeriod = currentPeriod(for: newMode)
                }

                periodSelector

                grossTrendSection
                summarySection
                recentRecordsSection
                documentAlertSection
            }
            .padding()
        }
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

    private var periodSelector: some View {
        Stepper(value: $selectedPeriod, in: 2000...2100) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedPeriodTitle)
                    .font(.title2.weight(.semibold))
                Text(periodDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var periodDescription: String {
        switch viewMode {
        case .calendarYear:
            "1月〜12月"
        case .fiscalYear:
            fiscalYearStartMonth == 1 ? "1月〜12月" : "\(fiscalYearStartMonth)月〜翌\(fiscalYearStartMonth - 1)月"
        }
    }

    private var grossTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("額面推移")
                    .font(.headline)
                Text("直近5期間の額面合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if payRecords.isEmpty {
                ContentUnavailableView(
                    "給与明細を登録すると、ここに額面推移が表示されます",
                    systemImage: "chart.bar"
                )
                .frame(minHeight: 180)
            } else {
                Chart(chartItems) { item in
                    BarMark(
                        x: .value("期間", item.label),
                        y: .value("額面", item.grossAmount)
                    )
                    .foregroundStyle(.blue)
                    .annotation(position: .top) {
                        if item.grossAmount > 0 {
                            Text(shortYenText(item.grossAmount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
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
                .frame(height: 220)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selectedPeriodTitle)のサマリー")
                    .font(.headline)

                if selectedRecords.isEmpty {
                    Text("この期間の明細はまだありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryItem(title: "額面合計", value: yenText(summary.grossTotal))
                summaryItem(title: "手取り合計", value: yenText(summary.netTotal))
                summaryItem(title: "控除合計", value: yenText(summary.deductionTotal))
                summaryItem(title: "手取り率", value: summary.takeHomeRateText)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
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
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近の明細")
                .font(.headline)

            if recentRecords.isEmpty {
                Text("給与明細を登録すると、最近の明細がここに表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentRecords) { record in
                        NavigationLink {
                            PayRecordFormView(payRecord: record)
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
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }

    private var documentAlertSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("書類チェック", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text("\(documentAttachments.count)件")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("源泉徴収票・支払調書の登録状況は、書類タブで確認できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("年別・勤務先別に整理できます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }

    private func currentPeriod(for mode: ViewMode) -> Int {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        switch mode {
        case .calendarYear:
            return year
        case .fiscalYear:
            return month >= fiscalYearStartMonth ? year : year - 1
        }
    }

    private func periodKey(for record: PayRecord, viewMode: ViewMode, fiscalYearStartMonth: Int) -> Int {
        switch viewMode {
        case .calendarYear:
            return record.paymentYear
        case .fiscalYear:
            return record.paymentMonth >= fiscalYearStartMonth ? record.paymentYear : record.paymentYear - 1
        }
    }

    private func periodLabel(for period: Int) -> String {
        switch viewMode {
        case .calendarYear:
            return "\(period)年"
        case .fiscalYear:
            return "\(period)年度"
        }
    }
}

private struct HomeSummary {
    let grossTotal: Int
    let netTotal: Int
    let deductionTotal: Int

    init(records: [PayRecord]) {
        grossTotal = records.reduce(0) { $0 + $1.grossAmount }
        netTotal = records.reduce(0) { $0 + $1.netAmount }
        deductionTotal = records.reduce(0) { partialResult, record in
            partialResult + (record.deductionAmount ?? max(record.grossAmount - record.netAmount, 0))
        }
    }

    var takeHomeRateText: String {
        guard grossTotal > 0 else {
            return "-"
        }

        let rate = Double(netTotal) / Double(grossTotal) * 100
        return String(format: "%.1f%%", rate)
    }
}

private struct GrossTrendItem: Identifiable {
    let period: Int
    let label: String
    let grossAmount: Int

    var id: Int {
        period
    }
}

private struct RecentPayRecordRow: View {
    let record: PayRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(record.paymentYear)年\(record.paymentMonth)月")
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
                    .foregroundStyle(.secondary)
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
