import AppKit

/// Verifies the animation pipeline end to end: the CPU sampler, the speed
/// mapping, frame coverage at every speed, and the theme recolouring.
///
/// Run with:  swift Tools/Verify/main.swift
///
/// This is a development helper and is not part of the shipping app.

let sampler = SystemCPUSampler()

// The fastest stride, in steps per second. 12 steps/s over 5 frames is 60
// frames/s, which matches the display refresh rate.
let maximumStrideRate = 12.0
let frameCount = 5

func strideRate(for loadPercent: Double) -> Double {
    min(maximumStrideRate, max(1.0, (loadPercent / 5.0) * 1.0))
}

// MARK: - 1. The sampler

print("=== 1. CPU 采样器 ===")
var readings: [Double] = []
for _ in 0..<8 {
    readings.append(sampler.sample())
    Thread.sleep(forTimeInterval: 0.25)
}
let average = readings.reduce(0, +) / Double(readings.count)
print("采样值: \(readings.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
print("平均: \(String(format: "%.1f", average * 100))%")
print(readings.allSatisfy { $0 >= 0 && $0 <= 1 } ? "✅ 取值范围合法" : "❌ 取值越界")

// MARK: - 2. Speed mapping

print("")
print("=== 2. 速度映射 ===")
print("CPU 占用    步频          视觉帧率")
print(String(repeating: "-", count: 42))
for loadPercent in [0.0, 2.0, 10.0, 25.0, 50.0, 75.0, 100.0] {
    let speed = strideRate(for: loadPercent)
    let loadText = String(format: "%.0f%%", loadPercent)
    let speedText = String(format: "%.1f 步/秒", speed)
    let fpsText = String(format: "%.0f fps", speed * Double(frameCount))
    print(loadText.padding(toLength: 13, withPad: " ", startingAt: 0)
        + speedText.padding(toLength: 15, withPad: " ", startingAt: 0)
        + fpsText)
}

// MARK: - 3. Frame coverage

print("")
print("=== 3. 帧覆盖(每档速度都必须走遍全部帧) ===")
var allCovered = true
for loadPercent in [2.0, 5.0, 10.0, 25.0, 50.0, 75.0, 100.0] {
    var seen = Set<Int>()
    let speed = strideRate(for: loadPercent)
    var elapsed = 0.0
    for _ in 0..<600 {
        elapsed += 1.0 / 60.0
        seen.insert(Int(elapsed * speed * Double(frameCount)) % frameCount)
    }
    let covered = seen.count == frameCount
    if !covered { allCovered = false }
    print("CPU \(Int(loadPercent))% → \(seen.sorted())  (\(seen.count)/\(frameCount)) \(covered ? "✅" : "❌")")
}
print(allCovered ? "✅ 所有速度下所有帧都能显示" : "❌ 存在帧跳过")

// MARK: - 4. The artwork

print("")
print("=== 4. 素材完整性 ===")

/// Reads the packaged frames from the built app.
func loadPackagedFrames() -> [NSImage] {
    let candidates = [
        URL(fileURLWithPath: "./build/Build/Products/Release/CatBar.app"),
        URL(fileURLWithPath: "./CatBarApp/CatBar.app"),
        URL(fileURLWithPath: "../CatBarApp/CatBar.app")
    ]
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
          let bundle = Bundle(url: url) else { return [] }

    return (0..<frameCount).compactMap { index in
        let name = "cat_run_\(String(format: "%02d", index))"
        guard let resourceURL = bundle.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: resourceURL)
    }
}

let frames = loadPackagedFrames()
if frames.isEmpty {
    print("⚠️  未找到已构建的 App,跳过素材检查(请先 build)")
} else {
    print("已加载 \(frames.count) 帧")
    var distinct = Set<String>()
    for (index, frame) in frames.enumerated() {
        guard let tiff = frame.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }
        let hash = png.reduce(into: UInt64(1469598103934665603)) { acc, byte in
            acc = (acc ^ UInt64(byte)) &* 1099511628211
        }
        distinct.insert(String(hash))
        print("  帧 \(index): \(rep.pixelsWide)x\(rep.pixelsHigh) px")
    }
    print(distinct.count == frames.count
          ? "✅ \(frames.count) 帧全部不同,动画有真实帧间变化"
          : "❌ 存在重复帧")

    // The artwork must be monochrome so it can be recoloured for the theme.
    if let first = frames.first,
       let tiff = first.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff) {
        var isMonochrome = true
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                    if abs(r - g) > 0.08 || abs(g - b) > 0.08 { isMonochrome = false }
                }
            }
        }
        print(isMonochrome ? "✅ 素材为单色,可按主题重着色" : "⚠️  素材含彩色,重着色可能不纯")
    }

    // Theme recolouring.
    func averageLuma(_ image: NSImage) -> Double {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return -1 }
        var total = 0.0
        var count = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    total += color.brightnessComponent
                    count += 1
                }
            }
        }
        return count > 0 ? total / Double(count) : -1
    }
    if let first = frames.first {
        let blackLuma = averageLuma(StatusBarImage.recolor(first, to: .black))
        let whiteLuma = averageLuma(StatusBarImage.recolor(first, to: .white))
        print("  黑色重着色亮度 \(String(format: "%.4f", blackLuma)),白色 \(String(format: "%.4f", whiteLuma))")
        print(blackLuma < whiteLuma ? "✅ 明暗两种主题都能正确适配" : "❌ 重着色未生效")
    }
}

// MARK: - 5. End to end

print("")
print("=== 5.端到端(真实采样 → 速度 → 帧) ===")
var elapsed = 0.0
for step in 0..<6 {
    let reading = sampler.sample()
    let loadPercent = reading * 100
    let speed = strideRate(for: loadPercent)
    elapsed += 0.25
    let index = Int(elapsed * speed * Double(frameCount)) % frameCount
    print("  第\(step + 1)次: CPU \(String(format: "%.1f", loadPercent))% → speed \(String(format: "%.1f", speed)) → 帧 \(index)")
}
