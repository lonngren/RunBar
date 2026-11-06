import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Extracts the frames of the resting-dog video as lossless PNGs.
///
/// The video has a checkerboard "transparency" backdrop baked into it, so the
/// frames are exported *untouched*. `make_frames.py` removes the backdrop from
/// these PNGs; working from the original video avoids the colour damage the
/// earlier GIF conversion caused (its colour key also erased the white body).
///
/// Run with:
///   swift Tools/RestDogFrames/ExtractFrames.swift <video.mp4> <output-dir> [fps]

let videoPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]
let fps = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 20) : 20

let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
let duration = CMTimeGetSeconds(asset.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let frameCount = max(1, Int((duration - 0.05) * Double(fps)))
print("时长 \(String(format: "%.2f", duration)) 秒，\(fps) fps，目标 \(frameCount) 帧")

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

var written = 0
for index in 0..<frameCount {
    let time = CMTime(seconds: Double(index) / Double(fps), preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }

    let url = URL(fileURLWithPath: outputDir)
        .appendingPathComponent(String(format: "raw_%03d.png", index))
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    if CGImageDestinationFinalize(destination) { written += 1 }
}

print("已导出 \(written) 帧到 \(outputDir)")
