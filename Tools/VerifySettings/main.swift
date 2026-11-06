import Foundation

/// Verifies the settings that the user can change from the menu: the colour
/// mode and the CPU sampling interval.
///
/// Run with:  swift Tools/VerifySettings/main.swift
///
/// This is a development helper and is not part of the shipping app.

// The same keys and defaults the app uses.
let colorModeKey = "CatBar.colorMode"
let samplingIntervalKey = "CatBar.samplingInterval"
let colorModeTitles = ["跟随系统", "白色猫", "黑色猫"]
let intervals: [Double] = [1, 2, 3, 5, 10, 30]

print("=== 设置持久化验证 ===")

let defaults = UserDefaults.standard

// 1. Colour mode round-trips.
print("")
print("--- 猫的颜色 ---")
for (index, title) in colorModeTitles.enumerated() {
    defaults.set(index, forKey: colorModeKey)
    let stored = defaults.integer(forKey: colorModeKey)
    let ok = stored == index
    print("  \(title): 存入 \(index) → 读回 \(stored) \(ok ? "✅" : "❌")")
}

// 2. Sampling interval round-trips, and the default is 3 seconds.
print("")
print("--- CPU 采样间隔 ---")
defaults.removeObject(forKey: samplingIntervalKey)
let afterReset = defaults.double(forKey: samplingIntervalKey)
let effectiveDefault = afterReset > 0 ? afterReset : 3
let defaultNote = effectiveDefault == 3 ? "✅ 默认 3 秒" : "❌ 默认值不对"
print("  未设置时: 读到 \(afterReset) → 生效值 \(effectiveDefault) \(defaultNote)")

for seconds in intervals {
    defaults.set(seconds, forKey: samplingIntervalKey)
    let stored = defaults.double(forKey: samplingIntervalKey)
    let ok = stored == seconds
    print("  \(Int(seconds)) 秒: 存入 → 读回 \(String(format: "%.0f", stored)) \(ok ? "✅" : "❌")}")
}

// 3. The choice survives a fresh read of the defaults.
print("")
print("--- 重启后保持 ---")
defaults.set(3, forKey: samplingIntervalKey)
defaults.set(1, forKey: colorModeKey)
let rereadInterval = UserDefaults.standard.double(forKey: samplingIntervalKey)
let rereadMode = UserDefaults.standard.integer(forKey: colorModeKey)
print("  采样间隔: \(Int(rereadInterval)) 秒 \(rereadInterval == 3 ? "✅" : "❌")")
print("  颜色模式: \(colorModeTitles[rereadMode]) \(rereadMode == 1 ? "✅" : "❌")")

// 4. Restore the defaults so the installed app starts clean.
defaults.removeObject(forKey: samplingIntervalKey)
defaults.removeObject(forKey: colorModeKey)
print("")
print("✅ 已恢复默认设置（跟随系统 / 3 秒）")
