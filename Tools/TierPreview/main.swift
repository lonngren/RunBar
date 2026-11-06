import AppKit
let R = "/Users/long/WorkBuddy/2026-11-04-14-11-13/CatBar/CatBar/Resources/CatFrames"
// 用 draw(in:) 直接绘制到画布,不做中间裁剪 —— 之前验证过的可靠路径
let tiers: [(String, Double)] = [("0-20%  慢走", 2.0), ("20-40%  小跑", 4.5), ("40-60%  快跑", 7.0), ("60-80%  疾跑", 9.0), ("80-100%  飞奔", 11.5)]

var frames: [NSImage] = []
for i in 0..<5 {
    guard let img = NSImage(contentsOfFile: R + "/cat_run_0" + String(i) + ".png") else { exit(1) }
    frames.append(img)
}

let cellW: CGFloat = 90
let cellH: CGFloat = 56
let labelW: CGFloat = 130
let cols = 10
let canvas = NSImage(size: NSSize(width: labelW + cellW * CGFloat(cols), height: cellH * CGFloat(tiers.count)))
canvas.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: canvas.size).fill()

for (row, tier) in tiers.enumerated() {
    let y = cellH * CGFloat(tiers.count - 1 - row)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
    (tier.0 as NSString).draw(at: CGPoint(x: 8, y: y + cellH / 2 - 6), withAttributes: attrs)
    let speedText = String(format: "%.1f 步/秒", tier.1)
    (speedText as NSString).draw(at: CGPoint(x: 8, y: y + cellH / 2 - 22),
        withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])

    var elapsed = 0.0
    for c in 0..<cols {
        elapsed += 1.0 / 60.0
        let idx = Int(elapsed * tier.1 * 5) % 5
        let src = frames[idx]
        let s = src.size
        let scale = min(cellW * 0.9 / s.width, cellH * 0.75 / s.height)
        let w = s.width * scale, h = s.height * scale
        src.draw(in: NSRect(x: labelW + CGFloat(c) * cellW + (cellW - w) / 2,
                            y: y + (cellH - h) / 2,
                            width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: 1)
    }
}
canvas.unlockFocus()
guard let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: "/tmp/catsearch/tiers2.png"))
print("ok")
