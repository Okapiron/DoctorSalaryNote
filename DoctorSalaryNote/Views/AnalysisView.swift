import Charts
import SwiftData
import SwiftUI

struct AnalysisView: View {
    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var trendScope: AnalysisTrendScope = .monthly

    private var selectedYearTitle: String {
        "\(selectedYear)年"
    }

    private var selectedRecords: [PayRecord] {
        payRecords.filter { $0.paymentYear == selectedYear }
    }

    private var annualSummaries: [AnalysisPeriodSummary] {
        let latestYear = max(selectedYear, payRecords.map(\.paymentYear).max() ?? selectedYear)

        return (0..<5).reversed().map { offset in
            let year = latestYear - offset
            let records = payRecords.filter { $0.paymentYear == year }
            return AnalysisPeriodSummary(period: year, label: "\(year)年", records: records)
        }
    }

    private var annualStackItems: [StackedAmountItem] {
        annualSummaries.flatMap { summary in
            [
                StackedAmountItem(id: "\(summary.period)-net", label: summary.label, kind: .net, amount: summary.netTotal),
                StackedAmountItem(id: "\(summary.period)-deduction", label: summary.label, kind: .deduction, amount: summary.deductionTotal)
            ]
        }
    }

    private var monthlySummaries: [AnalysisMonthSummary] {
        (1...12).map { month in
            let records = selectedRecords.filter { $0.paymentMonth == month }
            return AnalysisMonthSummary(month: month, label: "\(month)月", records: records)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                yearSelector

                if payRecords.isEmpty {
                    emptyState
                } else {
                    trendSection
                    breakdownSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("分析")
    }

    private var yearSelector: some View {
        analysisCard(tint: .teal) {
            Stepper(value: $selectedYear, in: 2000...2100) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(selectedYear)年")
                        .font(.title3.weight(.semibold))
                    Text("年別で収入の推移と内訳を確認します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "分析できる明細がありません",
            systemImage: "chart.bar.xaxis",
            description: Text("給与明細を登録すると、月別推移、年次推移、勤務先別・収入区分別の内訳を確認できます。")
        )
        .frame(minHeight: 260)
    }

    private var trendSection: some View {
        analysisCard(tint: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "推移",
                    subtitle: trendScope == .monthly ? "\(selectedYearTitle)の月別推移" : "直近5年の手取り・控除"
                )

                Picker("推移", selection: $trendScope) {
                    ForEach(AnalysisTrendScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                switch trendScope {
                case .monthly:
                    monthlyTrendContent
                case .annual:
                    annualTrendContent
                }
            }
        }
    }

    private var annualTrendContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(annualStackItems) { item in
                BarMark(
                    x: .value("年", item.label),
                    y: .value("金額", item.amount)
                )
                .foregroundStyle(by: .value("区分", item.kind.label))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale([
                AmountKind.net.label: .blue,
                AmountKind.deduction.label: .gray.opacity(0.55)
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
            .frame(height: 180)

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

    private var monthlyTrendContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedRecords.isEmpty {
                Text("この年の明細はまだありません。年を切り替えるか、明細を追加してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                Chart {
                    ForEach(monthlySummaries) { summary in
                        BarMark(
                            x: .value("月", summary.label),
                            y: .value("額面", summary.grossTotal)
                        )
                        .foregroundStyle(.cyan.gradient)
                        .cornerRadius(4)
                    }

                    ForEach(monthlySummaries) { summary in
                        LineMark(
                            x: .value("月", summary.label),
                            y: .value("手取り", summary.netTotal)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("月", summary.label),
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
                .frame(height: 220)

                HStack(spacing: 12) {
                    LegendDot(color: .cyan, text: "額面")
                    LegendDot(color: .blue, text: "手取り")
                    Text("控除は下の月別一覧で確認")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                VStack(spacing: 0) {
                    ForEach(monthlySummaries.filter { !$0.records.isEmpty }) { summary in
                        MonthSummaryRow(summary: summary)

                        if summary.id != monthlySummaries.filter({ !$0.records.isEmpty }).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "内訳分析",
                subtitle: "\(selectedYearTitle)の勤務先別・収入区分別"
            )
            employerBreakdownSection
            incomeCategoryBreakdownSection
        }
    }

    private var employerBreakdownSection: some View {
        analysisCard(tint: .indigo) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "勤務先別", subtitle: "勤務先ごとの額面・手取り")
                breakdownContent(
                    summaries: employerSummaries,
                    emptyMessage: "この年の勤務先別データはまだありません。"
                )
            }
        }
    }

    private var incomeCategoryBreakdownSection: some View {
        analysisCard(tint: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "収入区分別", subtitle: "常勤、外勤、当直、賞与などの比較")
                breakdownContent(
                    summaries: incomeCategorySummaries,
                    emptyMessage: "この年の収入区分別データはまだありません。"
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
                    .foregroundStyle(.cyan.gradient)
                    .cornerRadius(4)
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
                .frame(height: max(170, CGFloat(min(summaries.count, 8)) * 34))

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

    private func analysisCard<Content: View>(tint _: Color, @ViewBuilder content: () -> Content) -> some View {
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

private enum AnalysisTrendScope: String, CaseIterable, Identifiable {
    case monthly
    case annual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: "月別"
        case .annual: "年次"
        }
    }
}

private struct AnalysisPeriodSummary: Identifiable {
    let period: Int
    let label: String
    let records: [PayRecord]

    var id: Int { period }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmount } }
    var deductionTotal: Int { records.reduce(0) { $0 + deductionAmount(for: $1) } }

}

private struct AnalysisMonthSummary: Identifiable {
    let month: Int
    let label: String
    let records: [PayRecord]

    var id: Int { month }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmount } }
    var deductionTotal: Int { records.reduce(0) { $0 + deductionAmount(for: $1) } }
}

private struct BreakdownSummary: Identifiable {
    let label: String
    let records: [PayRecord]

    var id: String { label }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmount } }
    var count: Int { records.count }
}

private struct StackedAmountItem: Identifiable {
    let id: String
    let label: String
    let kind: AmountKind
    let amount: Int
}

private enum AmountKind {
    case net
    case deduction

    var label: String {
        switch self {
        case .net: "手取り"
        case .deduction: "控除"
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
        case .fullTimeSalary: "常勤給与"
        case .partTimeSalary: "外勤"
        case .duty: "当直・日当直"
        case .spot: "スポット"
        case .bonus: "賞与"
        case .other: "その他"
        }
    }

    var categories: [IncomeCategory] {
        switch self {
        case .fullTimeSalary: [.fullTimeSalary]
        case .partTimeSalary: [.partTimeSalary]
        case .duty: [.nightDuty, .dayNightDuty]
        case .spot: [.spot]
        case .bonus: [.bonus]
        case .other: [.other]
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
                Text("\(summary.records.count)件")
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
        .padding(.vertical, 8)
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

private struct MonthSummaryRow: View {
    let summary: AnalysisMonthSummary

    var body: some View {
        HStack {
            Text(summary.label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 42, alignment: .leading)
            amountText("額面", summary.grossTotal)
            Spacer()
            amountText("手取り", summary.netTotal)
            Spacer()
            amountText("控除", summary.deductionTotal)
        }
        .padding(.vertical, 8)
    }

    private func amountText(_ title: String, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(shortYenText(amount))
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
        .padding(.vertical, 8)
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

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(.secondary)
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
