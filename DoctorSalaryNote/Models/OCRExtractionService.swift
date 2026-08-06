import CoreGraphics
import Foundation
import PDFKit
import UIKit
import Vision

enum OCRField: Hashable {
    case employer
    case paymentDate
    case grossAmount
    case netAmount
    case deductionAmount
}

enum OCRCandidateConfidence {
    case high
    case medium
    case low

    init(score: Double) {
        switch score {
        case 0.82...:
            self = .high
        case 0.62...:
            self = .medium
        default:
            self = .low
        }
    }

    var label: String {
        switch self {
        case .high:
            "高"
        case .medium:
            "中"
        case .low:
            "要確認"
        }
    }
}

struct OCRAmountCandidate {
    let value: Int
    let confidenceScore: Double
    let sourceText: String
    let isInferred: Bool

    var confidence: OCRCandidateConfidence {
        OCRCandidateConfidence(score: confidenceScore)
    }

    var isInitiallySelected: Bool {
        !isInferred
    }
}

struct OCRPaymentDateCandidate {
    let year: Int
    let month: Int
    let confidenceScore: Double
    let sourceText: String

    var confidence: OCRCandidateConfidence {
        OCRCandidateConfidence(score: confidenceScore)
    }

    var isInitiallySelected: Bool {
        true
    }
}

struct OCRPayRecordCandidate: Identifiable {
    let id = UUID()
    let paymentDateCandidate: OCRPaymentDateCandidate?
    let grossCandidate: OCRAmountCandidate?
    let netCandidate: OCRAmountCandidate?
    let deductionCandidate: OCRAmountCandidate?
    let recognizedText: String

    var paymentYear: Int? {
        paymentDateCandidate?.year
    }

    var paymentMonth: Int? {
        paymentDateCandidate?.month
    }

    var grossAmount: Int? {
        grossCandidate?.value
    }

    var netAmount: Int? {
        netCandidate?.value
    }

    var deductionAmount: Int? {
        deductionCandidate?.value
    }

    var hasUsableValue: Bool {
        paymentDateCandidate != nil ||
            grossCandidate != nil ||
            netCandidate != nil ||
            deductionCandidate != nil
    }
}

enum OCRExtractionService {
    enum OCRError: LocalizedError {
        case unsupportedFile
        case unreadablePDF
        case imageRenderingFailed
        case recognitionFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                "対応していないファイル形式です。"
            case .unreadablePDF:
                "PDFを開けませんでした。パスワード保護やファイル破損がないか確認してください。"
            case .imageRenderingFailed:
                "書類を画像として読み込めませんでした。"
            case .recognitionFailed:
                "書類内の文字を認識できませんでした。"
            }
        }
    }

    static func extractPayRecordCandidate(
        from fileURL: URL,
        fileType: AttachmentFileType
    ) async throws -> OCRPayRecordCandidate {
        try await Task.detached(priority: .userInitiated) {
            var lines: [RecognizedLine] = []

            if fileType == .pdf {
                lines.append(contentsOf: embeddedPDFTextLines(from: fileURL))
                do {
                    lines.append(contentsOf: try recognizedPDFTextLines(from: fileURL))
                } catch {
                    guard !lines.isEmpty else {
                        throw error
                    }
                }
            } else {
                let images = try imagesForRecognition(from: fileURL, fileType: fileType)
                for (pageIndex, image) in images.enumerated() {
                    lines.append(contentsOf: try recognizeTextLines(in: image, pageIndex: pageIndex))
                }
            }

            guard !lines.isEmpty else {
                throw OCRError.recognitionFailed
            }

            return makeCandidate(from: lines)
        }.value
    }

    private enum RecognitionSource: Hashable {
        case embeddedPDF
        case vision
    }

    private struct RecognizedLine {
        let text: String
        let confidence: Double
        let boundingBox: CGRect?
        let pageIndex: Int
        let source: RecognitionSource

        var normalizedText: String {
            normalizeJapaneseText(text)
        }
    }

    private enum AmountField: CaseIterable {
        case gross
        case net
        case deduction

        var keywords: [String] {
            switch self {
            case .gross:
                ["総支給額", "支給総額", "総支給", "支給額合計", "支給合計"]
            case .net:
                ["差引支給額", "銀行振込額", "振込支給額", "差引支給", "銀行振込", "振込額", "手取り"]
            case .deduction:
                ["控除額合計", "控除合計", "控除総額", "控除計"]
            }
        }

        var minimumAmount: Int {
            switch self {
            case .gross, .net:
                1_000
            case .deduction:
                0
            }
        }
    }

    private struct AmountMatch {
        let value: Int
        let range: NSRange
    }

    private struct ScoredAmount {
        let value: Int
        let score: Double
        let sourceText: String
        let isInferred: Bool
    }

    private static func makeCandidate(from lines: [RecognizedLine]) -> OCRPayRecordCandidate {
        let meaningfulLines = lines.filter { !$0.normalizedText.isEmpty }
        let recognizedText = uniqueRecognizedText(from: meaningfulLines)

        let paymentDate = extractPaymentDate(from: meaningfulLines)
        var gross = bestAmountCandidate(for: .gross, in: meaningfulLines)
        var net = bestAmountCandidate(for: .net, in: meaningfulLines)
        var deduction = bestAmountCandidate(for: .deduction, in: meaningfulLines)

        adjustConfidenceForArithmeticConsistency(
            gross: &gross,
            net: &net,
            deduction: &deduction
        )

        if deduction == nil,
           let gross,
           let net,
           gross.value >= net.value {
            deduction = ScoredAmount(
                value: gross.value - net.value,
                score: 0.45,
                sourceText: "額面と振込額の差から推定",
                isInferred: true
            )
        }

        return OCRPayRecordCandidate(
            paymentDateCandidate: paymentDate,
            grossCandidate: gross.map(makeAmountCandidate),
            netCandidate: net.map(makeAmountCandidate),
            deductionCandidate: deduction.map(makeAmountCandidate),
            recognizedText: recognizedText
        )
    }

    private static func makeAmountCandidate(from candidate: ScoredAmount) -> OCRAmountCandidate {
        OCRAmountCandidate(
            value: candidate.value,
            confidenceScore: clampedScore(candidate.score),
            sourceText: candidate.sourceText,
            isInferred: candidate.isInferred
        )
    }

    private static func embeddedPDFTextLines(from fileURL: URL) -> [RecognizedLine] {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            return []
        }

        let pageLimit = min(document.pageCount, 2)
        return (0..<pageLimit).flatMap { pageIndex -> [RecognizedLine] in
            guard let pageText = document.page(at: pageIndex)?.string else {
                return []
            }

            return pageText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map {
                    RecognizedLine(
                        text: $0,
                        confidence: 0.99,
                        boundingBox: nil,
                        pageIndex: pageIndex,
                        source: .embeddedPDF
                    )
                }
        }
    }

    private static func imagesForRecognition(
        from fileURL: URL,
        fileType: AttachmentFileType
    ) throws -> [CGImage] {
        switch fileType {
        case .image:
            guard let image = UIImage(contentsOfFile: fileURL.path),
                  let cgImage = normalizedCGImage(from: image) else {
                throw OCRError.imageRenderingFailed
            }
            return [cgImage]

        case .pdf, .other:
            throw OCRError.unsupportedFile
        }
    }

    private static func recognizedPDFTextLines(from fileURL: URL) throws -> [RecognizedLine] {
        guard let provider = CGDataProvider(url: fileURL as CFURL),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0 else {
            throw OCRError.unreadablePDF
        }

        var recognizedLines: [RecognizedLine] = []
        let pageLimit = min(document.numberOfPages, 2)

        for pageIndex in 0..<pageLimit {
            guard let page = document.page(at: pageIndex + 1),
                  let image = renderPDFPage(page) else {
                continue
            }

            if let pageLines = try? recognizeTextLines(in: image, pageIndex: pageIndex) {
                recognizedLines.append(contentsOf: pageLines)
            }
        }

        guard !recognizedLines.isEmpty else {
            throw OCRError.recognitionFailed
        }
        return recognizedLines
    }

    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        let maximumDimension: CGFloat = 3_000
        let largestDimension = max(image.size.width, image.size.height)
        guard largestDimension > 0 else {
            return nil
        }

        let scale = min(1, maximumDimension / largestDimension)
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private static func renderPDFPage(_ page: CGPDFPage) -> CGImage? {
        let bounds = page.getBoxRect(.mediaBox)
        let maximumDimension: CGFloat = 3_000
        let normalizedRotation = ((page.rotationAngle % 360) + 360) % 360
        let swapsDimensions = normalizedRotation == 90 || normalizedRotation == 270
        let pageSize = CGSize(
            width: swapsDimensions ? bounds.height : bounds.width,
            height: swapsDimensions ? bounds.width : bounds.height
        )
        let largestDimension = max(pageSize.width, pageSize.height)
        guard largestDimension > 0 else {
            return nil
        }

        let scale = min(3, maximumDimension / largestDimension)
        let width = max(1, Int((pageSize.width * scale).rounded(.up)))
        let height = max(1, Int((pageSize.height * scale).rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(targetRect)
        context.concatenate(
            page.getDrawingTransform(
                .mediaBox,
                rect: targetRect,
                rotate: 0,
                preserveAspectRatio: true
            )
        )
        context.drawPDFPage(page)
        return context.makeImage()
    }

    private static func recognizeTextLines(
        in image: CGImage,
        pageIndex: Int
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.30 else {
                    return nil
                }

                return RecognizedLine(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    boundingBox: observation.boundingBox,
                    pageIndex: pageIndex,
                    source: .vision
                )
            }
            .sorted { lhs, rhs in
                guard let lhsBox = lhs.boundingBox,
                      let rhsBox = rhs.boundingBox else {
                    return lhs.text < rhs.text
                }

                if abs(lhsBox.midY - rhsBox.midY) > 0.012 {
                    return lhsBox.midY > rhsBox.midY
                }
                return lhsBox.minX < rhsBox.minX
            }
    }

    private static func extractPaymentDate(
        from lines: [RecognizedLine]
    ) -> OCRPaymentDateCandidate? {
        var candidates: [OCRPaymentDateCandidate] = []

        for line in lines {
            let text = line.normalizedText
            let contextAdjustment: Double = {
                if ["支給年月", "給与年月", "対象年月", "支給日"].contains(where: { text.contains($0) }) {
                    return 0.03
                }
                if ["発行日", "作成日", "印刷日"].contains(where: { text.contains($0) }) {
                    return -0.15
                }
                return 0
            }()
            let baseScore = clampedScore(
                (line.source == .embeddedPDF ? 0.97 : 0.88 * line.confidence) + contextAdjustment
            )

            if let match = firstMatch(in: text, pattern: #"((?:20)?\d{2})年(\d{1,2})月"#),
               match.count >= 3,
               let rawYear = Int(match[1]),
               let month = Int(match[2]) {
                let year = rawYear < 100 ? 2000 + rawYear : rawYear
                if (2000...2100).contains(year), (1...12).contains(month) {
                    candidates.append(
                        OCRPaymentDateCandidate(
                            year: year,
                            month: month,
                            confidenceScore: baseScore,
                            sourceText: line.text
                        )
                    )
                }
            }

            if let match = firstMatch(in: text, pattern: #"令和(\d{1,2})年(\d{1,2})月"#),
               match.count >= 3,
               let reiwaYear = Int(match[1]),
               let month = Int(match[2]),
               (1...12).contains(month) {
                candidates.append(
                    OCRPaymentDateCandidate(
                        year: 2018 + reiwaYear,
                        month: month,
                        confidenceScore: baseScore,
                        sourceText: line.text
                    )
                )
            }

            let hasDateContext = ["支給", "給与", "対象", "年月"].contains { text.contains($0) }
            if hasDateContext,
               let match = firstMatch(in: text, pattern: #"((?:20)?\d{2})[./-](\d{1,2})(?:[./-]\d{1,2})?"#),
               match.count >= 3,
               let rawYear = Int(match[1]),
               let month = Int(match[2]) {
                let year = rawYear < 100 ? 2000 + rawYear : rawYear
                if (2000...2100).contains(year), (1...12).contains(month) {
                    candidates.append(
                        OCRPaymentDateCandidate(
                            year: year,
                            month: month,
                            confidenceScore: baseScore - 0.08,
                            sourceText: line.text
                        )
                    )
                }
            }
        }

        return candidates.max { lhs, rhs in
            lhs.confidenceScore < rhs.confidenceScore
        }
    }

    private static func bestAmountCandidate(
        for field: AmountField,
        in lines: [RecognizedLine]
    ) -> ScoredAmount? {
        var candidates: [ScoredAmount] = []

        for (index, line) in lines.enumerated() {
            let text = line.normalizedText
            guard let keyword = field.keywords
                .filter({ text.contains($0) })
                .max(by: { $0.count < $1.count }) else {
                continue
            }

            if field == .gross,
               ["課税支給", "課税対象"].contains(where: { text.contains($0) }) {
                continue
            }

            let confidence = line.source == .embeddedPDF ? 0.99 : line.confidence
            if let keywordRange = text.range(of: keyword) {
                let trailingText = String(text[keywordRange.upperBound...])
                for (matchIndex, match) in amountMatches(
                    in: trailingText,
                    minimum: field.minimumAmount
                ).enumerated() {
                    candidates.append(
                        ScoredAmount(
                            value: match.value,
                            score: (0.94 - Double(matchIndex) * 0.04) * confidence,
                            sourceText: line.text,
                            isInferred: false
                        )
                    )
                }
            }

            if let spatialCandidate = spatialAmountCandidate(
                for: field,
                labelLine: line,
                in: lines
            ) {
                candidates.append(spatialCandidate)
            }

            if let tableCandidate = tableAmountCandidate(
                for: field,
                headerLine: line,
                headerIndex: index,
                in: lines
            ) {
                candidates.append(tableCandidate)
            }

            let followingLines = lines.dropFirst(index + 1).prefix(3)
            for (offset, followingLine) in followingLines.enumerated() {
                guard followingLine.pageIndex == line.pageIndex,
                      followingLine.source == line.source else {
                    continue
                }

                let matches = amountMatches(
                    in: followingLine.normalizedText,
                    minimum: field.minimumAmount
                )
                guard let amount = preferredAmount(from: matches.map(\.value), for: field) else {
                    continue
                }

                let baseScore = offset == 0 ? 0.68 : 0.54
                candidates.append(
                    ScoredAmount(
                        value: amount,
                        score: baseScore * min(confidence, followingLine.confidence),
                        sourceText: "\(line.text) / \(followingLine.text)",
                        isInferred: false
                    )
                )
            }
        }

        let deduplicated = Dictionary(grouping: candidates, by: \.value)
            .compactMap { _, matches in
                matches.max { $0.score < $1.score }
            }

        return deduplicated.max { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.02 {
                return lhs.score < rhs.score
            }
            if field == .gross {
                return lhs.value < rhs.value
            }
            return lhs.score < rhs.score
        }
    }

    private static func spatialAmountCandidate(
        for field: AmountField,
        labelLine: RecognizedLine,
        in lines: [RecognizedLine]
    ) -> ScoredAmount? {
        guard labelLine.source == .vision,
              let labelBox = labelLine.boundingBox else {
            return nil
        }

        let candidates = lines.compactMap { line -> ScoredAmount? in
            guard line.source == .vision,
                  line.pageIndex == labelLine.pageIndex,
                  line.text != labelLine.text,
                  let box = line.boundingBox,
                  abs(box.midY - labelBox.midY) <= 0.035,
                  box.minX >= labelBox.minX,
                  let amount = preferredAmount(
                    from: amountMatches(
                        in: line.normalizedText,
                        minimum: field.minimumAmount
                    ).map(\.value),
                    for: field
                  ) else {
                return nil
            }

            let horizontalDistance = max(0, box.minX - labelBox.maxX)
            let distancePenalty = min(0.12, horizontalDistance * 0.20)
            return ScoredAmount(
                value: amount,
                score: (0.91 - distancePenalty) * min(labelLine.confidence, line.confidence),
                sourceText: "\(labelLine.text) / \(line.text)",
                isInferred: false
            )
        }

        return candidates.max { $0.score < $1.score }
    }

    private static func tableAmountCandidate(
        for field: AmountField,
        headerLine: RecognizedLine,
        headerIndex: Int,
        in lines: [RecognizedLine]
    ) -> ScoredAmount? {
        let fieldOrder = fieldPositions(in: headerLine.normalizedText)
            .sorted { $0.position < $1.position }
        guard fieldOrder.count >= 2,
              let fieldIndex = fieldOrder.firstIndex(where: { $0.field == field }) else {
            return nil
        }

        for line in lines.dropFirst(headerIndex + 1).prefix(3) {
            guard line.pageIndex == headerLine.pageIndex,
                  line.source == headerLine.source else {
                continue
            }

            let amounts = amountMatches(
                in: line.normalizedText,
                minimum: 0
            ).map(\.value)
            guard amounts.count >= fieldOrder.count,
                  amounts.indices.contains(fieldIndex) else {
                continue
            }

            return ScoredAmount(
                value: amounts[fieldIndex],
                score: 0.84 * min(headerLine.confidence, line.confidence),
                sourceText: "\(headerLine.text) / \(line.text)",
                isInferred: false
            )
        }

        return nil
    }

    private static func fieldPositions(
        in line: String
    ) -> [(field: AmountField, position: Int)] {
        AmountField.allCases.compactMap { field in
            let positions = field.keywords.compactMap { keyword in
                line.range(of: keyword)?.lowerBound.utf16Offset(in: line)
            }
            guard let position = positions.min() else {
                return nil
            }
            return (field, position)
        }
    }

    private static func preferredAmount(
        from amounts: [Int],
        for field: AmountField
    ) -> Int? {
        let plausibleAmounts = amounts.filter {
            $0 >= field.minimumAmount && $0 <= 100_000_000
        }

        switch field {
        case .gross:
            return plausibleAmounts.max()
        case .net, .deduction:
            return plausibleAmounts.last
        }
    }

    private static func adjustConfidenceForArithmeticConsistency(
        gross: inout ScoredAmount?,
        net: inout ScoredAmount?,
        deduction: inout ScoredAmount?
    ) {
        guard let currentGross = gross,
              let currentNet = net,
              let currentDeduction = deduction else {
            return
        }

        let difference = abs(currentGross.value - currentNet.value - currentDeduction.value)
        let matchingTolerance = max(100, Int(Double(currentGross.value) * 0.005))
        let mismatchTolerance = max(1_000, Int(Double(currentGross.value) * 0.03))

        if difference <= matchingTolerance {
            gross = adjustedScore(currentGross, by: 0.04)
            net = adjustedScore(currentNet, by: 0.04)
            deduction = adjustedScore(currentDeduction, by: 0.04)
        } else if difference > mismatchTolerance {
            gross = adjustedScore(currentGross, by: -0.12)
            net = adjustedScore(currentNet, by: -0.12)
            deduction = adjustedScore(currentDeduction, by: -0.12)
        }
    }

    private static func adjustedScore(
        _ candidate: ScoredAmount,
        by adjustment: Double
    ) -> ScoredAmount {
        ScoredAmount(
            value: candidate.value,
            score: clampedScore(candidate.score + adjustment),
            sourceText: candidate.sourceText,
            isInferred: candidate.isInferred
        )
    }

    private static func amountMatches(
        in text: String,
        minimum: Int
    ) -> [AmountMatch] {
        let pattern = #"([¥￥]?\d{1,3}(?:,\d{3})+|[¥￥]?\d{4,9}|(?<!\d)0(?!\d))円?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else {
                return nil
            }

            let matchedText = nsText.substring(with: valueRange)
            let digits = matchedText.filter(\.isNumber)
            guard let value = Int(digits),
                  value >= minimum,
                  value <= 100_000_000 else {
                return nil
            }
            return AmountMatch(value: value, range: valueRange)
        }
    }

    private static func normalizeJapaneseText(_ text: String) -> String {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfWidth
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueRecognizedText(from lines: [RecognizedLine]) -> String {
        var seen = Set<String>()
        return lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else {
                return nil
            }
            return text
        }.joined(separator: "\n")
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).compactMap { index in
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound else {
                return nil
            }
            return nsText.substring(with: matchRange)
        }
    }

    private static func clampedScore(_ score: Double) -> Double {
        min(1, max(0, score))
    }
}
