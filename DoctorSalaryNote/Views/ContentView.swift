import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeSummaryView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }

            PayRecordListView()
                .tabItem {
                    Label("明細", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                DocumentListView()
            }
            .tabItem {
                Label("書類", systemImage: "doc.text")
            }

            NavigationStack {
                AnalysisPlaceholderView()
            }
            .tabItem {
                Label("分析", systemImage: "chart.bar")
            }
        }
    }
}

#Preview {
    ContentView()
}
