import SwiftData
import SwiftUI

@main
struct DoctorSalaryNoteApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Employer.self,
            PayRecord.self,
            DocumentAttachment.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainerの初期化に失敗しました: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
