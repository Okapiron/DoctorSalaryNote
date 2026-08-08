import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var storedAppTheme = AppTheme.aqua.rawValue

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

    @State private var selectedCSVYear = 0
    @State private var csvFileURL: URL?
    @State private var csvMessage: String?
    @State private var securityMessage: String?
    @State private var deleteMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsFinalDeleteAlert = false

    private var settings: AppSettings? {
        appSettings.first
    }

    private var availableYears: [Int] {
        Array(Set(payRecords.map(\.paymentYear))).sorted(by: >)
    }

    var body: some View {
        List {
            appearanceSection
            securitySection
            csvSection
            dataManagementSection
            informationSection
        }
        .tint(selectedAppTheme.accentColor)
        .navigationTitle("設定")
        .onAppear(perform: ensureSettings)
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
        } header: {
            Text("テーマカラー")
        } footer: {
            Text("ボタンやタブ、主要アイコンの色を変更します。")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings?.isBiometricLockEnabled ?? false },
                set: setBiometricLockEnabled
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(BiometricAuthenticator.biometryLabel())ロック")
                    Text("起動時や復帰時に認証してから内容を表示します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let securityMessage {
                Text(securityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Face ID / Touch IDロック")
        }
    }

    private var csvSection: some View {
        Section {
            Picker("出力対象", selection: $selectedCSVYear) {
                Text("すべての年").tag(0)
                ForEach(availableYears, id: \.self) { year in
                    Text(verbatim: "\(year)年").tag(year)
                }
            }

            Button {
                makeCSVFile()
            } label: {
                Label("CSVファイルを作成", systemImage: "doc.badge.arrow.up")
            }
            .disabled(payRecords.isEmpty)

            if let csvFileURL {
                ShareLink(item: csvFileURL) {
                    Label("CSVを共有", systemImage: "square.and.arrow.up")
                }
            }

            if let csvMessage {
                Text(csvMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if payRecords.isEmpty {
                Text("給与明細を登録するとCSV出力できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("CSV出力")
        } footer: {
            Text("給与明細を年別または全期間で出力します。")
        }
    }

    private var dataManagementSection: some View {
        Section {
            NavigationLink {
                EmployerListView()
            } label: {
                Label("勤務先管理", systemImage: "building.2")
            }

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("全データ削除", systemImage: "trash")
            }

            if let deleteMessage {
                Text(deleteMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("データ管理")
        } footer: {
            Text("全データ削除では勤務先、給与明細、書類、添付ファイルを削除します。")
        }
    }

    private var informationSection: some View {
        Section {
            NavigationLink {
                PolicyTextView(
                    title: "免責事項",
                    paragraphs: [
                        "本アプリは税務計算アプリではありません。",
                        "本アプリは確定申告書を作成するものではありません。",
                        "本アプリは税務助言や申告代行を行いません。",
                        "登録内容や集計結果は、ユーザーご自身で確認してください。",
                        "税務判断が必要な場合は、税理士、税務署などの専門窓口にご確認ください。"
                    ]
                )
            } label: {
                Label("免責事項", systemImage: "exclamationmark.shield")
            }

            NavigationLink {
                PolicyTextView(
                    title: "プライバシーについて",
                    paragraphs: [
                        "本アプリはログイン不要で利用できます。",
                        "勤務先、給与明細、書類情報は端末内に保存されます。",
                        "給与明細、源泉徴収票、支払調書などの添付ファイルも端末内に保存されます。",
                        "本アプリは給与情報や添付ファイルを外部サーバーへ送信しません。",
                        "給与明細のOCR読み取りは端末内で処理され、画像や認識結果を外部のOCRサービスへ送信しません。",
                        "クラウド同期は行いません。",
                        "CSV出力や共有は、ユーザー操作によってのみ行われます。共有先の扱いにはご注意ください。"
                    ]
                )
            } label: {
                Label("プライバシーについて", systemImage: "lock.shield")
            }

            NavigationLink {
                AppInfoView()
            } label: {
                Label("アプリ情報", systemImage: "info.circle")
            }
        } header: {
            Text("情報")
        }
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

    private func makeCSVFile() {
        do {
            let year = selectedCSVYear == 0 ? nil : selectedCSVYear
            csvFileURL = try CSVExportService.makePayRecordsCSVFile(payRecords: payRecords, year: year)
            csvMessage = year.map { "\($0)年のCSVを作成しました。" } ?? "全期間のCSVを作成しました。"
        } catch {
            csvFileURL = nil
            csvMessage = "CSVファイルを作成できませんでした。もう一度お試しください。"
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
            selectedCSVYear = 0
            csvFileURL = nil
            csvMessage = nil
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

private struct PolicyTextView: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        List {
            Section {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.body)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct AppInfoView: View {
    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildNumberText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("アプリ名", value: "Dr's Salary")
                LabeledContent("バージョン", value: versionText)
                LabeledContent("ビルド", value: buildNumberText)
            }

            Section {
                Text("医師の複数勤務先からの給与・収入と関連書類をまとめ、給与明細の端末内OCRで入力を支援するアプリです。")
                    .font(.body)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("アプリ情報")
    }
}
