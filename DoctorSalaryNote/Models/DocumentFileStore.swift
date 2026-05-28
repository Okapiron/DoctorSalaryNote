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
            localFilePath: relativeLocalFilePath(for: storedFileName),
            storedFileName: storedFileName,
            originalFileName: originalFileName,
            mimeType: mimeType(for: fileExtension, fileType: fileType),
            fileSize: data.count,
            fileType: fileType
        )
    }

    static func fileURL(for attachment: DocumentAttachment) -> URL? {
        if let localFilePath = attachment.localFilePath,
           let fileURL = fileURL(forLocalFilePath: localFilePath) {
            return fileURL
        }

        guard let storedFileName = attachment.storedFileName else {
            return nil
        }

        return try? attachmentsDirectory().appendingPathComponent(storedFileName)
    }

    static func deleteFile(for attachment: DocumentAttachment) {
        deleteFile(at: fileURL(for: attachment))
    }

    static func deleteFile(at fileURL: URL?) {
        guard let fileURL else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    static func fileURL(forLocalFilePath localFilePath: String) -> URL? {
        guard !localFilePath.isEmpty else {
            return nil
        }

        if localFilePath.hasPrefix("/") {
            return URL(fileURLWithPath: localFilePath)
        }

        return try? documentsDirectory().appendingPathComponent(localFilePath)
    }

    private static func relativeLocalFilePath(for storedFileName: String) -> String {
        "\(directoryName)/\(storedFileName)"
    }

    private static func documentsDirectory() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private static func attachmentsDirectory() throws -> URL {
        let documentsURL = try documentsDirectory()
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
