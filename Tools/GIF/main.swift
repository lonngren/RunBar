import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Builds an animated GIF of a character, so the motion can be reviewed
/// without launching the app.
///
/// Run with:  swift Tools/GIF/main.swift <output.gif> [cat|dog]
///
/// This is a development helper and is not part of the shipping app.

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/cat.gif"

let characterName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "cat"
let isDog = characterName == "dog"
let frameCount = isDog ? 32 : 5
let prefix = isDog ? "dog_run" : "cat_run"
let canvasWidth: CGFloat = isDog ? 29 : 44

/// Reads the packaged frames from the installed app.
func loadFrames() -> [NSImage] {
    let candidates = [
        URL(fileURLWithPath: "/Applications/CatBar.app"),
        URL(fileURLWithPath: "./build/Build/Products/Release/CatBar.app")
    ]
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
          let bundle = Bundle(url: url) else { return [] }

    return (0..<frameCount).compactMap { index in
        let name = "\(prefix)_\(String(format: "%02d", index))"
        guard let resourceURL = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: resourceURL) else { return nil }
        if let representation = image.representations.first as? NSBitmapImageRep {
            representation.size = NSSize(width: canvasWidth, height: 22)
        }
        image.size = NSSize(width: canvasWidth, height: 22)
        return image
    }
}

let frames = loadFrames()
guard !frames.isEmpty else {
    print("找不到素材帧，请先构建 App")
    exit(1)
}

/// Draws each frame on an opaque background — GIF handles alpha poorly.
func flattened(_ image: NSImage) -> NSImage {
    let canvas = NSImage(size: image.size)
    canvas.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.draw(in: NSRect(origin: .zero, size: image.size),
               from: .zero, operation: .sourceOver, fraction: 1)
    canvas.unlockFocus()
    return canvas
}

// Two cycles so the loop reads clearly.
let cycle = (frames + frames).map(flattened)

guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL,
    UTType.gif.identifier as CFString,
    cycle.count,
    nil
) else {
    print("无法创建 GIF")
    exit(1)
}

for frame in cycle {
    guard let cgImage = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 0.08
        ]
    ]
    CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
}

if CGImageDestinationFinalize(destination) {
    print("GIF 已生成: \(outputPath)")
} else {
    print("GIF 生成失败")
    exit(1)
}
