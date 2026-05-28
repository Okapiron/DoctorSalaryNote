import QuickLook
import SwiftUI
import UIKit

struct DocumentPreviewView: View {
    private let title: String
    private let fileType: AttachmentFileType
    private let fileURL: URL?

    init(attachment: DocumentAttachment) {
        self.title = attachment.documentType.label
        self.fileType = attachment.attachmentFileType
        self.fileURL = DocumentFileStore.fileURL(for: attachment)
    }

    init(title: String, fileType: AttachmentFileType, fileURL: URL?) {
        self.title = title
        self.fileType = fileType
        self.fileURL = fileURL
    }

    var body: some View {
        Group {
            if let fileURL, fileType == .image,
               let image = UIImage(contentsOfFile: fileURL.path) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                .background(Color(.systemBackground))
            } else if let fileURL {
                QuickLookPreview(fileURL: fileURL)
            } else {
                ContentUnavailableView(
                    "プレビューできません",
                    systemImage: "doc.questionmark",
                    description: Text("保存済みファイルが見つかりません。")
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}
