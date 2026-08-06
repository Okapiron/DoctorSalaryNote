import SwiftData
import SwiftUI

@main
struct DoctorSalaryNoteApp: App {
    private let modelContainer: ModelContainer?
    private let modelContainerError: String?

    init() {
        let schema = Schema([
            Employer.self,
            PayRecord.self,
            EmployerDeductionTemplate.self,
            PayRecordDeductionItem.self,
            DocumentAttachment.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            modelContainerError = nil
        } catch {
            modelContainer = nil
            modelContainerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .modelContainer(modelContainer)
            } else {
                DataStoreErrorView(errorDescription: modelContainerError)
            }
        }
    }
}

private struct DataStoreErrorView: View {
    let errorDescription: String?

    var body: some View {
        ContentUnavailableView {
            Label("データを読み込めませんでした", systemImage: "exclamationmark.triangle")
        } description: {
            Text("アプリを終了して、もう一度開いてください。改善しない場合は、アプリを削除せずにサポートへお問い合わせください。")
        }
        .padding()
        .accessibilityHint(errorDescription ?? "端末内データの初期化に失敗しました。")
    }
}
