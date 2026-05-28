import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

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
            securitySection
            csvSection
            dataManagementSection
            informationSection
        }
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
                    Text("\(year)年").tag(year)
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
            Text("給与明細を年別または全期間で出力します。年度別CSVは今後の対応予定です。")
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
                        "MVPではクラウド同期を行いません。",
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
        try? modelContext.save()
    }

    private func setBiometricLockEnabled(_ isEnabled: Bool) {
        securityMessage = nil

        if isEnabled {
            if let unavailableMessage = BiometricAuthenticator.unavailableMessage() {
                securityMessage = unavailableMessage
                return
            }

            Task {
                do {
                    try await BiometricAuthenticator.authenticate(reason: "医師給与ノートのロックを有効にするため認証してください。")
                    await MainActor.run {
                        updateBiometricLock(isEnabled: true)
                        securityMessage = "\(BiometricAuthenticator.biometryLabel())ロックを有効にしました。"
                    }
                } catch {
                    await MainActor.run {
                        securityMessage = "認証できなかったため、ロックを有効にしませんでした。"
                    }
                }
            }
        } else {
            updateBiometricLock(isEnabled: false)
            securityMessage = "\(BiometricAuthenticator.biometryLabel())ロックを無効にしました。"
        }
    }

    private func updateBiometricLock(isEnabled: Bool) {
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
        UserDefaults.standard.set(isEnabled, forKey: "biometricLockEnabled")
        try? modelContext.save()
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
        for document in documents {
            DocumentFileStore.deleteFile(for: document)
            modelContext.delete(document)
        }

        DocumentFileStore.deleteAllFiles()

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
        UserDefaults.standard.set(false, forKey: "biometricLockEnabled")

        do {
            try modelContext.save()
            selectedCSVYear = 0
            csvFileURL = nil
            csvMessage = nil
            securityMessage = nil
            deleteMessage = "すべてのデータを削除しました。"
        } catch {
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
                LabeledContent("アプリ名", value: "医師給与ノート")
                LabeledContent("バージョン", value: versionText)
                LabeledContent("ビルド", value: buildNumberText)
            }

            Section {
                Text("医師の複数勤務先からの給与・収入と関連書類を、端末内で整理するための補助アプリです。")
                    .font(.body)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("アプリ情報")
    }
}
