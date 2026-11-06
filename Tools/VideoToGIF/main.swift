import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Converts a video into an animated GIF, making the flat background
/// transparent on the way.
///
/// The source video has no alpha channel; instead its backdrop is a
/// checkerboard of two greys, the usual way of showing "transparent" in a
/// video editor. Both greys have to be keyed out, otherwise half the
/// checkerboard survives and shows up as speckle.
///
/// Keying on the distance to the *nearer* of the two greys keeps the
/// anti-aliased edges clean: a pixel that blends one grey into the other
/// becomes partly transparent rather than keeping a grey halo.
///
/// GIF only has a 256-colour palette. A global palette is shared by every
/// frame, and because the drawing changes subtly from frame to frame the
/// colours drift and leave speckles in the transparent areas. Switching the
/// global palette off gives each frame its own, which looks much cleaner.
///
/// Run with:  swift Tools/VideoToGIF/main.swift <video> <output.gif> [fps] [width]

let videoPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let fps = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 20) : 20
let targetWidth = CommandLine.arguments.count > 4 ? (Int(CommandLine.arguments[4]) ?? 360) : 360

// MARK: - Reading the video

let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
let duration = CMTimeGetSeconds(asset.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let frameCount = max(1, Int((duration - 0.05) * Double(fps)))
print("时长 \(String(format: "%.2f", duration)) 秒，\(fps) fps，目标 \(frameCount) 帧")

/// The two greys of the checkerboard backdrop.
var backdropA = (r: 212.0, g: 212.0, b: 214.0)
var backdropB = (r: 245.0, g: 245.0, b: 246.0)

/// How far a pixel may sit from a backdrop grey before it counts as opaque.
let tolerance = 30.0

/// Finds the two most common greys in the top strip of the frame, which is
/// all backdrop.
func findBackdrops(_ pixels: [UInt8], width: Int, height: Int) -> ((r: Double, g: Double, b: Double), (r: Double, g: Double, b: Double)) {
    var histogram: [Int: Int] = [:]
    for y in 0..<(height / 3) {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let grey = Int(pixels[i])
            histogram[grey, default: 0] += 1
        }
    }
    let sorted = histogram.sorted { $0.value > $1.value }
    let first = sorted.first?.key ?? 212
    // The second grey is the most common one that is clearly different.
    let second = sorted.first { abs($0.key - first) > 12 }?.key ?? (first + 32)
    return (
        (Double(first), Double(first), Double(first + 2)),
        (Double(second), Double(second), Double(second + 1))
    )
}

/// Reads a frame, scales it, and removes the backdrop.
func preparedFrame(at index: Int) -> CGImage? {
    let time = CMTime(seconds: Double(index) / Double(fps), preferredTimescale: 600)
    guard let source = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }

    let ratio = Double(targetWidth) / Double(source.width)
    let width = targetWidth
    let height = max(1, Int(Double(source.height) * ratio))

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    if index == 0 {
        let found = findBackdrops(pixels, width: width, height: height)
        backdropA = found.0
        backdropB = found.1
        print("背景双色: (\(Int(backdropA.r)), \(Int(backdropA.g)), \(Int(backdropA.b)))"
            + " 和 (\(Int(backdropB.r)), \(Int(backdropB.g)), \(Int(backdropB.b)))")
    }

    // Key out both greys. The nearer one decides how transparent the pixel
    // is, so the soft edges fade instead of keeping a grey rim.
    for i in stride(from: 0, to: width * height * 4, by: 4) {
        let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])

        func distance(to backdrop: (r: Double, g: Double, b: Double)) -> Double {
            sqrt((r - backdrop.r) * (r - backdrop.r)
               + (g - backdrop.g) * (g - backdrop.g)
               + (b - backdrop.b) * (b - backdrop.b))
        }

        let nearest = min(distance(to: backdropA), distance(to: backdropB))
        pixels[i + 3] = UInt8(min(1.0, nearest / tolerance) * 255)
    }

    // Premultiply, which is what the GIF encoder expects.
    for i in stride(from: 0, to: width * height * 4, by: 4) {
        let alpha = Double(pixels[i + 3]) / 255
        pixels[i] = UInt8(Double(pixels[i]) * alpha)
        pixels[i + 1] = UInt8(Double(pixels[i + 1]) * alpha)
        pixels[i + 2] = UInt8(Double(pixels[i + 2]) * alpha)
    }

    return context.makeImage()
}

// MARK: - Writing the GIF

guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL,
    UTType.gif.identifier as CFString,
    frameCount,
    nil
) else {
    print("无法创建 GIF")
    exit(1)
}

// Turning the global palette off gives every frame its own, which avoids the
// colour speckles a shared palette leaves in the transparent areas.
let containerProperties: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0,
        kCGImagePropertyGIFHasGlobalColorMap: false
    ]
]
CGImageDestinationSetProperties(destination, containerProperties as CFDictionary)

var written = 0
for index in 0..<frameCount {
    guard let frame = preparedFrame(at: index) else { continue }
    let properties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)
        ]
    ]
    CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
    written += 1
}

if CGImageDestinationFinalize(destination) {
    print("GIF 已生成: \(outputPath)（\(written) 帧）")
} else {
    print("生成失败")
    exit(1)
}
