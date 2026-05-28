import Foundation
import UniformTypeIdentifiers

struct StoredDocumentFile {
    let localFilePath: String
    let storedFileName: String
    let originalFileName: String
    let mimeType: String
    let fileSize: Int
    let fileType: AttachmentFileType
}

enum DocumentFileStore {
    private static let directoryName = "DocumentAttachments"

    static func saveSecurityScopedFile(from sourceURL: URL, fileType: AttachmentFileType) throws -> StoredDocumentFile {
        let canAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = sourceURL.lastPathComponent.isEmpty ? "document.pdf" : sourceURL.lastPathComponent
        let data = try Data(contentsOf: sourceURL)
        return try saveData(data, originalFileName: fileName, fileType: fileType)
    }

    static func saveData(_ data: Data, originalFileName: String, fileType: AttachmentFileType) throws -> StoredDocumentFile {
        let directory = try attachmentsDirectory()
        let fileExtension = preferredFileExtension(for: originalFileName, fileType: fileType)
        let storedFileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(storedFileName)

        try data.write(to: destinationURL, options: [.atomic])

        return StoredDocumentFile(
            localFilePath: destinationURL.path,
            storedFileName: storedFileName,
            originalFileName: originalFileName,
            mimeType: mimeType(for: fileExtension, fileType: fileType),
            fileSize: data.count,
            fileType: fileType
        )
    }

    static func fileURL(for attachment: DocumentAttachment) -> URL? {
        if let localFilePath = attachment.localFilePath, !localFilePath.isEmpty {
            return URL(fileURLWithPath: localFilePath)
        }

        guard let storedFileName = attachment.storedFileName else {
            return nil
        }

        return try? attachmentsDirectory().appendingPathComponent(storedFileName)
    }

    static func deleteFile(for attachment: DocumentAttachment) {
        guard let fileURL = fileURL(for: attachment) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func attachmentsDirectory() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documentsURL.appendingPathComponent(directoryName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private static func preferredFileExtension(for originalFileName: String, fileType: AttachmentFileType) -> String {
        let extensionFromName = URL(fileURLWithPath: originalFileName).pathExtension
        if !extensionFromName.isEmpty {
            return extensionFromName
        }

        switch fileType {
        case .pdf:
            return "pdf"
        case .image:
            return "jpg"
        case .other:
            return "dat"
        }
    }

    private static func mimeType(for fileExtension: String, fileType: AttachmentFileType) -> String {
        if let type = UTType(filenameExtension: fileExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        switch fileType {
        case .pdf:
            return "application/pdf"
        case .image:
            return "image/jpeg"
        case .other:
            return "application/octet-stream"
        }
    }
}
