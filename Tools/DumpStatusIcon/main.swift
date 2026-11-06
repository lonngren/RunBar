import AppKit

/// Dumps the exact image the status bar button is currently displaying, so the
/// real runtime output can be inspected instead of guessing from screenshots.
///
/// Run with:  swift Tools/DumpStatusIcon/main.swift <output.png>

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/statusicon.png"

/// Reads the packaged frames from the installed app.
func loadFrames() -> [NSImage] {
    let candidates = [
        URL(fileURLWithPath: "/Applications/CatBar.app"),
        URL(fileURLWithPath: "./build/Build/Products/Release/CatBar.app")
    ]
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
          let bundle = Bundle(url: url) else { return [] }

    return (0..<5).compactMap { index in
        let name = "cat_run_\(String(format: "%02d", index))"
        guard let resourceURL = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: resourceURL) else { return nil }
        if let rep = image.representations.first as? NSBitmapImageRep {
            rep.size = NSSize(width: 44, height: 22)
        }
        image.size = NSSize(width: 44, height: 22)
        return image
    }
}

let frames = loadFrames()
guard !frames.isEmpty else {
    print("找不到素材")
    exit(1)
}

print("=== 运行时状态栏图标检查 ===")
for (index, frame) in frames.enumerated() {
    let tinted = StatusBarImage.recolor(frame, to: .white)
    let rep = tinted.representations.first as? NSBitmapImageRep
    print("  帧 \(index): image.size=\(tinted.size)  rep 像素=\(rep?.pixelsWide ?? 0)x\(rep?.pixelsHigh ?? 0)  rep.size=\(rep?.size ?? .zero)")
}

let composed = StatusBarImage.compose(cat: frames[2], text: nil, appearance: NSAppearance.currentDrawing())
print("合成后 image.size = \(composed.size)")

// Write the composed image at high resolution for inspection.
// Use the tinted (white) frame — that is what the app actually shows.
let tinted = StatusBarImage.recolor(frames[2], to: .white)
let composedLight = StatusBarImage.compose(cat: tinted, text: nil, appearance: NSAppearance.currentDrawing())
guard let tiff = composedLight.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else { exit(1) }
let scaled = NSImage(size: NSSize(width: 44 * 6, height: 22 * 6))
scaled.lockFocus()
NSColor.black.setFill()
NSRect(origin: .zero, size: scaled.size).fill()
composedLight.draw(in: NSRect(origin: .zero, size: scaled.size),
                   from: .zero, operation: .sourceOver, fraction: 1)
scaled.unlockFocus()
if let t = scaled.tiffRepresentation, let r = NSBitmapImageRep(data: t),
   let png = r.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: outputPath))
    print("已导出运行时图标: \(outputPath)")
}
