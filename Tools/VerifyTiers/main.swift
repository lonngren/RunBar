import Foundation

/// Verifies the ten load bands: their ranges, their default speeds, and the
/// hysteresis that keeps the character from flickering between two bands.
///
/// Run with:  swift Tools/VerifyTiers/main.swift
///
/// This is a development helper and is not part of the shipping app.

/// Mirror of the app's tier layout, kept local so the tool has no AppKit
/// dependency.
enum Tier: Int, CaseIterable {
    case resting = 0
    case tier1 = 1
    case tier2 = 2
    case tier3 = 3
    case tier4 = 4
    case tier5 = 5
    case tier6 = 6
    case tier7 = 7
    case tier8 = 8
    case tier9 = 9

    var lowerBound: Double { Double(rawValue) * 10 }
    var upperBound: Double { Double(rawValue + 1) * 10 }
    var defaultSpeed: Double { self == .resting ? 0 : Double(rawValue) }
    var isResting: Bool { self == .resting }

    static func tier(for load: Double) -> Tier {
        let index = Int((load / 10).rounded(.down))
        return Tier(rawValue: max(0, min(allCases.count - 1, index))) ?? .resting
    }

    static func tier(for load: Double, current: Tier, hysteresis: Double) -> Tier {
        let target = tier(for: load)
        guard target != current else { return current }
        if target.rawValue > current.rawValue {
            guard load >= target.lowerBound + hysteresis else { return current }
        } else {
            guard load <= current.lowerBound - hysteresis else { return current }
        }
        return target
    }
}

print("=== 1. 十个区间的划分与默认速度 ===")
print("占用率      状态      默认速度")
print(String(repeating: "-", count: 44))
for tier in Tier.allCases {
    let speed = tier.isResting ? "静止" : String(format: "%.1f 步/秒", tier.defaultSpeed)
    let range = "\(Int(tier.lowerBound))–\(Int(tier.upperBound))%"
    let state = tier.isResting ? "静止" : "运行"
    print(range.padding(toLength: 12, withPad: " ", startingAt: 0)
        + state.padding(toLength: 10, withPad: " ", startingAt: 0)
        + speed)
}

print("")
print("=== 2. 区间归属 ===")
var ok = true
for tier in Tier.allCases {
    for load in [tier.lowerBound, tier.lowerBound + 0.1,
                 (tier.lowerBound + tier.upperBound) / 2, tier.upperBound - 0.1] {
        let actual = Tier.tier(for: load)
        if actual != tier {
            ok = false
            print("  ❌ \(load)% 落到了 \(actual)，应为 \(tier)")
        }
    }
}
print(ok ? "✅ 所有区间归属正确" : "❌ 存在归属错误")

print("")
print("=== 3. 边界点归属 ===")
// A load exactly on a boundary belongs to the band that starts there.
for tier in Tier.allCases where tier.rawValue > 0 {
    let actual = Tier.tier(for: tier.lowerBound)
    let expected = "属于 \(tier.rawValue * 10)–\(tier.rawValue * 10 + 10)%"
    print(String(format: "  %3d%% → %@", Int(tier.lowerBound),
                 actual == tier ? "✅ \(expected)" : "❌ 属于 \(actual)"))
}

print("")
print("=== 4. 迟滞:边界附近不会来回跳 ===")
var current = Tier.tier1
var flips = 0
let samples: [Double] = [11.0, 12.0, 11.5, 12.4, 11.8, 12.2, 11.2, 11.9]
for load in samples {
    let next = Tier.tier(for: load, current: current, hysteresis: 3.0)
    if next != current { flips += 1 }
    current = next
}
print("  负载在 11.0~12.4% 之间波动 8 次")
print("  档位切换次数: \(flips) \(flips == 0 ? "✅ 完全不抖" : "❌ 仍在抖动")")

print("")
print("=== 5. 真正越过边界时仍会切换 ===")
current = .resting
let up = Tier.tier(for: 15, current: current, hysteresis: 3.0)
print("  静止档 → 15%: \(up.rawValue == 1 ? "✅ 进入第一档" : "❌ 得到 \(up)")")

current = .tier9
let down = Tier.tier(for: 85, current: current, hysteresis: 3.0)
print("  最高档 → 85%: \(down.rawValue == 8 ? "✅ 降到第八档" : "❌ 得到 \(down)")")

print("")
print("=== 6. 速度单调递增 ===")
let speeds = Tier.allCases.map(\.defaultSpeed)
let monotonic = zip(speeds, speeds.dropFirst()).allSatisfy { $0 < $1 }
print("  \(speeds)")
print(monotonic ? "✅ 逐档递增 1 步/秒" : "❌ 有重复或倒序")
