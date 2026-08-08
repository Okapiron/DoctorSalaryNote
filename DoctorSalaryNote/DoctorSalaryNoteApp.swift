import SwiftData
import SwiftUI

@main
struct DoctorSalaryNoteApp: App {
    private let modelContainer: ModelContainer?
    private let modelContainerError: String?
#if DEBUG
    private let appStoreScreenshotMode: String?
    private let appStoreScreenshotEmployer: Employer?
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let screenshotMode = arguments.first { $0.hasPrefix("-appStoreScreenshot") }
        appStoreScreenshotMode = screenshotMode
#else
        let screenshotMode: String? = nil
#endif
        let schema = Schema([
            Employer.self,
            PayRecord.self,
            EmployerDeductionTemplate.self,
            PayRecordDeductionItem.self,
            DocumentAttachment.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: screenshotMode != nil
        )

        let containerResult: Result<ModelContainer, Error>
        do {
            containerResult = .success(try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
            containerResult = .failure(error)
        }

        switch containerResult {
        case .success(let container):
            modelContainer = container
            modelContainerError = nil
#if DEBUG
            if screenshotMode != nil {
                let employer = Employer(
                    name: "青空メディカルセンター",
                    employerType: .fullTime,
                    defaultIncomeCategory: .fullTimeSalary
                )
                container.mainContext.insert(employer)
                appStoreScreenshotEmployer = employer
            } else {
                appStoreScreenshotEmployer = nil
            }
#endif
        case .failure(let error):
            modelContainer = nil
            modelContainerError = error.localizedDescription
#if DEBUG
            appStoreScreenshotEmployer = nil
#endif
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
#if DEBUG
                if let appStoreScreenshotMode,
                   let appStoreScreenshotEmployer {
                    NavigationStack {
                        if appStoreScreenshotMode == "-appStoreScreenshotImport" {
                            PayRecordFormView(
                                initialEmployer: appStoreScreenshotEmployer,
                                showsImportOptionsOnAppear: true
                            )
                        } else {
                            PayRecordFormView(screenshotEmployer: appStoreScreenshotEmployer)
                        }
                    }
                    .modelContainer(modelContainer)
                } else {
                    ContentView()
                        .modelContainer(modelContainer)
                }
#else
                ContentView()
                    .modelContainer(modelContainer)
#endif
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
