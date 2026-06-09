import Foundation
import PDFKit
import UIKit
import Vision

struct OCRPayRecordCandidate: Identifiable {
    let id = UUID()
    let paymentYear: Int?
    let paymentMonth: Int?
    let grossAmount: Int?
    let netAmount: Int?
    let deductionAmount: Int?
    let recognizedText: String

    var hasUsableValue: Bool {
        paymentYear != nil ||
            paymentMonth != nil ||
            grossAmount != nil ||
            netAmount != nil ||
            deductionAmount != nil
    }
}

enum OCRExtractionService {
    enum OCRError: Error {
        case unsupportedFile
        case imageRenderingFailed
        case recognitionFailed
    }

    static func extractPayRecordCandidate(from fileURL: URL, fileType: AttachmentFileType) async throws -> OCRPayRecordCandidate {
        try await Task.detached(priority: .userInitiated) {
            let images = try imagesForRecognition(from: fileURL, fileType: fileType)
            var lines: [RecognizedLine] = []

            for image in images {
                lines.append(contentsOf: try recognizeTextLines(in: image))
            }

            let normalizedLines = lines
                .map { normalizeJapaneseText($0.text) }
                .filter { !$0.isEmpty }

            guard !normalizedLines.isEmpty else {
                throw OCRError.recognitionFailed
            }

            let recognizedText = normalizedLines.joined(separator: "\n")
            let paymentDate = extractPaymentDate(from: recognizedText)
            let grossAmount = amountCandidate(for: .gross, in: normalizedLines)
            let netAmount = amountCandidate(for: .net, in: normalizedLines)
            let extractedDeduction = amountCandidate(for: .deduction, in: normalizedLines)
            let inferredDeduction: Int? = {
                guard extractedDeduction == nil,
                      let grossAmount,
                      let netAmount,
                      grossAmount >= netAmount else {
                    return nil
                }
                return grossAmount - netAmount
            }()

            return OCRPayRecordCandidate(
                paymentYear: paymentDate?.year,
                paymentMonth: paymentDate?.month,
                grossAmount: grossAmount,
                netAmount: netAmount,
                deductionAmount: extractedDeduction ?? inferredDeduction,
                recognizedText: recognizedText
            )
        }.value
    }

    private struct RecognizedLine {
        let text: String
        let confidence: Float
        let boundingBox: CGRect
    }

    private enum AmountField {
        case gross
        case net
        case deduction

        var keywords: [String] {
            switch self {
            case .gross:
                ["総支給額", "総支給", "支給合計", "支給額合計", "支給総額"]
            case .net:
                ["差引支給額", "差引支給", "差引額", "振込額", "銀行振込額", "銀行振込", "手取り"]
            case .deduction:
                ["控除合計", "控除額合計", "控除総額", "控除計"]
            }
        }
    }

    private static func imagesForRecognition(from fileURL: URL, fileType: AttachmentFileType) throws -> [CGImage] {
        switch fileType {
        case .image:
            guard let image = UIImage(contentsOfFile: fileURL.path),
                  let cgImage = image.cgImage else {
                throw OCRError.imageRenderingFailed
            }
            return [cgImage]

        case .pdf:
            guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
                throw OCRError.imageRenderingFailed
            }

            let pageLimit = min(document.pageCount, 2)
            return try (0..<pageLimit).map { index in
                guard let page = document.page(at: index),
                      let image = renderPDFPage(page) else {
                    throw OCRError.imageRenderingFailed
                }
                return image
            }

        case .other:
            throw OCRError.unsupportedFile
        }
    }

    private static func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }

        return image.cgImage
    }

    private static func recognizeTextLines(in image: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.35 else {
                    return nil
                }
                return RecognizedLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.015 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
    }

    private static func normalizeJapaneseText(_ text: String) -> String {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidth
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractPaymentDate(from text: String) -> (year: Int, month: Int)? {
        if let westernDate = firstMatch(
            in: text,
            pattern: #"((?:20)?\d{2})年(\d{1,2})月"#
        ),
           westernDate.count >= 3,
           let rawYear = Int(westernDate[1]),
           let month = Int(westernDate[2]),
           (1...12).contains(month) {
            let year = rawYear < 100 ? 2000 + rawYear : rawYear
            if (2000...2100).contains(year) {
                return (year, month)
            }
        }

        if let reiwaDate = firstMatch(
            in: text,
            pattern: #"令和(\d{1,2})年(\d{1,2})月"#
        ),
           reiwaDate.count >= 3,
           let reiwaYear = Int(reiwaDate[1]),
           let month = Int(reiwaDate[2]),
           (1...12).contains(month) {
            return (2018 + reiwaYear, month)
        }

        return nil
    }

    private static func amountCandidate(for field: AmountField, in lines: [String]) -> Int? {
        for (index, line) in lines.enumerated() {
            guard lineContainsAnyKeyword(line, keywords: field.keywords) else {
                continue
            }

            if let tableAmount = amountFromTableHeaderLine(field: field, line: line, followingLines: Array(lines.dropFirst(index + 1).prefix(2))) {
                return tableAmount
            }

            let sameLineAmounts = amountValues(in: line)
            if !sameLineAmounts.isEmpty {
                return bestAmount(from: sameLineAmounts, for: field)
            }

            for followingLine in lines.dropFirst(index + 1).prefix(2) {
                let followingAmounts = amountValues(in: followingLine)
                if !followingAmounts.isEmpty {
                    return bestAmount(from: followingAmounts, for: field)
                }
            }
        }

        return nil
    }

    private static func amountFromTableHeaderLine(field: AmountField, line: String, followingLines: [String]) -> Int? {
        let fieldOrder = fieldPositions(in: line).sorted { $0.position < $1.position }
        guard fieldOrder.count >= 2,
              let fieldIndex = fieldOrder.firstIndex(where: { $0.field == field }) else {
            return nil
        }

        for followingLine in followingLines {
            let amounts = amountValues(in: followingLine)
            guard amounts.count >= fieldOrder.count else {
                continue
            }
            return amounts[fieldIndex]
        }

        return nil
    }

    private static func fieldPositions(in line: String) -> [(field: AmountField, position: Int)] {
        [AmountField.gross, .net, .deduction].compactMap { field in
            let positions = field.keywords.compactMap { keyword in
                line.range(of: keyword)?.lowerBound.utf16Offset(in: line)
            }
            guard let position = positions.min() else {
                return nil
            }
            return (field, position)
        }
    }

    private static func lineContainsAnyKeyword(_ line: String, keywords: [String]) -> Bool {
        keywords.contains { line.contains($0) }
    }

    private static func bestAmount(from amounts: [Int], for field: AmountField) -> Int? {
        let filteredAmounts = amounts.filter { amount in
            switch field {
            case .gross, .net:
                amount >= 1_000
            case .deduction:
                amount >= 0
            }
        }

        guard !filteredAmounts.isEmpty else {
            return nil
        }

        switch field {
        case .gross:
            return filteredAmounts.max()
        case .net, .deduction:
            return filteredAmounts.last
        }
    }

    private static func amountValues(in text: String) -> [Int] {
        let pattern = #"([¥￥]?\d{1,3}(?:,\d{3})+|\d{4,9}|(?<!\d)0(?!\d))円?"#
        let matches = capturedMatches(in: text, pattern: pattern)
        return matches.compactMap { match in
            let digits = match.filter(\.isNumber)
            return Int(digits)
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        firstMatches(in: text, pattern: pattern, includeCaptureGroups: true).first
    }

    private static func firstMatches(in text: String, pattern: String, includeCaptureGroups: Bool = false) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            let rangeIndexes = includeCaptureGroups ? 0..<match.numberOfRanges : 0..<1
            return rangeIndexes.compactMap { index in
                let matchRange = match.range(at: index)
                guard matchRange.location != NSNotFound else {
                    return nil
                }
                return nsText.substring(with: matchRange)
            }
        }
    }

    private static func capturedMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            let matchRange = match.range(at: 1)
            guard matchRange.location != NSNotFound else {
                return nil
            }
            return nsText.substring(with: matchRange)
        }
    }
}
