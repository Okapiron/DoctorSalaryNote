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

    private var selectedYearGrossTotal: Int {
        selectedRecords.reduce(0) { $0 + $1.grossAmount }
    }

    private var annualSummaries: [AnalysisPeriodSummary] {
        let latestYear = max(selectedYear, payRecords.map(\.paymentYear).max() ?? selectedYear)

        return (0..<5).reversed().map { offset in
            let year = latestYear - offset
            let records = payRecords.filter { $0.paymentYear == year }
            return AnalysisPeriodSummary(period: year, label: "\(year)年", records: records)
        }
    }

    private var monthlySummaries: [AnalysisMonthSummary] {
        (1...12).map { month in
            let records = selectedRecords.filter { $0.paymentMonth == month }
            return AnalysisMonthSummary(month: month, label: "\(month)月", records: records)
        }
    }

    private var annualTrendPoints: [TrendPoint] {
        annualSummaries.map {
            TrendPoint(id: "\($0.period)", label: $0.label, grossTotal: $0.grossTotal, netTotal: $0.netTotal)
        }
    }

    private var monthlyTrendPoints: [TrendPoint] {
        monthlySummaries.map {
            TrendPoint(id: "\($0.month)", label: $0.label, grossTotal: $0.grossTotal, netTotal: $0.netTotal)
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
            "分析できる給与明細がありません",
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
                    subtitle: trendScope == .monthly ? "\(selectedYearTitle)の月別推移" : "直近5年の推移"
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
            trendDataChart(points: annualTrendPoints)

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
                Text("この年の給与明細はまだありません。年を切り替えるか、給与明細を追加してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                trendDataChart(points: monthlyTrendPoints)

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
                sectionHeader(title: "勤務先別", subtitle: "額面バーと手取り位置で比較")
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
                sectionHeader(title: "収入区分別", subtitle: "常勤給与、賞与、外勤、スポット、その他の比較")
                breakdownContent(
                    summaries: incomeCategorySummaries,
                    emptyMessage: "この年の収入区分別データはまだありません。"
                )
            }
        }
    }

    private func breakdownContent(summaries: [BreakdownSummary], emptyMessage: String) -> some View {
        let visibleSummaries = Array(summaries.prefix(8))
        let yearlyGrossTotal = max(selectedYearGrossTotal, 1)

        return VStack(alignment: .leading, spacing: 12) {
            if summaries.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(visibleSummaries.enumerated()), id: \.element.id) { index, summary in
                        InfographicBreakdownRow(
                            rank: index + 1,
                            summary: summary,
                            yearlyGrossTotal: yearlyGrossTotal
                        )
                    }
                }

                HStack(spacing: 12) {
                    LegendDot(color: .cyan, text: "額面")
                    LegendDot(color: .blue, text: "手取り")
                }
                .font(.caption)

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

    private func trendDataChart(points: [TrendPoint]) -> some View {
        let maxAmount = max(points.map(\.grossTotal).max() ?? 0, points.map(\.netTotal).max() ?? 0)
        let axisMax = niceAxisMax(for: maxAmount)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                LegendDot(color: .cyan, text: "額面")
                LegendDot(color: .blue, text: "手取り")
            }
            .font(.caption)

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("期間", point.label),
                        y: .value("総支給額", point.grossTotal),
                        width: .ratio(points.count > 8 ? 0.42 : 0.56)
                    )
                    .foregroundStyle(Color.cyan.opacity(0.72))
                    .cornerRadius(3)
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("期間", point.label),
                        y: .value("手取り", point.netTotal)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.linear)
                    .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("期間", point.label),
                        y: .value("手取り", point.netTotal)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(24)
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: 0...axisMax)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color(.systemGray5))
                    AxisTick()
                        .foregroundStyle(Color(.systemGray4))
                    AxisValueLabel {
                        if let amount = value.as(Int.self) {
                            Text(compactChartAmountText(amount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: points.map(\.label)) { value in
                    AxisTick()
                        .foregroundStyle(Color(.systemGray4))
                    AxisValueLabel(anchor: .top) {
                        if let label = value.as(String.self) {
                            Text(compactAxisLabel(label))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color(.systemBackground))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()
        }
    }
}

private struct TrendPoint: Identifiable {
    let id: String
    let label: String
    let grossTotal: Int
    let netTotal: Int
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
    var deductionTotal: Int { records.reduce(0) { $0 + deductionAmount(for: $1) } }
    var count: Int { records.count }
}

private enum IncomeCategoryAnalysisGroup: CaseIterable {
    case fullTimeSalary
    case bonus
    case partTimeSalary
    case spot
    case other

    var label: String {
        switch self {
        case .fullTimeSalary: "常勤給与"
        case .partTimeSalary: "外勤"
        case .spot: "スポット"
        case .bonus: "賞与"
        case .other: "その他"
        }
    }

    var categories: [IncomeCategory] {
        switch self {
        case .fullTimeSalary: [.fullTimeSalary]
        case .partTimeSalary: [.partTimeSalary]
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

private struct InfographicBreakdownRow: View {
    let rank: Int
    let summary: BreakdownSummary
    let yearlyGrossTotal: Int

    private var grossRatio: Double {
        guard yearlyGrossTotal > 0 else { return 0 }
        return min(Double(summary.grossTotal) / Double(yearlyGrossTotal), 1)
    }

    private var netRatio: Double {
        guard yearlyGrossTotal > 0 else { return 0 }
        return min(Double(summary.netTotal) / Double(yearlyGrossTotal), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", rank))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                    .monospacedDigit()

                Text(summary.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(shortYenText(summary.grossTotal))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let grossWidth = max(width * grossRatio, summary.grossTotal > 0 ? 10 : 0)
                let markerX = min(max(width * netRatio, 5), width - 5)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.46), Color.cyan.opacity(0.88)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: grossWidth)

                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        }
                        .offset(x: markerX - 5)
                }
            }
            .frame(height: 12)

            HStack {
                Spacer()
                Text("手取り \(shortYenText(summary.netTotal))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
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

private func compactAxisLabel(_ label: String) -> String {
    label
        .replacingOccurrences(of: "月", with: "")
        .replacingOccurrences(of: "年", with: "")
}

private func compactChartAmountText(_ amount: Int) -> String {
    let value = amount >= 10_000 ? amount / 10_000 : amount
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private func niceAxisMax(for amount: Int) -> Int {
    guard amount > 0 else {
        return 100_000
    }

    let magnitude = pow(10.0, floor(log10(Double(amount))))
    let normalized = Double(amount) / magnitude
    let niceNormalized: Double

    if normalized <= 1.0 {
        niceNormalized = 1.0
    } else if normalized <= 2.0 {
        niceNormalized = 2.0
    } else if normalized <= 5.0 {
        niceNormalized = 5.0
    } else {
        niceNormalized = 10.0
    }

    return Int(niceNormalized * magnitude)
}
