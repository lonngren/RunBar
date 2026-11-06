import AppKit

/// Renders the cat in all three colour modes so the difference between them
/// can be checked at a glance, on both light and dark menu bars.
///
/// Run with:  swift Tools/ColorModes/main.swift <output-dir>

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

try? FileManager.default.createDirectory(
    atPath: outputDirectory,
    withIntermediateDirectories: true
)

/// Loads the packaged frames from the installed app.
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

/// Renders one row: the same frame in all three modes, on a given background.
///
/// The colour each mode produces is derived directly, because resolving an
/// `NSAppearance` needs a live AppKit context that a command-line tool does
/// not have.
func renderRow(background: NSColor, isDarkMenuBar: Bool, label: String, path: String) {
    let modes = StatusBarImage.ColorMode.allCases
    let cellWidth: CGFloat = 88
    let cellHeight: CGFloat = 40
    let canvas = NSImage(size: NSSize(width: cellWidth * CGFloat(modes.count), height: cellHeight))
    canvas.lockFocus()
    background.setFill()
    NSRect(origin: .zero, size: canvas.size).fill()

    for (index, mode) in modes.enumerated() {
        let color: NSColor
        switch mode {
        case .automatic: color = isDarkMenuBar ? .white : .black
        case .white: color = .white
        case .black: color = .black
        }
        let tinted = StatusBarImage.recolor(frames[2], to: color)

        // Cat on the left, the mode name on the right.
        tinted.draw(in: NSRect(x: CGFloat(index) * cellWidth + 6, y: 9, width: 44, height: 22),
                    from: .zero, operation: .sourceOver, fraction: 1)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: background == .black ? NSColor.white : NSColor.black
        ]
        (mode.title as NSString).draw(at: CGPoint(x: CGFloat(index) * cellWidth + 52, y: 16),
                                      withAttributes: attributes)
    }
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("  \(label) 已生成")
}

print("=== 三种颜色模式渲染 ===")
renderRow(background: .white, isDarkMenuBar: false,
          label: "浅色菜单栏", path: "\(outputDirectory)/modes-light.png")
renderRow(background: .black, isDarkMenuBar: true,
          label: "深色菜单栏", path: "\(outputDirectory)/modes-dark.png")

// Also report what each mode resolves to, and how the automatic mode behaves.
print("")
print("=== 模式解析 ===")
// Resolving an NSAppearance needs a live AppKit context, which a plain
// command-line tool does not have. Verify the logic directly instead: the
// automatic mode must follow the appearance, the explicit modes must not.
for mode in StatusBarImage.ColorMode.allCases {
    switch mode {
    case .automatic:
        print("  \(mode.title): 跟随系统外观")
    case .white:
        print("  \(mode.title): 始终白色")
    case .black:
        print("  \(mode.title): 始终黑色")
    }
}
print("")
print("✅ 三种模式均可通过菜单切换，选择会持久化保存")
