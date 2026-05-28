import Charts
import SwiftData
import SwiftUI

struct AnalysisView: View {
    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @Query private var appSettings: [AppSettings]

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

    private var annualSummaries: [AnalysisPeriodSummary] {
        let latestPeriod = max(selectedPeriod, payRecords.map {
            periodKey(for: $0, viewMode: viewMode, fiscalYearStartMonth: fiscalYearStartMonth)
        }.max() ?? selectedPeriod)

        return (0..<5).reversed().map { offset in
            let period = latestPeriod - offset
            let records = payRecords.filter {
                periodKey(for: $0, viewMode: viewMode, fiscalYearStartMonth: fiscalYearStartMonth) == period
            }
            return AnalysisPeriodSummary(
                period: period,
                label: periodLabel(for: period),
                records: records
            )
        }
    }

    private var annualStackItems: [StackedAmountItem] {
        annualSummaries.flatMap { summary in
            [
                StackedAmountItem(
                    id: "\(summary.period)-net",
                    label: summary.label,
                    kind: .net,
                    amount: summary.netTotal
                ),
                StackedAmountItem(
                    id: "\(summary.period)-deduction",
                    label: summary.label,
                    kind: .deduction,
                    amount: summary.deductionTotal
                )
            ]
        }
    }

    private var monthlySummaries: [AnalysisMonthSummary] {
        orderedMonths.map { month in
            let records = selectedRecords.filter { $0.paymentMonth == month }
            return AnalysisMonthSummary(month: month, label: "\(month)月", records: records)
        }
    }

    private var monthlyChartItems: [GroupedAmountItem] {
        monthlySummaries.flatMap { summary in
            [
                GroupedAmountItem(
                    id: "\(summary.month)-gross",
                    label: summary.label,
                    kind: .gross,
                    amount: summary.grossTotal
                ),
                GroupedAmountItem(
                    id: "\(summary.month)-net",
                    label: summary.label,
                    kind: .net,
                    amount: summary.netTotal
                ),
                GroupedAmountItem(
                    id: "\(summary.month)-deduction",
                    label: summary.label,
                    kind: .deduction,
                    amount: summary.deductionTotal
                )
            ]
        }
    }

    private var employerSummaries: [BreakdownSummary] {
        Dictionary(grouping: selectedRecords, by: { $0.employer?.name ?? "勤務先未設定" })
            .map { employerName, records in
                BreakdownSummary(label: employerName, records: records)
            }
            .sorted {
                if $0.grossTotal == $1.grossTotal {
                    return $0.label.localizedStandardCompare($1.label) == .orderedAscending
                }
                return $0.grossTotal > $1.grossTotal
            }
    }

    private var incomeCategorySummaries: [BreakdownSummary] {
        IncomeCategoryAnalysisGroup.allCases.compactMap { group in
            let records = selectedRecords.filter { group.categories.contains($0.incomeCategory) }
            guard !records.isEmpty else {
                return nil
            }
            return BreakdownSummary(label: group.label, records: records)
        }
        .sorted {
            if $0.grossTotal == $1.grossTotal {
                return $0.label.localizedStandardCompare($1.label) == .orderedAscending
            }
            return $0.grossTotal > $1.grossTotal
        }
    }

    private var orderedMonths: [Int] {
        switch viewMode {
        case .calendarYear:
            return Array(1...12)
        case .fiscalYear:
            return Array(fiscalYearStartMonth...12) + Array(1..<fiscalYearStartMonth)
        }
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

                if payRecords.isEmpty {
                    emptyState
                } else {
                    annualTrendSection
                    monthlyTrendSection
                    breakdownSection
                }
            }
            .padding()
        }
        .navigationTitle("分析")
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

    private var emptyState: some View {
        ContentUnavailableView(
            "分析できる明細がありません",
            systemImage: "chart.bar.xaxis",
            description: Text("給与明細を登録すると、収入推移と内訳を確認できます。")
        )
        .frame(minHeight: 260)
    }

    private var annualTrendSection: some View {
        analysisCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "年次推移",
                    subtitle: "手取り + 控除 = 額面として直近5期間を比較"
                )

                Chart(annualStackItems) { item in
                    BarMark(
                        x: .value("期間", item.label),
                        y: .value("金額", item.amount)
                    )
                    .foregroundStyle(by: .value("区分", item.kind.label))
                }
                .chartForegroundStyleScale([
                    AmountKind.net.label: .green,
                    AmountKind.deduction.label: .orange
                ])
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
                .frame(height: 240)

                VStack(spacing: 0) {
                    ForEach(annualSummaries) { summary in
                        PeriodSummaryRow(summary: summary)

                        if summary.id != annualSummaries.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var monthlyTrendSection: some View {
        analysisCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "月別推移",
                    subtitle: "\(selectedPeriodTitle)の額面・手取り・控除"
                )

                if selectedRecords.isEmpty {
                    Text("この期間の明細はまだありません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    Chart(monthlyChartItems) { item in
                        BarMark(
                            x: .value("月", item.label),
                            y: .value("金額", item.amount)
                        )
                        .foregroundStyle(by: .value("区分", item.kind.label))
                        .position(by: .value("区分", item.kind.label))
                    }
                    .chartForegroundStyleScale([
                        AmountKind.gross.label: .blue,
                        AmountKind.net.label: .green,
                        AmountKind.deduction.label: .orange
                    ])
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
                    .frame(height: 260)
                }
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "内訳分析",
                subtitle: "\(selectedPeriodTitle)の勤務先別・収入区分別の比較"
            )
            employerBreakdownSection
            incomeCategoryBreakdownSection
        }
    }

    private var employerBreakdownSection: some View {
        analysisCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "勤務先別",
                    subtitle: "\(selectedPeriodTitle)の勤務先ごとの収入"
                )

                breakdownContent(
                    summaries: employerSummaries,
                    emptyMessage: "この期間の勤務先別データはまだありません。"
                )
            }
        }
    }

    private var incomeCategoryBreakdownSection: some View {
        analysisCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "収入区分別",
                    subtitle: "\(selectedPeriodTitle)の収入区分ごとの内訳"
                )

                breakdownContent(
                    summaries: incomeCategorySummaries,
                    emptyMessage: "この期間の収入区分別データはまだありません。"
                )
            }
        }
    }

    private func breakdownContent(summaries: [BreakdownSummary], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if summaries.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                Chart(summaries.prefix(8).map { $0 }) { summary in
                    BarMark(
                        x: .value("額面", summary.grossTotal),
                        y: .value("項目", summary.label)
                    )
                    .foregroundStyle(.blue)
                    .annotation(position: .trailing) {
                        Text(shortYenText(summary.grossTotal))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Int.self) {
                                Text(shortYenText(amount))
                            }
                        }
                    }
                }
                .frame(height: max(180, CGFloat(min(summaries.count, 8)) * 36))

                VStack(spacing: 0) {
                    ForEach(summaries) { summary in
                        BreakdownRow(summary: summary)

                        if summary.id != summaries.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func analysisCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
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

private struct AnalysisPeriodSummary: Identifiable {
    let period: Int
    let label: String
    let records: [PayRecord]

    var id: Int {
        period
    }

    var grossTotal: Int {
        records.reduce(0) { $0 + $1.grossAmount }
    }

    var netTotal: Int {
        records.reduce(0) { $0 + $1.netAmount }
    }

    var deductionTotal: Int {
        records.reduce(0) { $0 + deductionAmount(for: $1) }
    }

    var takeHomeRateText: String {
        guard grossTotal > 0 else {
            return "-"
        }

        let rate = Double(netTotal) / Double(grossTotal) * 100
        return String(format: "%.1f%%", rate)
    }
}

private struct AnalysisMonthSummary: Identifiable {
    let month: Int
    let label: String
    let records: [PayRecord]

    var id: Int {
        month
    }

    var grossTotal: Int {
        records.reduce(0) { $0 + $1.grossAmount }
    }

    var netTotal: Int {
        records.reduce(0) { $0 + $1.netAmount }
    }

    var deductionTotal: Int {
        records.reduce(0) { $0 + deductionAmount(for: $1) }
    }
}

private struct BreakdownSummary: Identifiable {
    let label: String
    let records: [PayRecord]

    var id: String {
        label
    }

    var grossTotal: Int {
        records.reduce(0) { $0 + $1.grossAmount }
    }

    var netTotal: Int {
        records.reduce(0) { $0 + $1.netAmount }
    }

    var count: Int {
        records.count
    }
}

private struct StackedAmountItem: Identifiable {
    let id: String
    let label: String
    let kind: AmountKind
    let amount: Int
}

private struct GroupedAmountItem: Identifiable {
    let id: String
    let label: String
    let kind: AmountKind
    let amount: Int
}

private enum AmountKind {
    case gross
    case net
    case deduction

    var label: String {
        switch self {
        case .gross:
            "額面"
        case .net:
            "手取り"
        case .deduction:
            "控除"
        }
    }
}

private enum IncomeCategoryAnalysisGroup: CaseIterable {
    case fullTimeSalary
    case partTimeSalary
    case duty
    case spot
    case bonus
    case other

    var label: String {
        switch self {
        case .fullTimeSalary:
            "常勤給与"
        case .partTimeSalary:
            "外勤"
        case .duty:
            "当直・日当直"
        case .spot:
            "スポット"
        case .bonus:
            "賞与"
        case .other:
            "その他"
        }
    }

    var categories: [IncomeCategory] {
        switch self {
        case .fullTimeSalary:
            [.fullTimeSalary]
        case .partTimeSalary:
            [.partTimeSalary]
        case .duty:
            [.nightDuty, .dayNightDuty]
        case .spot:
            [.spot]
        case .bonus:
            [.bonus]
        case .other:
            [.other]
        }
    }
}

private struct PeriodSummaryRow: View {
    let summary: AnalysisPeriodSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("手取り率 \(summary.takeHomeRateText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                amountText("額面", summary.grossTotal)
                Spacer()
                amountText("手取り", summary.netTotal)
                Spacer()
                amountText("控除", summary.deductionTotal)
            }
        }
        .padding(.vertical, 10)
    }

    private func amountText(_ title: String, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(yenText(amount))
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct BreakdownRow: View {
    let summary: BreakdownSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(summary.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                amountText("額面", summary.grossTotal)
                Spacer()
                amountText("手取り", summary.netTotal)
            }
        }
        .padding(.vertical, 10)
    }

    private func amountText(_ title: String, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(yenText(amount))
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private func deductionAmount(for record: PayRecord) -> Int {
    record.deductionAmount ?? max(record.grossAmount - record.netAmount, 0)
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
