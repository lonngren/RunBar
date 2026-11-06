import AppKit

/// Renders the app's real frames at true menu-bar size on both light and dark
/// backgrounds, so the artwork can be judged as it will actually appear.
///
/// Run with:  swift Tools/MenuPreview/main.swift <output-dir>

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

try? FileManager.default.createDirectory(
    atPath: outputDirectory,
    withIntermediateDirectories: true
)

/// The menu bar item's real height on a modern Mac, in points.
let menuBarHeight: CGFloat = 22
let scale: CGFloat = 3      // render at 3x so the preview is legible when zoomed

/// Loads the bundled frames the same way the app does.
func loadFrames() -> [NSImage] {
    let names = (0..<5).map { "cat_run_\(String(format: "%02d", $0))" }
    let bundle = Bundle(for: BundleToken.self)
    return names.compactMap { name in
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 44, height: 22)
        return image
    }
}

/// Finds the built app bundle so the preview uses the real packaged artwork.
func locateAppBundle() -> Bundle? {
    let candidates = [
        URL(fileURLWithPath: "./build/Build/Products/Release/CatBar.app"),
        URL(fileURLWithPath: "./CatBarApp/CatBar.app"),
        URL(fileURLWithPath: "../CatBarApp/CatBar.app")
    ]
    for url in candidates where FileManager.default.fileExists(atPath: url.path) {
        return Bundle(url: url)
    }
    return nil
}

final class BundleToken {}

let appBundle = locateAppBundle()
let frames: [NSImage]
if let appBundle {
    frames = (0..<5).compactMap { index in
        let name = "cat_run_\(String(format: "%02d", index))"
        guard let url = appBundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 44, height: 22)
        return image
    }
} else {
    frames = loadFrames()
}

guard !frames.isEmpty else {
    print("找不到素材帧，请先构建 App")
    exit(1)
}

/// Renders a strip that mimics the menu bar: the cat at true height, spaced
/// out the way status items are.
func renderStrip(background: NSColor, path: String) {
    let catWidth = frames[0].size.width
    let spacing: CGFloat = 18
    let canvas = NSImage(size: NSSize(
        width: (catWidth + spacing) * CGFloat(frames.count),
        height: menuBarHeight
    ))

    canvas.lockFocus()
    background.setFill()
    NSRect(origin: .zero, size: canvas.size).fill()

    for (index, frame) in frames.enumerated() {
        // Recolour to match the menu bar foreground.
        let tinted = StatusBarImage.recolor(
            frame,
            to: background == .black ? .white : .black
        )
        tinted.draw(in: NSRect(
            x: CGFloat(index) * (catWidth + spacing),
            y: 0,
            width: catWidth,
            height: menuBarHeight
        ))
    }
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

renderStrip(background: .white, path: "\(outputDirectory)/menu-light.png")
renderStrip(background: .black, path: "\(outputDirectory)/menu-dark.png")

// Also render the idle frames.
let idle = CatArt.buildIdleFrames()
let idleStrip = NSImage(size: NSSize(width: 44 * CGFloat(idle.count), height: menuBarHeight))
idleStrip.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: idleStrip.size).fill()
for (index, frame) in idle.enumerated() {
    StatusBarImage.recolor(frame, to: .black).draw(in: NSRect(
        x: CGFloat(index) * 44, y: 0, width: 44, height: menuBarHeight
    ))
}
idleStrip.unlockFocus()
if let tiff = idleStrip.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "\(outputDirectory)/menu-idle.png"))
}

print("菜单栏预览已生成: \(outputDirectory)")
print("素材来源: \(appBundle != nil ? "已构建的 App bundle" : "本地资源")")
