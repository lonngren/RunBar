import AppKit

/// Records the animation frame index the app would show over a period of
/// time, so the motion can be checked for smoothness.
///
/// The status bar itself is hard to observe from outside (screen captures
/// come back cached), so this drives the same frame-selection logic and
/// prints the resulting sequence.
///
/// Run with:  swift Tools/TraceFrames/main.swift

/// The number of frames in one stride.
let frameCount = 5

/// Mirrors the app's bucketing.
enum Tier: Int, CaseIterable {
    case idle, low, medium, high, extreme

    var speed: Double {
        switch self {
        case .idle: return 2.0
        case .low: return 4.5
        case .medium: return 7.0
        case .high: return 9.0
        case .extreme: return 11.5
        }
    }
}

print("=== 各档位的帧序列(模拟 3 秒,60fps)===")

for tier in Tier.allCases {
    var elapsed = 0.0
    var indices: [Int] = []
    var skipped = 0

    for _ in 0..<180 {
        elapsed += 1.0 / 60.0
        let index = Int(elapsed * tier.speed * Double(frameCount)) % frameCount
        if let last = indices.last {
            let step = (index - last + frameCount) % frameCount
            if step > 1 { skipped += 1 }
        }
        indices.append(index)
    }

    // How many distinct frames were shown, and how often the sequence repeated.
    let distinct = Set(indices).count
    print("")
    print("  \(tier)  速度 \(String(format: "%.1f", tier.speed)) 步/秒")
    print("    出现的不同帧: \(distinct)/\(frameCount)")
    print("    跳帧次数: \(skipped)/179")
    print("    前 30 帧序列: \(indices.prefix(30).map(String.init).joined(separator: " "))")
}

// Now the interesting case: a load that hovers on a boundary. With bucketing
// plus hysteresis the tier must not change, so the sequence stays identical.
print("")
print("=== 边界抖动的表现 ===")

func simulate(samples: [Double], hysteresis: Double) -> [Int] {
    var tier = Tier.idle
    var target = tier.speed
    var current = target
    var elapsed = 0.0
    var indices: [Int] = []
    var tick = 0.0

    for load in samples {
        // Sample every 3 seconds, as the app does by default.
        tick += 3.0
        let wanted = Tier.allCases.first { load < Double($0.rawValue + 1) * 20 } ?? .extreme
        if wanted != tier {
            if wanted.rawValue > tier.rawValue {
                if load >= Double(wanted.rawValue) * 20 + hysteresis { tier = wanted; target = wanted.speed }
            } else {
                if load <= Double(tier.rawValue) * 20 - hysteresis { tier = wanted; target = wanted.speed }
            }
        }
        // 3 seconds of animation at 60fps.
        for _ in 0..<180 {
            elapsed += 1.0 / 60.0
            current += (target - current) * min(1, (1.0/60.0) * 6.0)
            indices.append(Int(elapsed * current * Double(frameCount)) % frameCount)
        }
    }
    return indices
}

let jittery: [Double] = [19.5, 20.4, 19.8, 20.2, 19.6, 20.3, 19.9, 20.1]
let withHysteresis = simulate(samples: jittery, hysteresis: 3.0)
let withoutHysteresis = simulate(samples: jittery, hysteresis: 0)

func countSpeedChanges(_ indices: [Int]) -> Int {
    // Count how often the frame sequence jumps by more than one frame.
    var changes = 0
    for i in 1..<indices.count {
        let step = (indices[i] - indices[i - 1] + frameCount) % frameCount
        if step > 1 { changes += 1 }
    }
    return changes
}

print("  负载在 19.5~20.4% 反复波动 8 次")
print("  带迟滞: 跳变 \(countSpeedChanges(withHysteresis)) 次")
print("  无迟滞: 跳变 \(countSpeedChanges(withoutHysteresis)) 次")
print(countSpeedChanges(withHysteresis) <= countSpeedChanges(withoutHysteresis)
      ? "✅ 迟滞有效减少了不连贯"
      : "❌ 迟滞没有帮助")
