import AppKit

/// Builds the application icon from the running dog artwork.
///
/// The dog is drawn on a shared canvas so the frames line up with each
/// other, which leaves a lot of empty space around the animal. For the icon
/// the dog is cropped to its own bounds and scaled up, so it fills the
/// rounded-rectangle shape the way an app icon is expected to.
///
/// Run with:  swift Tools/AppIcon/main.swift <output-dir>

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

try? FileManager.default.createDirectory(
    atPath: outputDirectory,
    withIntermediateDirectories: true
)

/// The frame of the run cycle used for the icon: legs fully stretched out,
/// facing forward — the pose that reads as "running" at a glance.
let iconFrame = 5

/// Locates the dog artwork.
func locateDogFrame() -> NSImage? {
    let candidates = [
        URL(fileURLWithPath: "./CatBar/Resources/DogFrames"),
        URL(fileURLWithPath: "./build/Build/Products/Release/RunBar.app/Contents/Resources"),
        URL(fileURLWithPath: "./CatBarApp/RunBar.app/Contents/Resources")
    ]
    for directory in candidates {
        let name = String(format: "dog_run_%02d.png", iconFrame)
        let url = directory.appendingPathComponent(name)
        if let image = NSImage(contentsOf: url) {
            return image
        }
    }
    return nil
}

guard let frame = locateDogFrame() else {
    print("找不到小狗素材")
    exit(1)
}

// Work in pixels: the artwork is 4x, so the logical size is a quarter.
guard let source = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("无法读取素材")
    exit(1)
}
let pixelWidth = source.width
let pixelHeight = source.height

// Find the dog's own bounds so the icon is not mostly empty space.
var minX = pixelWidth, minY = pixelHeight, maxX = 0, maxY = 0
var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
if let context = CGContext(
    data: &pixels, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
    bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) {
    context.draw(source, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    for y in 0..<pixelHeight {
        for x in 0..<pixelWidth {
            if pixels[(y * pixelWidth + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
}
print("小狗内容范围: x=[\(minX),\(maxX)] y=[\(minY),\(maxY)]")

// Pad a little so the drawing does not touch the edge of the icon.
let padding = Int(Double(pixelWidth) * 0.06)
minX = max(0, minX - padding); minY = max(0, minY - padding)
maxX = min(pixelWidth - 1, maxX + padding); maxY = min(pixelHeight - 1, maxY + padding)

let cropRect = CGRect(x: minX, y: minY,
                       width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = source.cropping(to: cropRect) else { exit(1) }

// The icon sizes macOS asks for.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

/// Renders the icon at an exact pixel size.
///
/// The drawing is done with Core Graphics directly, so the output is exactly
/// the number of pixels asked for — `NSImage.tiffRepresentation` would
/// otherwise hand back a Retina-sized bitmap.
func render(pixels: Int) -> Data? {
    let scale: CGFloat = 2
    let points = CGFloat(pixels) / scale

    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    guard let context = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high

    // The rounded rectangle macOS icons use, inset so the shape shows.
    let inset = points * 0.055
    let box = CGRect(x: inset, y: inset,
                     width: points - inset * 2,
                     height: points - inset * 2)
    let path = CGPath(roundedRect: box, cornerWidth: box.width * 0.2237,
                      cornerHeight: box.height * 0.2237, transform: nil)
    context.addPath(path)
    context.clip()

    // A gradient reads better than flat colour at small sizes.
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [
                                    NSColor(calibratedRed: 0.29, green: 0.66, blue: 0.94, alpha: 1).cgColor,
                                    NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.78, alpha: 1).cgColor
                                 ] as CFArray,
                                 locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: box.midX, y: box.maxY),
                                   end: CGPoint(x: box.midX, y: box.minY),
                                   options: [])
    }

    // The dog, scaled to fill the box.
    let fit = box.width / CGFloat(cropped.width)
    let width = CGFloat(cropped.width) * fit
    let height = CGFloat(cropped.height) * fit
    context.draw(cropped, in: CGRect(x: box.midX - width / 2,
                                     y: box.midY - height / 2,
                                     width: width, height: height))

    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])
}

for (name, pixels) in sizes {
    guard let png = render(pixels: pixels) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name).png"))
}

print("已生成 \(sizes.count) 个尺寸的图标")
