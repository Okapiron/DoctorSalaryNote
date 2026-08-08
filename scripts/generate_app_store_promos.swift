import AppKit
import Foundation

struct Promo {
    let source: String
    let output: String
    let titlePrimary: String
    let titleAccent: String
    let subtitle: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDir = root.appendingPathComponent("docs/app-store-screenshots/source", isDirectory: true)
let outputDir = root.appendingPathComponent("docs/app-store-screenshots/iphone-6.9", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let promos = [
    Promo(
        source: sourceDir.appendingPathComponent("01_home.png").path,
        output: "01_home_summary.png",
        titlePrimary: "医師の収入を、",
        titleAccent: "ひとつに。",
        subtitle: "Dr's Salaryで給与・収入をまとめて管理"
    ),
    Promo(
        source: sourceDir.appendingPathComponent("02_ocr_import.png").path,
        output: "02_ocr_import.png",
        titlePrimary: "給与明細を撮って、",
        titleAccent: "かんたん記録。",
        subtitle: "カメラ・写真・PDFから選んで取り込み"
    ),
    Promo(
        source: sourceDir.appendingPathComponent("03_ocr_result.png").path,
        output: "03_ocr_result.png",
        titlePrimary: "給与明細を",
        titleAccent: "OCRで読み取り",
        subtitle: "読み取り結果を確認・修正して保存"
    ),
    Promo(
        source: sourceDir.appendingPathComponent("04_income_breakdown.png").path,
        output: "04_income_breakdown.png",
        titlePrimary: "複数勤務先の給与を",
        titleAccent: "まとめて管理",
        subtitle: "常勤・外勤・スポット・賞与を見える化"
    ),
    Promo(
        source: sourceDir.appendingPathComponent("05_salary_trend.png").path,
        output: "05_salary_trend.png",
        titlePrimary: "月ごと・年ごとの収入が",
        titleAccent: "ひと目でわかる",
        subtitle: "額面・手取り・控除の推移を確認"
    ),
    Promo(
        source: sourceDir.appendingPathComponent("06_documents.png").path,
        output: "06_documents.png",
        titlePrimary: "給与明細や書類も",
        titleAccent: "まとめて保存",
        subtitle: "給与明細・源泉徴収票・支払調書を整理"
    )
]

let canvasSize = NSSize(width: 1290, height: 2796)
let accent = NSColor(calibratedRed: 78 / 255, green: 195 / 255, blue: 211 / 255, alpha: 1)
let accentDark = NSColor(calibratedRed: 25 / 255, green: 139 / 255, blue: 158 / 255, alpha: 1)
let bgTop = NSColor(calibratedRed: 238 / 255, green: 249 / 255, blue: 252 / 255, alpha: 1)
let bgBottom = NSColor(calibratedRed: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1)
let textPrimary = NSColor(calibratedWhite: 0.06, alpha: 1)
let textSecondary = NSColor(calibratedWhite: 0.42, alpha: 1)
let navy = NSColor(calibratedRed: 4 / 255, green: 30 / 255, blue: 72 / 255, alpha: 1)

func font(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(in: rect, withAttributes: attrs)
}

func drawCenteredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
    drawText(text, in: rect, font: font, color: color, alignment: .center)
}

func addRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawGradientBackground() {
    let gradient = NSGradient(colors: [bgTop, bgBottom])!
    gradient.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -90)
    accent.withAlphaComponent(0.14).setFill()
    NSBezierPath(ovalIn: NSRect(x: -240, y: 2180, width: 560, height: 560)).fill()
    accent.withAlphaComponent(0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: 1008, y: 2250, width: 420, height: 420)).fill()
}

func drawDeviceScreenshot(_ image: NSImage) {
    let cropTop: CGFloat = 118
    let cropRect = NSRect(x: 0, y: cropTop, width: image.size.width, height: image.size.height - cropTop)
    let screenWidth: CGFloat = 970
    let screenHeight = cropRect.height * (screenWidth / cropRect.width)
    let x = (canvasSize.width - screenWidth) / 2
    let y: CGFloat = 170
    let screenRect = NSRect(x: x, y: y, width: screenWidth, height: min(screenHeight, 2140))
    let bezel: CGFloat = 34
    let deviceRect = screenRect.insetBy(dx: -bezel, dy: -bezel)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.set()
    addRoundedRect(deviceRect, radius: 78, color: NSColor(calibratedWhite: 0.06, alpha: 1))
    NSGraphicsContext.current?.restoreGraphicsState()

    addRoundedRect(deviceRect.insetBy(dx: 8, dy: 8), radius: 70, color: NSColor(calibratedWhite: 0.12, alpha: 1))

    let topSensor = NSRect(x: deviceRect.midX - 72, y: deviceRect.maxY - 42, width: 144, height: 13)
    addRoundedRect(topSensor, radius: 6.5, color: NSColor(calibratedWhite: 0.02, alpha: 1))

    let clip = NSBezierPath(roundedRect: screenRect, xRadius: 50, yRadius: 50)
    NSGraphicsContext.current?.saveGraphicsState()
    clip.addClip()
    image.draw(in: screenRect, from: cropRect, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.current?.restoreGraphicsState()

    let statusMask = NSRect(x: screenRect.minX, y: screenRect.maxY - 126, width: screenRect.width, height: 126)
    NSGraphicsContext.current?.saveGraphicsState()
    let topClip = NSBezierPath(roundedRect: screenRect, xRadius: 50, yRadius: 50)
    topClip.addClip()
    NSColor(calibratedRed: 246 / 255, green: 247 / 255, blue: 251 / 255, alpha: 1).setFill()
    statusMask.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.34).setStroke()
    let deviceStroke = NSBezierPath(roundedRect: deviceRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 77, yRadius: 77)
    deviceStroke.lineWidth = 3
    deviceStroke.stroke()

    NSColor.black.withAlphaComponent(0.20).setStroke()
    let screenStroke = NSBezierPath(roundedRect: screenRect, xRadius: 50, yRadius: 50)
    screenStroke.lineWidth = 2
    screenStroke.stroke()
}

for promo in promos {
    guard let sourceImage = NSImage(contentsOfFile: promo.source) else {
        fputs("Missing source image: \(promo.source)\n", stderr)
        exit(1)
    }

    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()
    drawGradientBackground()

    drawText(promo.titlePrimary, in: NSRect(x: 70, y: 2540, width: 1160, height: 112), font: font(106, weight: .heavy), color: navy)
    drawText(promo.titleAccent, in: NSRect(x: 70, y: 2404, width: 1160, height: 132), font: font(126, weight: .heavy), color: accentDark)
    drawText(promo.subtitle, in: NSRect(x: 76, y: 2292, width: 1140, height: 92), font: font(52, weight: .bold), color: textSecondary, lineHeight: 62)

    drawDeviceScreenshot(sourceImage)
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render: \(promo.output)\n", stderr)
        exit(1)
    }

    try png.write(to: outputDir.appendingPathComponent(promo.output))
    print(outputDir.appendingPathComponent(promo.output).path)
}
