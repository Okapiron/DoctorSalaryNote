import Charts
import SwiftData
import SwiftUI

struct AnalysisView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var trendScope: AnalysisTrendScope = .monthly
    @State private var pendingScrollTarget: AnalysisScrollTarget?

    private let scrollRetentionAnchor = UnitPoint(x: 0.5, y: 0.12)

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
        return (0..<5).reversed().map { offset in
            let year = selectedYear - offset
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
            TrendPoint(
                id: "\($0.period)",
                label: $0.label,
                grossTotal: $0.grossTotal,
                netTotal: $0.netTotal,
                hasData: !$0.records.isEmpty,
                hasNetAmount: $0.hasNetAmount
            )
        }
    }

    private var monthlyTrendPoints: [TrendPoint] {
        monthlySummaries.map {
            TrendPoint(
                id: "\($0.month)",
                label: $0.label,
                grossTotal: $0.grossTotal,
                netTotal: $0.netTotal,
                hasData: !$0.records.isEmpty,
                hasNetAmount: $0.hasNetAmount
            )
        }
    }

    private var monthlyAxisMax: Int {
        let grouped = Dictionary(grouping: payRecords) { record in
            "\(record.paymentYear)-\(record.paymentMonth)"
        }
        let maxAmount = grouped.values
            .map { records in
                max(
                    records.reduce(0) { $0 + $1.grossAmount },
                    records.reduce(0) { $0 + $1.netAmountForAggregation }
                )
            }
            .max() ?? 0

        return niceAxisMax(for: maxAmount)
    }

    private var annualAxisMax: Int {
        let grouped = Dictionary(grouping: payRecords, by: \.paymentYear)
        let maxAmount = grouped.values
            .map { records in
                max(
                    records.reduce(0) { $0 + $1.grossAmount },
                    records.reduce(0) { $0 + $1.netAmountForAggregation }
                )
            }
            .max() ?? 0

        return niceAxisMax(for: maxAmount)
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if payRecords.isEmpty {
                        emptyState
                    } else {
                        trendSection
                            .id(AnalysisScrollTarget.trend)
                        breakdownSection
                    }
                }
                .padding()
            }
            .background(EditorialStyle.pageBackground)
            .navigationTitle("分析")
            .navigationBarTitleDisplayMode(.inline)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
            .onChange(of: pendingScrollTarget) { _, target in
                guard let target else {
                    return
                }

                DispatchQueue.main.async {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(target, anchor: scrollRetentionAnchor)
                        pendingScrollTarget = nil
                    }
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
            VStack(alignment: .leading, spacing: 14) {
                yearControlHeader(
                    title: "推移",
                    subtitle: trendScope == .monthly ? "\(selectedYearTitle)の月別推移" : "\(selectedYearTitle)までの5年推移",
                    scrollTarget: .trend
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
        .simultaneousGesture(yearSwipeGesture(keeping: .trend))
    }

    private var annualTrendContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            trendDataChart(points: annualTrendPoints, axisMax: annualAxisMax)

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
                trendDataChart(points: monthlyTrendPoints, axisMax: monthlyAxisMax)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Spacer(minLength: 0)
                    Text(verbatim: "\(selectedYear)年合計")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(yenText(selectedYearGrossTotal))
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 2)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("月")
                            .frame(width: 40, alignment: .leading)
                        Text("額面")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("手取り")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("控除")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)

                    Divider()

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
                subtitle: "勤務先や収入区分ごとの収入を比較"
            )
            employerBreakdownSection
            incomeCategoryBreakdownSection
        }
    }

    private var employerBreakdownSection: some View {
        analysisCard(tint: .indigo) {
            VStack(alignment: .leading, spacing: 12) {
                yearControlHeader(title: "勤務先別", subtitle: "\(selectedYearTitle)の勤務先別", scrollTarget: .employer)
                breakdownContent(
                    summaries: employerSummaries,
                    emptyMessage: "この年の勤務先別データはまだありません。"
                )
            }
        }
        .id(AnalysisScrollTarget.employer)
        .simultaneousGesture(yearSwipeGesture(keeping: .employer))
    }

    private var incomeCategoryBreakdownSection: some View {
        analysisCard(tint: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                yearControlHeader(title: "収入区分別", subtitle: "\(selectedYearTitle)の収入区分別", scrollTarget: .incomeCategory)
                breakdownContent(
                    summaries: incomeCategorySummaries,
                    emptyMessage: "この年の収入区分別データはまだありません。"
                )
            }
        }
        .id(AnalysisScrollTarget.incomeCategory)
        .simultaneousGesture(yearSwipeGesture(keeping: .incomeCategory))
    }

    private func breakdownContent(summaries: [BreakdownSummary], emptyMessage: String) -> some View {
        let visibleSummaries = Array(summaries.prefix(8))
        let yearlyGrossTotal = max(selectedYearGrossTotal, 1)

        return VStack(alignment: .leading, spacing: 14) {
            if summaries.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(visibleSummaries.enumerated()), id: \.element.id) { index, summary in
                        InfographicBreakdownRow(
                            rank: index + 1,
                            summary: summary,
                            yearlyGrossTotal: yearlyGrossTotal
                        )
                    }
                }

                HStack(spacing: 12) {
                    LegendMark(color: appTheme.chartGrossColor, text: "額面", shape: .bar)
                    LegendMark(color: appTheme.chartNetColor, text: "手取り", shape: .point)
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
        EditorialCard(content: content)
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

    private func yearControlHeader(title: String, subtitle: String, scrollTarget: AnalysisScrollTarget) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    moveSelectedYear(by: -1, keeping: scrollTarget)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("前年へ")

                Text(verbatim: "\(selectedYear)年")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    moveSelectedYear(by: 1, keeping: scrollTarget)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("翌年へ")
            }
            .foregroundStyle(appTheme.accentColor)
        }
    }

    private func yearSwipeGesture(keeping scrollTarget: AnalysisScrollTarget) -> some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height

                guard abs(horizontalDistance) > abs(verticalDistance),
                      abs(horizontalDistance) > 48 else {
                    return
                }

                if horizontalDistance < 0 {
                    moveSelectedYear(by: 1, keeping: scrollTarget)
                } else {
                    moveSelectedYear(by: -1, keeping: scrollTarget)
                }
            }
    }

    private func moveSelectedYear(by delta: Int, keeping scrollTarget: AnalysisScrollTarget? = nil) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedYear = min(max(selectedYear + delta, 2000), 2100)
            pendingScrollTarget = scrollTarget
        }
    }

    private func trendDataChart(points: [TrendPoint], axisMax: Int) -> some View {
        var segment = 0
        let linePoints = points.compactMap { point -> TrendLinePoint? in
            guard point.hasNetAmount else {
                segment += 1
                return nil
            }
            return TrendLinePoint(point: point, segment: segment)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                LegendMark(color: appTheme.chartGrossColor, text: "額面", shape: .bar)
                LegendMark(color: appTheme.chartNetColor, text: "手取り", shape: .point)
            }
            .font(.caption)

            Chart {
                ForEach(points.filter(\.hasData)) { point in
                    BarMark(
                        x: .value("期間", point.label),
                        y: .value("総支給額", point.grossTotal),
                        width: .ratio(points.count > 8 ? 0.50 : 0.64)
                    )
                    .foregroundStyle(appTheme.chartGrossColor.opacity(0.72))
                    .cornerRadius(3)
                }

                ForEach(linePoints) { point in
                    LineMark(
                        x: .value("期間", point.label),
                        y: .value("手取り", point.netTotal),
                        series: .value("連続区間", point.segment)
                    )
                    .foregroundStyle(appTheme.chartNetColor)
                    .interpolationMethod(.linear)
                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("期間", point.label),
                        y: .value("手取り", point.netTotal)
                    )
                    .foregroundStyle(appTheme.chartNetColor)
                    .symbolSize(30)
                }
            }
            .chartLegend(.hidden)
            .chartXScale(domain: points.map(\.label))
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

private enum AnalysisScrollTarget: String, Hashable {
    case trend
    case employer
    case incomeCategory
}

private struct TrendPoint: Identifiable {
    let id: String
    let label: String
    let grossTotal: Int
    let netTotal: Int
    let hasData: Bool
    let hasNetAmount: Bool
}

private struct TrendLinePoint: Identifiable {
    let point: TrendPoint
    let segment: Int

    var id: String { "\(segment)-\(point.id)" }
    var label: String { point.label }
    var netTotal: Int { point.netTotal }
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
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmountForAggregation } }
    var hasNetAmount: Bool { records.contains { $0.netAmount != nil } }
    var deductionTotal: Int { records.reduce(0) { $0 + $1.deductionTotalForAggregation } }

}

private struct AnalysisMonthSummary: Identifiable {
    let month: Int
    let label: String
    let records: [PayRecord]

    var id: Int { month }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmountForAggregation } }
    var hasNetAmount: Bool { records.contains { $0.netAmount != nil } }
    var deductionTotal: Int { records.reduce(0) { $0 + $1.deductionTotalForAggregation } }
}

private struct BreakdownSummary: Identifiable {
    let label: String
    let records: [PayRecord]

    var id: String { label }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmountForAggregation } }
    var hasNetAmount: Bool { records.contains { $0.netAmount != nil } }
    var deductionTotal: Int { records.reduce(0) { $0 + $1.deductionTotalForAggregation } }
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
        HStack(spacing: 0) {
            Text(summary.label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, alignment: .leading)
            amountText(summary.grossTotal)
            amountText(summary.netTotal)
            amountText(summary.deductionTotal)
        }
        .padding(.vertical, 10)
    }

    private func amountText(_ amount: Int) -> some View {
        Text(shortYenText(amount))
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct BreakdownRow: View {
    let summary: BreakdownSummary

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(summary.count)件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            amountText("額面", summary.grossTotal)
                .frame(width: 92, alignment: .trailing)
            amountText("手取り", summary.netTotal)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private func amountText(_ title: String, _ amount: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(yenText(amount))
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }
}

private struct InfographicBreakdownRow: View {
    @Environment(\.appTheme) private var appTheme

    let rank: Int
    let summary: BreakdownSummary
    let yearlyGrossTotal: Int

    private var grossRatio: Double {
        guard yearlyGrossTotal > 0 else { return 0 }
        return min(Double(summary.grossTotal) / Double(yearlyGrossTotal), 1)
    }

    private var netRatio: Double {
        guard summary.hasNetAmount, yearlyGrossTotal > 0 else { return 0 }
        return min(Double(summary.netTotal) / Double(yearlyGrossTotal), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", rank))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.accentColor)
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
                        .fill(appTheme.chartGrossColor.opacity(0.78))
                        .frame(width: grossWidth)

                    if summary.hasNetAmount {
                        Circle()
                            .fill(appTheme.chartNetColor)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 2)
                            }
                            .offset(x: markerX - 5)
                    }
                }
            }
            .frame(height: 8)

            HStack {
                Spacer()
                Text("手取り \(summary.hasNetAmount ? shortYenText(summary.netTotal) : "未入力")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private enum LegendMarkShape {
    case bar
    case point
}

private struct LegendMark: View {
    let color: Color
    let text: String
    let shape: LegendMarkShape

    var body: some View {
        HStack(spacing: 4) {
            Group {
                switch shape {
                case .bar:
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 10, height: 10)
                case .point:
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
            }
            Text(text)
                .foregroundStyle(.secondary)
        }
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
