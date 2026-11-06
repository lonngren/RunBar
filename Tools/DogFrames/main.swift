import AppKit
import ImageIO

/// Converts the running-dog GIF into menu bar frames, doubling the frame rate
/// with motion-compensated interpolation.
///
/// The source animation has sixteen frames, and at the speed the dog runs at
/// that is not enough to look smooth. This tool inserts an extra frame
/// between every pair, so the cycle becomes thirty-two frames.
///
/// Interpolating a plain cross-fade does not work here: the dog moves a long
/// way between frames, so the blend shows two overlapping dogs. The fix is to
/// align the two frames on their centre of mass before combining them — the
/// translation is compensated, which removes the ghosting. The remaining
/// difference between the two frames is the shape change (the dog folding
/// itself up mid-jump), which no translation can undo, so the intermediate
/// frame is taken from whichever of the two aligned frames has the sharper
/// outline. That keeps every frame a single, crisp dog.
///
/// Run with:  swift Tools/DogFrames/main.swift <output-dir>

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

/// Where the source GIF lives.
let sourcePath = "/Users/long/Downloads/奔跑小狗-透明.gif"

try? FileManager.default.createDirectory(
    atPath: outputDirectory,
    withIntermediateDirectories: true
)

guard let sourceData = NSData(contentsOfFile: sourcePath),
      let source = CGImageSourceCreateWithData(sourceData, nil) else {
    print("找不到源文件: \(sourcePath)")
    exit(1)
}

let sourceFrameCount = CGImageSourceGetCount(source)
print("源动画共 \(sourceFrameCount) 帧")

// The source frames all share one canvas — the union of their content — so
// the bounce reads as movement instead of rescaling.
let canvasWidth = 379, canvasHeight = 290
let union = CGRect(x: 10, y: 10, width: 360, height: 271)

// MARK: - Reading the frames

/// One frame as straight RGBA bytes.
struct Frame {
    var pixels: [UInt8]
    var center: (x: Double, y: Double)
}

/// Renders a source frame onto the shared canvas and returns its pixels.
func readFrame(_ index: Int) -> Frame? {
    guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }

    var pixels = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * 4)
    guard let context = CGContext(
        data: &pixels, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8,
        bytesPerRow: canvasWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Draw the frame at its own position — the canvas is the size of the
    // source image, so the frames line up with each other.
    context.draw(cg, in: CGRect(x: 0, y: 0,
                                 width: canvasWidth, height: canvasHeight))

    // The centre of mass tells us how far the dog has moved.
    var total: Double = 0, sumX: Double = 0, sumY: Double = 0
    for y in 0..<canvasHeight {
        for x in 0..<canvasWidth {
            let alpha = Double(pixels[(y * canvasWidth + x) * 4 + 3])
            if alpha > 10 {
                total += alpha
                sumX += Double(x) * alpha
                sumY += Double(y) * alpha
            }
        }
    }
    let center = total > 0 ? (sumX / total, sumY / total) : (0, 0)
    return Frame(pixels: pixels, center: center)
}

var frames: [Frame] = []
for index in 0..<sourceFrameCount {
    if let frame = readFrame(index) { frames.append(frame) }
}
guard frames.count >= 2 else {
    print("帧数不足")
    exit(1)
}
print("已读取 \(frames.count) 帧")

// MARK: - Interpolation

/// Shifts a frame by a fractional offset, interpolating bilinearly.
func shifted(_ frame: Frame, dx: Double, dy: Double) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * 4)
    let source = frame.pixels

    for y in 0..<canvasHeight {
        let sampleY = Double(y) - dy
        let y0 = Int(floor(sampleY))
        let weightY = sampleY - Double(y0)

        for x in 0..<canvasWidth {
            let sampleX = Double(x) - dx
            let x0 = Int(floor(sampleX))
            let weightX = sampleX - Double(x0)

            var red: Double = 0, green: Double = 0, blue: Double = 0, alpha: Double = 0
            let taps = [
                (x0, y0, (1 - weightX) * (1 - weightY)),
                (x0 + 1, y0, weightX * (1 - weightY)),
                (x0, y0 + 1, (1 - weightX) * weightY),
                (x0 + 1, y0 + 1, weightX * weightY)
            ]
            for (tapX, tapY, weight) in taps {
                guard tapX >= 0, tapX < canvasWidth, tapY >= 0, tapY < canvasHeight else { continue }
                let index = (tapY * canvasWidth + tapX) * 4
                let a = Double(source[index + 3]) / 255
                red += Double(source[index]) * a * weight
                green += Double(source[index + 1]) * a * weight
                blue += Double(source[index + 2]) * a * weight
                alpha += a * weight
            }

            let out = (y * canvasWidth + x) * 4
            if alpha > 0.001 {
                output[out] = UInt8(min(255, red / alpha))
                output[out + 1] = UInt8(min(255, green / alpha))
                output[out + 2] = UInt8(min(255, blue / alpha))
            }
            output[out + 3] = UInt8(min(255, alpha * 255))
        }
    }
    return output
}

/// A measure of how crisp an outline is: the total difference between
/// neighbouring alpha values.
func sharpness(_ pixels: [UInt8]) -> Double {
    var total: Double = 0
    for y in 1..<(canvasHeight - 1) {
        for x in 1..<(canvasWidth - 1) {
            let left = Double(pixels[(y * canvasWidth + x - 1) * 4 + 3])
            let right = Double(pixels[(y * canvasWidth + x + 1) * 4 + 3])
            let up = Double(pixels[((y - 1) * canvasWidth + x) * 4 + 3])
            let down = Double(pixels[((y + 1) * canvasWidth + x) * 4 + 3])
            total += abs(left - right) + abs(up - down)
        }
    }
    return total
}

/// Builds a CGImage from straight RGBA bytes.
func makeImage(from pixels: [UInt8]) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    // The pixels come straight out of a premultiplied-alpha context, so the
    // bitmap has to declare the same layout.
    return CGImage(
        width: canvasWidth, height: canvasHeight,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: canvasWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )
}

/// The interpolated cycle: every source frame, plus one in-between frame.
var cycle: [[UInt8]] = []
for index in 0..<frames.count {
    cycle.append(frames[index].pixels)

    let next = frames[(index + 1) % frames.count]
    let current = frames[index]
    let dx = next.center.x - current.center.x
    let dy = next.center.y - current.center.y

    // Align the two frames on their centre of mass, then keep the sharper
    // one — blending would smear the shape change.
    let alignedCurrent = shifted(current, dx: dx * 0.5, dy: dy * 0.5)
    let alignedNext = shifted(next, dx: -dx * 0.5, dy: -dy * 0.5)
    cycle.append(sharpness(alignedCurrent) >= sharpness(alignedNext)
                 ? alignedCurrent
                 : alignedNext)
}
print("插值后共 \(cycle.count) 帧")

// MARK: - Writing the frames

let targetHeight: CGFloat = 22
let scale = targetHeight / union.height
let targetWidth = union.width * scale
let factor: CGFloat = 4     // Retina

print("每帧尺寸: \(Int(targetWidth * factor))x\(Int(targetHeight * factor)) 像素")

for (index, pixels) in cycle.enumerated() {
    guard let sourceImage = makeImage(from: pixels) else { continue }

    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(targetWidth * factor),
        pixelsHigh: Int(targetHeight * factor),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }

    // Crop the shared canvas down to the part every frame uses, then scale
    // that into the target size.
    guard let cropped = sourceImage.cropping(to: union) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    if let context = NSGraphicsContext.current?.cgContext {
        context.interpolationQuality = .high
        // The representation is already at pixel resolution, so the cropped
        // frame is scaled straight into it.
        context.draw(cropped, in: CGRect(x: 0, y: 0,
                                         width: CGFloat(representation.pixelsWide),
                                         height: CGFloat(representation.pixelsHigh)))
    }
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: targetWidth, height: targetHeight))
    image.addRepresentation(representation)

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }

    let name = String(format: "dog_run_%02d.png", index)
    try? png.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name)"))
}

print("已导出 \(cycle.count) 帧到 \(outputDirectory)")
