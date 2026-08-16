import Charts
import SwiftData
import SwiftUI

struct HomeSummaryView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse),
        SortDescriptor(\PayRecord.createdAt, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var isAddingCurrentMonthRecord = false

    private var currentMonthKey: MonthKey {
        let now = Date()
        let calendar = Calendar.current
        return MonthKey(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
    }

    private var latestMonthKey: MonthKey {
        if let record = payRecords.first {
            return MonthKey(year: record.paymentYear, month: record.paymentMonth)
        }

        return currentMonthKey
    }

    private var recentMonthSummaries: [HomeMonthSummary] {
        (0..<6).reversed().map { offset in
            let key = currentMonthKey.addingMonths(-offset)
            let records = payRecords.filter {
                $0.paymentYear == key.year && $0.paymentMonth == key.month
            }
            return HomeMonthSummary(key: key, records: records)
        }
    }

    private var recentMonthLinePoints: [HomeTrendLinePoint] {
        var segment = 0
        return recentMonthSummaries.compactMap { summary in
            guard summary.hasNetAmount else {
                segment += 1
                return nil
            }
            return HomeTrendLinePoint(summary: summary, segment: segment)
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
            VStack(alignment: .leading, spacing: 0) {
                homeHeader
                latestMonthSection
                sectionBreak
                monthlyTrendSection
                sectionBreak
                yearSummarySection
                sectionBreak
                recentRecordsSection
            }
            .padding(.bottom, 104)
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingCurrentMonthRecord) {
            NavigationStack {
                PayRecordFormView(showsImportOptionsOnAppear: true)
            }
        }
    }

    private var homeHeader: some View {
        HStack(spacing: 14) {
            Text("ホーム")
                .font(.system(size: 17, weight: .semibold))

            Spacer(minLength: 12)

            Button {
                isAddingCurrentMonthRecord = true
            } label: {
                Label("給与明細を取り込む", systemImage: "doc.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(appTheme.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(appTheme.accentColor.opacity(0.09))
                            .overlay {
                                Capsule()
                                    .stroke(appTheme.accentColor.opacity(0.22), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("給与明細を追加し、PDFや写真から読み取れます")

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(appTheme.accentColor)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("設定")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private var latestMonthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(latestMonthSummary.longLabel)の給与")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                if latestMonthSummary.records.isEmpty {
                    Text("未登録")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 18) {
                latestMonthAmount(
                    "額面",
                    latestMonthSummary.records.isEmpty ? "未登録" : yenText(latestMonthSummary.grossTotal)
                )

                Divider()
                    .frame(height: 56)

                latestMonthAmount(
                    "手取り",
                    latestMonthSummary.records.isEmpty ? "未登録" : latestMonthSummary.netDisplayText
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(appTheme.accentColor.opacity(0.07))
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func latestMonthAmount(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(appTheme.accentColor)
            Text(value)
                .font(.system(size: 28, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthlyTrendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("直近6か月")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                if !payRecords.isEmpty {
                    HStack(spacing: 14) {
                        trendLegend(color: appTheme.chartGrossColor, title: "額面")
                        trendLegend(color: appTheme.chartNetColor, title: "手取り", showsLine: true)
                    }
                }
            }

            if payRecords.isEmpty {
                Text("給与明細を登録すると、月別の推移が表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            } else {
                Chart {
                    ForEach(recentMonthSummaries) { summary in
                        BarMark(
                            x: .value("月", summary.axisLabel),
                            y: .value("額面", summary.grossTotal)
                        )
                        .foregroundStyle(appTheme.chartGrossColor.opacity(0.78))
                        .cornerRadius(3)
                    }

                    ForEach(recentMonthLinePoints) { summary in
                        LineMark(
                            x: .value("月", summary.axisLabel),
                            y: .value("手取り", summary.netTotal),
                            series: .value("連続区間", summary.segment)
                        )
                        .foregroundStyle(appTheme.chartNetColor)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("月", summary.axisLabel),
                            y: .value("手取り", summary.netTotal)
                        )
                        .foregroundStyle(appTheme.chartNetColor)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisTick().foregroundStyle(Color(.systemGray4))
                        AxisValueLabel {
                            if let month = value.as(String.self) {
                                Text(month)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color(.systemGray5))
                        AxisValueLabel {
                            if let amount = value.as(Int.self) {
                                Text(chartAxisText(amount))
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.clear)
                }
                .frame(height: 210)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
    }

    private var yearSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: "\(selectedYear)年の合計")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Stepper("表示年", value: $selectedYear, in: 2000...2100)
                    .labelsHidden()
                    .fixedSize()
            }

            Rectangle()
                .fill(appTheme.accentColor)
                .frame(width: 54, height: 2)

            HStack(alignment: .top, spacing: 12) {
                compactAmount("額面", selectedYearSummary.grossTotal)
                Divider().frame(height: 46)
                compactAmount("手取り", selectedYearSummary.netDisplayText)
                Divider().frame(height: 46)
                compactAmount("控除", selectedYearSummary.deductionTotal)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
    }

    private func trendLegend(color: Color, title: String, showsLine: Bool = false) -> some View {
        HStack(spacing: 6) {
            if showsLine {
                Capsule()
                    .fill(color)
                    .frame(width: 20, height: 3)
                    .overlay {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                    }
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.78))
                    .frame(width: 15, height: 10)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chartAxisText(_ amount: Int) -> String {
        String(Int((Double(amount) / 10_000).rounded()))
    }

    private var sectionBreak: some View {
        Divider()
            .padding(.horizontal, 20)
            .accessibilityHidden(true)
    }

    private func compactAmount(_ title: String, _ amount: Int) -> some View {
        compactAmount(title, shortYenText(amount))
    }

    private func compactAmount(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近の給与明細")
                .font(.system(size: 16, weight: .semibold))

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
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
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
    var axisLabel: String { "\(key.month)" }
    var longLabel: String { "\(key.year)年\(key.month)月" }
    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmountForAggregation } }
    var hasNetAmount: Bool { records.contains { $0.netAmount != nil } }
    var netDisplayText: String { hasNetAmount ? yenText(netTotal) : "未入力" }
    var deductionTotal: Int { records.reduce(0) { $0 + $1.deductionTotalForAggregation } }

}

private struct HomeTrendLinePoint: Identifiable {
    let summary: HomeMonthSummary
    let segment: Int

    var id: String { "\(segment)-\(summary.key.year)-\(summary.key.month)" }
    var axisLabel: String { summary.axisLabel }
    var netTotal: Int { summary.netTotal }
}

private struct HomeYearSummary {
    let year: Int
    let records: [PayRecord]

    var grossTotal: Int { records.reduce(0) { $0 + $1.grossAmount } }
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmountForAggregation } }
    var hasNetAmount: Bool { records.contains { $0.netAmount != nil } }
    var netDisplayText: String { hasNetAmount ? shortYenText(netTotal) : "未入力" }
    var deductionTotal: Int { records.reduce(0) { $0 + $1.deductionTotalForAggregation } }
}

private struct RecentPayRecordRow: View {
    let record: PayRecord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(record.paymentYear)年\(record.paymentMonth)月分")
                    .font(.system(size: 15, weight: .medium))

                Text(record.employer?.name ?? "勤務先未設定")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(yenText(record.grossAmount))
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
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
