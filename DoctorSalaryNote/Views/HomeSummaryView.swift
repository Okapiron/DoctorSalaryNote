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
        Array(payRecords.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                currentMonthImportButton
                latestMonthSection
                monthlyTrendSection
                yearSummarySection
                recentRecordsSection
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
        .sheet(isPresented: $isAddingCurrentMonthRecord) {
            NavigationStack {
                PayRecordFormView(showsImportOptionsOnAppear: true)
            }
        }
    }

    private var currentMonthImportButton: some View {
        Button {
            isAddingCurrentMonthRecord = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)

                Text("今月の記録を取り込む")
                    .font(.headline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(appTheme.accentColor)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("今月の給与明細を追加し、PDFや写真から読み取れます")
    }

    private var monthlyTrendSection: some View {
        homeCard(tint: .teal) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "直近の月別給与",
                    subtitle: "今月まで6か月の額面と手取り",
                    systemImage: "chart.bar.xaxis"
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
                            .foregroundStyle(appTheme.chartGrossColor.gradient)
                            .cornerRadius(4)
                        }

                        ForEach(recentMonthLinePoints) { summary in
                            LineMark(
                                x: .value("月", summary.shortLabel),
                                y: .value("手取り", summary.netTotal),
                                series: .value("連続区間", summary.segment)
                            )
                            .foregroundStyle(appTheme.chartNetColor)
                            .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))

                            PointMark(
                                x: .value("月", summary.shortLabel),
                                y: .value("手取り", summary.netTotal)
                            )
                            .foregroundStyle(appTheme.chartNetColor)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    headerIcon("calendar.badge.clock")
                    Text("\(latestMonthSummary.longLabel)の給与")
                        .font(.headline)

                    Spacer()

                    if latestMonthSummary.records.isEmpty {
                        Text("未登録")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    latestMonthAmount(
                        "額面",
                        latestMonthSummary.records.isEmpty ? "未登録" : yenText(latestMonthSummary.grossTotal),
                        tint: appTheme.accentColor
                    )

                    latestMonthAmount(
                        "手取り",
                        latestMonthSummary.records.isEmpty ? "未登録" : latestMonthSummary.netDisplayText,
                        tint: appTheme.accentColor
                    )
                }
            }
        }
    }

    private func latestMonthAmount(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        }
    }

    private var yearSummarySection: some View {
        homeCard(tint: .indigo) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $selectedYear, in: 2000...2100) {
                    HStack(spacing: 10) {
                        headerIcon("calendar")
                        Text(verbatim: "\(selectedYear)年の合計")
                            .font(.headline)
                    }
                }

                HStack(spacing: 12) {
                    compactAmount("額面", selectedYearSummary.grossTotal)
                    compactAmount("手取り", selectedYearSummary.netDisplayText)
                    compactAmount("控除", selectedYearSummary.deductionTotal)
                }
            }
        }
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
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentRecordsSection: some View {
        homeCard(tint: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "最近の給与明細",
                    subtitle: "登録した給与明細をすぐ確認",
                    systemImage: "clock"
                )

                if recentRecords.isEmpty {
                    Text("給与明細を登録すると、直近3件がここに表示されます。")
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

    private func homeCard<Content: View>(tint _: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .shadow(color: appTheme.accentColor.opacity(0.10), radius: 10, y: 4)
            )
    }

    private func sectionHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            headerIcon(systemImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headerIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(appTheme.accentColor)
            .frame(width: 28, height: 28)
            .background(appTheme.accentColor.opacity(0.12))
            .clipShape(Circle())
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
    var netTotal: Int { records.reduce(0) { $0 + $1.netAmountForAggregation } }
    var hasNetAmount: Bool { records.contains { $0.netAmount != nil } }
    var netDisplayText: String { hasNetAmount ? yenText(netTotal) : "未入力" }
    var deductionTotal: Int { records.reduce(0) { $0 + $1.deductionTotalForAggregation } }

}

private struct HomeTrendLinePoint: Identifiable {
    let summary: HomeMonthSummary
    let segment: Int

    var id: String { "\(segment)-\(summary.key.year)-\(summary.key.month)" }
    var shortLabel: String { summary.shortLabel }
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
    @Environment(\.appTheme) private var appTheme

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
                Text("手取り \(record.netAmount.map(yenText) ?? "未入力")")
                    .foregroundStyle(appTheme.accentColor)
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
