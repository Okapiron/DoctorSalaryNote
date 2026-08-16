import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var storedAppTheme = AppTheme.aqua.rawValue
    @AppStorage(AppIconChoice.storageKey) private var storedAppIconChoice = AppIconChoice.followTheme.rawValue

    @Query(sort: [
        SortDescriptor(\PayRecord.paymentYear, order: .reverse),
        SortDescriptor(\PayRecord.paymentMonth, order: .reverse)
    ]) private var payRecords: [PayRecord]

    @Query(sort: [
        SortDescriptor(\Employer.sortOrder),
        SortDescriptor(\Employer.name)
    ]) private var employers: [Employer]

    @Query private var documents: [DocumentAttachment]
    @Query private var appSettings: [AppSettings]

    @State private var securityMessage: String?
    @State private var appIconMessage: String?
    @State private var deleteMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsFinalDeleteAlert = false

    private var settings: AppSettings? {
        appSettings.first
    }

    var body: some View {
        List {
            appearanceSection
            securitySection
            dataManagementSection
            informationSection
        }
        .tint(selectedAppTheme.accentColor)
        .listSectionSpacing(18)
        .scrollContentBackground(.hidden)
        .background(EditorialStyle.pageBackground)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: ensureSettings)
        .onChange(of: storedAppTheme) { _, _ in
            guard selectedAppIconChoice == .followTheme else {
                return
            }
            updateAppIcon()
        }
        .onChange(of: storedAppIconChoice) { _, _ in
            updateAppIcon()
        }
        .confirmationDialog(
            "全データ削除",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除手続きへ進む", role: .destructive) {
                showsFinalDeleteAlert = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("勤務先、給与明細、書類、添付ファイルを削除します。次の画面でもう一度確認します。")
        }
        .alert("本当にすべて削除しますか？", isPresented: $showsFinalDeleteAlert) {
            Button("すべて削除", role: .destructive, action: deleteAllData)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は元に戻せません。保存済みの添付ファイルも削除されます。")
        }
    }

    private var selectedAppTheme: AppTheme {
        AppTheme(rawValue: storedAppTheme) ?? .aqua
    }

    private var selectedAppIconChoice: AppIconChoice {
        AppIconChoice(rawValue: storedAppIconChoice) ?? .followTheme
    }

    private var appearanceSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        storedAppTheme = theme.rawValue
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(theme.accentColor)
                                    .frame(width: 34, height: 34)

                                if selectedAppTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }

                            Text(theme.label)
                                .font(.caption2)
                                .foregroundStyle(selectedAppTheme == theme ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(theme.label)テーマ")
                    .accessibilityValue(selectedAppTheme == theme ? "選択中" : "")
                }
            }
            .padding(.vertical, 4)

            Picker(selection: $storedAppIconChoice) {
                ForEach(AppIconChoice.allCases) { choice in
                    Text(choice.label).tag(choice.rawValue)
                }
            } label: {
                SettingsRowLabel(
                    systemImage: "app.dashed",
                    title: "ホーム画面アイコン"
                )
            }
            .pickerStyle(.navigationLink)

            if let appIconMessage {
                Text(appIconMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            settingsSectionHeader("外観")
        } footer: {
            Text("テーマはボタン、タブ、主要アイコン、グラフへ反映されます。")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings?.isBiometricLockEnabled ?? false },
                set: setBiometricLockEnabled
            )) {
                SettingsRowLabel(
                    systemImage: "faceid",
                    title: "\(BiometricAuthenticator.biometryLabel())ロック",
                    detail: "起動時と1分以上離れた後に認証"
                )
            }

            if let securityMessage {
                Text(securityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            settingsSectionHeader("セキュリティ")
        }
    }

    private var dataManagementSection: some View {
        Section {
            NavigationLink {
                EmployerListView()
            } label: {
                SettingsRowLabel(
                    systemImage: "building.2",
                    title: "勤務先管理",
                    detail: "勤務先とOCR用の控除項目",
                    trailingValue: "\(employers.count)件"
                )
            }

            NavigationLink {
                CSVExportSettingsView(payRecords: payRecords)
            } label: {
                SettingsRowLabel(
                    systemImage: "tablecells",
                    title: "CSV出力",
                    detail: "給与明細を年別または全期間で出力"
                )
            }

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                SettingsRowLabel(
                    systemImage: "trash",
                    title: "全データ削除",
                    isDestructive: true
                )
            }

            if let deleteMessage {
                Text(deleteMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            settingsSectionHeader("データ管理")
        } footer: {
            Text("全データ削除では勤務先、給与明細、書類、添付ファイルを削除します。")
        }
    }

    private var informationSection: some View {
        Section {
            NavigationLink {
                DisclaimerView()
            } label: {
                SettingsRowLabel(systemImage: "exclamationmark.shield", title: "免責事項")
            }

            NavigationLink {
                PrivacyOverviewView()
            } label: {
                SettingsRowLabel(systemImage: "lock.shield", title: "プライバシーについて")
            }

            NavigationLink {
                AppInfoView()
            } label: {
                SettingsRowLabel(
                    systemImage: "info.circle",
                    title: "アプリ情報",
                    trailingValue: appVersionText
                )
            }
        } header: {
            settingsSectionHeader("アプリについて")
        }
    }

    private var appVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private func ensureSettings() {
        guard appSettings.isEmpty else {
            return
        }

        modelContext.insert(AppSettings())
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            securityMessage = "設定を準備できませんでした。アプリを再起動して、もう一度お試しください。"
        }
    }

    private func setBiometricLockEnabled(_ isEnabled: Bool) {
        securityMessage = nil

        if isEnabled {
            if let unavailableMessage = BiometricAuthenticator.unavailableMessage() {
                securityMessage = unavailableMessage
                return
            }

            if updateBiometricLock(isEnabled: true) {
                securityMessage = "\(BiometricAuthenticator.biometryLabel())ロックを有効にしました。次回起動時、または1分以上アプリを離れた後に認証します。"
            }
        } else {
            if updateBiometricLock(isEnabled: false) {
                securityMessage = "\(BiometricAuthenticator.biometryLabel())ロックを無効にしました。"
            }
        }
    }

    private func updateAppIcon() {
        appIconMessage = nil
        let choice = selectedAppIconChoice
        let theme = selectedAppTheme

        Task {
            do {
                try await AppIconManager.update(choice: choice, theme: theme)
                appIconMessage = "ホーム画面アイコンを変更しました。"
            } catch {
                appIconMessage = "ホーム画面アイコンを変更できませんでした。もう一度お試しください。"
            }
        }
    }

    private func updateBiometricLock(isEnabled: Bool) -> Bool {
        let targetSettings: AppSettings
        if let settings {
            targetSettings = settings
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            targetSettings = newSettings
        }

        targetSettings.isBiometricLockEnabled = isEnabled
        targetSettings.updatedAt = Date()
        do {
            try modelContext.save()
            UserDefaults.standard.set(isEnabled, forKey: "biometricLockEnabled")
            return true
        } catch {
            modelContext.rollback()
            securityMessage = "ロック設定を保存できませんでした。もう一度お試しください。"
            return false
        }
    }

    private func deleteAllData() {
        let documentFileURLs = documents.compactMap { DocumentFileStore.fileURL(for: $0) }

        for document in documents {
            modelContext.delete(document)
        }

        for payRecord in payRecords {
            modelContext.delete(payRecord)
        }

        for employer in employers {
            modelContext.delete(employer)
        }

        for settings in appSettings {
            modelContext.delete(settings)
        }

        modelContext.insert(AppSettings())

        do {
            try modelContext.save()
            UserDefaults.standard.set(false, forKey: "biometricLockEnabled")
            storedAppTheme = AppTheme.aqua.rawValue
            storedAppIconChoice = AppIconChoice.followTheme.rawValue
            updateAppIcon()
            securityMessage = nil
            do {
                try DocumentFileStore.deleteFiles(at: documentFileURLs)
                try DocumentFileStore.deleteAllFiles()
                deleteMessage = "すべてのデータを削除しました。"
            } catch {
                deleteMessage = "登録データは削除しましたが、一部の添付ファイルを端末から削除できませんでした。アプリを再起動して、もう一度全データ削除を実行してください。"
            }
        } catch {
            modelContext.rollback()
            deleteMessage = "データ削除中にエラーが発生しました。もう一度お試しください。"
        }
    }
}

private struct SettingsRowLabel: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String
    let title: String
    var detail: String? = nil
    var trailingValue: String? = nil
    var isDestructive = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 31, height: 31)

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color.red : Color.primary)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let trailingValue {
                Text(trailingValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, detail == nil ? 0 : 2)
    }

    private var iconColor: Color {
        isDestructive ? .red : appTheme.accentColor
    }
}

private struct CSVExportSettingsView: View {
    @Environment(\.appTheme) private var appTheme

    let payRecords: [PayRecord]

    @State private var selectedYear = 0
    @State private var fileURL: URL?
    @State private var message: String?

    private var availableYears: [Int] {
        Array(Set(payRecords.map(\.paymentYear))).sorted(by: >)
    }

    private var selectedRecords: [PayRecord] {
        guard selectedYear != 0 else {
            return payRecords
        }
        return payRecords.filter { $0.paymentYear == selectedYear }
    }

    private var targetLabel: String {
        selectedYear == 0 ? "すべての年" : "\(selectedYear)年"
    }

    private var expectedFileName: String {
        selectedYear == 0
            ? "Dr's Salary_給与明細_全期間.csv"
            : "Dr's Salary_給与明細_\(selectedYear)年.csv"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(appTheme.accentColor)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("給与明細を\nCSVにまとめる")
                            .font(.system(size: 26, weight: .bold))

                        Text("表計算ソフトで確認・整理できる形式で出力します。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 26)

                VStack(alignment: .leading, spacing: 12) {
                    Text("出力対象")
                        .font(.system(size: 17, weight: .bold))

                    HStack {
                        Text("期間")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Picker("期間", selection: $selectedYear) {
                            Text("すべての年").tag(0)
                            ForEach(availableYears, id: \.self) { year in
                                Text(verbatim: "\(year)年").tag(year)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fontWeight(.semibold)
                    }
                }
                .padding(.vertical, 20)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }

                VStack(spacing: 0) {
                    csvSummaryRow(title: "対象データ", value: "\(selectedRecords.count)件")
                    Divider()
                    csvSummaryRow(title: "ファイル名", value: expectedFileName, allowsWrapping: true)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("含まれる内容")
                        .font(.system(size: 17, weight: .bold))

                    Text("支給年月、勤務先、収入区分、額面、手取り、控除、税金、控除内訳、メモ")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)

                if let fileURL {
                    VStack(spacing: 14) {
                        Label("\(targetLabel)のCSVを作成しました", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)

                        ShareLink(item: fileURL) {
                            Label("CSVを共有", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(appTheme.accentColor)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(appTheme.accentColor.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: EditorialStyle.cornerRadius, style: .continuous))
                        }
                    }
                } else {
                    Button(action: makeCSVFile) {
                        Label("CSVファイルを作成", systemImage: "doc.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(selectedRecords.isEmpty ? Color.secondary : appTheme.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: EditorialStyle.cornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedRecords.isEmpty)
                }

                if let message, fileURL == nil {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else if selectedRecords.isEmpty {
                    Text("選択した期間に給与明細がありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }

                Text("作成したCSVは、共有シートから保存先や送信先を選べます。自動送信は行いません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .tint(appTheme.accentColor)
        .background(EditorialStyle.pageBackground)
        .navigationTitle("CSV出力")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedYear) { _, _ in
            fileURL = nil
            message = nil
        }
    }

    private func csvSummaryRow(title: String, value: String, allowsWrapping: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)

            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(allowsWrapping ? 2 : 1)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }

    private func makeCSVFile() {
        do {
            let year = selectedYear == 0 ? nil : selectedYear
            fileURL = try CSVExportService.makePayRecordsCSVFile(payRecords: payRecords, year: year)
            message = year.map { "\($0)年のCSVを作成しました。" } ?? "全期間のCSVを作成しました。"
        } catch {
            fileURL = nil
            message = "CSVファイルを作成できませんでした。もう一度お試しください。"
        }
    }
}

private struct AppInfoView: View {
    @Environment(\.appTheme) private var appTheme

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildNumberText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(appTheme.accentColor)

                        Image(systemName: "yensign")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 68, height: 68)
                    .shadow(color: appTheme.accentColor.opacity(0.16), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dr's Salary")
                            .font(.system(size: 25, weight: .bold))

                        Text("医師の収入を、ひとつに。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 26)

                Text("複数勤務先の給与・収入と関連書類をまとめ、給与明細の端末内OCRで入力を支援します。")
                    .font(.body)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Divider() }
                    .overlay(alignment: .bottom) { Divider() }

                VStack(spacing: 0) {
                    infoValueRow(title: "バージョン", value: versionText)
                    Divider()
                    infoValueRow(title: "ビルド", value: buildNumberText)
                }
                .padding(.bottom, 22)

                VStack(spacing: 0) {
                    NavigationLink {
                        PrivacyOverviewView()
                    } label: {
                        infoLinkRow(systemImage: "lock.shield", title: "プライバシーについて")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        infoLinkRow(systemImage: "exclamationmark.shield", title: "免責事項")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .background(EditorialStyle.pageBackground)
        .navigationTitle("アプリ情報")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 15)
    }

    private func infoLinkRow(systemImage: String, title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(appTheme.accentColor.opacity(0.11))
                    .frame(width: 34, height: 34)

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appTheme.accentColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 13)
    }
}

private struct PrivacyOverviewView: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InformationHero(
                    systemImage: "lock.shield.fill",
                    title: "給与情報は\n端末内で管理",
                    detail: "ログインや外部サーバーへの送信はありません。"
                )

                HStack(alignment: .top, spacing: 8) {
                    PrivacyPoint(systemImage: "iphone", title: "端末内\n保存")
                    PrivacyPoint(systemImage: "icloud.slash", title: "クラウド\n同期なし")
                    PrivacyPoint(systemImage: "doc.text.viewfinder", title: "OCRも\n端末内処理")
                }
                .padding(.vertical, 26)

                Divider()

                InformationReadingSection(
                    title: "保存される情報",
                    text: "勤務先、給与明細、書類情報、給与明細・源泉徴収票・支払調書などの添付ファイルは、アプリの端末内領域に保存されます。"
                )

                InformationReadingSection(
                    title: "OCR読み取り",
                    text: "給与明細の画像、PDF、認識結果を外部のOCRサービスへ送信せず、端末内で処理します。"
                )

                InformationReadingSection(
                    title: "外部への共有",
                    text: "CSV出力や共有はユーザーの操作時のみ行われます。共有先での取り扱いをご確認ください。"
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .tint(appTheme.accentColor)
        .background(EditorialStyle.pageBackground)
        .navigationTitle("プライバシー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DisclaimerView: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InformationHero(
                    systemImage: "exclamationmark.shield.fill",
                    title: "収入記録と\n書類整理のために",
                    detail: "本アプリは税務申告ソフトではありません。",
                    iconColor: .orange
                )

                Divider()
                    .padding(.top, 26)

                InformationReadingSection(
                    title: "本アプリでできること",
                    text: "給与・手取り・控除の記録、収入推移の確認、給与明細や源泉徴収票などの整理を支援します。"
                )

                InformationReadingSection(
                    title: "本アプリで行わないこと",
                    text: "税務計算、確定申告書の作成、税務助言、申告代行は行いません。"
                )

                InformationReadingSection(
                    title: "登録内容について",
                    text: "登録内容や集計結果はご自身で確認し、税務判断が必要な場合は税理士や税務署などの専門窓口へご相談ください。"
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .tint(appTheme.accentColor)
        .background(EditorialStyle.pageBackground)
        .navigationTitle("免責事項")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InformationHero: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String
    let title: String
    let detail: String
    var iconColor: Color? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(iconColor ?? appTheme.accentColor)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacyPoint: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))

            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(appTheme.accentColor)
        .frame(maxWidth: .infinity, minHeight: 94)
        .background(appTheme.accentColor.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: EditorialStyle.cornerRadius, style: .continuous))
    }
}

private struct InformationReadingSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .bold))

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }
}
