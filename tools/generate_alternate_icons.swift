import AppKit
import CoreImage
import Foundation

enum IconVariant {
    case pink
    case green
    case gray

    var iconSetName: String {
        switch self {
        case .pink: "AppIcon-Pink"
        case .green: "AppIcon-Green"
        case .gray: "AppIcon-Gray"
        }
    }

    var hueAdjustment: Float? {
        switch self {
        case .pink: .pi * 0.54
        case .green: -.pi * 0.46
        case .gray: nil
        }
    }
}

let fileManager = FileManager.default
let repositoryURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetsURL = repositoryURL.appending(path: "DoctorSalaryNote/Assets.xcassets")
let sourceURL = assetsURL.appending(path: "AppIcon.appiconset/AppIcon-1024.png")
let context = CIContext()

guard let sourceImage = CIImage(contentsOf: sourceURL) else {
    fatalError("Unable to read \(sourceURL.path())")
}

for variant in [IconVariant.pink, .green, .gray] {
    let outputImage: CIImage

    if let hueAdjustment = variant.hueAdjustment {
        let filter = CIFilter(name: "CIHueAdjust")!
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        filter.setValue(hueAdjustment, forKey: kCIInputAngleKey)
        outputImage = filter.outputImage ?? sourceImage
    } else {
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        filter.setValue(1.08, forKey: kCIInputContrastKey)
        filter.setValue(-0.04, forKey: kCIInputBrightnessKey)
        outputImage = filter.outputImage ?? sourceImage
    }

    guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent),
          let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        fatalError("Unable to render \(variant.iconSetName)")
    }

    let iconSetURL = assetsURL.appending(path: "\(variant.iconSetName).appiconset")
    try fileManager.createDirectory(at: iconSetURL, withIntermediateDirectories: true)
    try pngData.write(to: iconSetURL.appending(path: "AppIcon-1024.png"))

    let contents = """
    {
      \"images\" : [
        {
          \"filename\" : \"AppIcon-1024.png\",
          \"idiom\" : \"universal\",
          \"platform\" : \"ios\",
          \"size\" : \"1024x1024\"
        }
      ],
      \"info\" : {
        \"author\" : \"xcode\",
        \"version\" : 1
      }
    }
    """
    try contents.data(using: .utf8)?.write(to: iconSetURL.appending(path: "Contents.json"))
}
