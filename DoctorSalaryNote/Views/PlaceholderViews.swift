import SwiftUI

struct HomePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "ホーム",
            systemImage: "house",
            description: Text("集計表示は次の開発フェーズで追加します。")
        )
        .navigationTitle("ホーム")
    }
}

struct DocumentsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "書類",
            systemImage: "doc.text",
            description: Text("書類添付と管理機能は次の開発フェーズで追加します。")
        )
        .navigationTitle("書類")
    }
}

struct AnalysisPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "分析",
            systemImage: "chart.bar",
            description: Text("グラフと分析表示は次の開発フェーズで追加します。")
        )
        .navigationTitle("分析")
    }
}
