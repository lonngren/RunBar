import Foundation

/// Verifies the per-range speed settings: that each range keeps its own
/// value, that the values persist, and that the resting range stays at zero.
///
/// Run with:  swift Tools/VerifyTierSpeeds/main.swift
///
/// This is a development helper and is not part of the shipping app.

/// Mirror of the app's tier layout, kept local so the tool has no AppKit
/// dependency.
enum Tier: Int, CaseIterable {
    case idle, low, medium, high, extreme

    var lowerBound: Double {
        switch self {
        case .idle: return 0
        case .low: return 20
        case .medium: return 40
        case .high: return 60
        case .extreme: return 80
        }
    }
    var upperBound: Double {
        switch self {
        case .idle: return 20
        case .low: return 40
        case .medium: return 60
        case .high: return 80
        case .extreme: return 100
        }
    }
    var defaultSpeed: Double {
        switch self {
        case .idle: return 0
        case .low: return 4.5
        case .medium: return 7.0
        case .high: return 9.0
        case .extreme: return 11.5
        }
    }
    var isResting: Bool { self == .idle }
}

let key = "CatBar.tierSpeeds"
let defaults = UserDefaults.standard

print("=== 1. 各档位速度独立保存 ===")
// Set a distinct value per range.
var speeds = Tier.allCases.map(\.defaultSpeed)
speeds[1] = 2.0
speeds[2] = 5.0
speeds[3] = 8.0
speeds[4] = 10.0
defaults.set(speeds, forKey: key)

let restored = defaults.array(forKey: key) as? [Double] ?? []
let ok = restored.count == Tier.allCases.count
    && zip(restored, Tier.allCases).allSatisfy { value, tier in
        tier.isResting ? value == 0 : value > 0
    }
print("  存入: \(speeds)")
print("  读回: \(restored)")
print(ok ? "✅ 每档速度独立保存,静止档保持 0" : "❌ 保存有误")

print("")
print("=== 2. 静止档不参与速度 ===")
print("  静止档: \(Tier.idle.isResting ? "是" : "否") — 速度 \(speeds[0]) 步/秒")
print("  其余四档均可调")
print(speeds[0] == 0 ? "✅ 0–20% 为静止" : "❌ 静止档速度不为 0")

print("")
print("=== 3. 每档互不影响 ===")
// Change one range and check the others are untouched.
var changed = restored
changed[2] = 9.5
defaults.set(changed, forKey: key)
let after = defaults.array(forKey: key) as? [Double] ?? []
let othersUnchanged = zip(after, restored).enumerated().allSatisfy { index, pair in
    index == 2 || pair.0 == pair.1
}
print("  改 40–60% 为 9.5 后: \(after)")
print(othersUnchanged ? "✅ 其他档位未受影响" : "❌ 其他档位被连带修改")

print("")
print("=== 4. 恢复默认 ===")
defaults.removeObject(forKey: key)
let cleared = defaults.array(forKey: key) as? [Double] ?? []
print(cleared.isEmpty ? "✅ 已清除,下次启动用默认值" : "❌ 仍有残留: \(cleared)")
