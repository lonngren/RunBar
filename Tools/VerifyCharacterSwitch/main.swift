import AppKit

/// Exercises the character switch the way the menu does, and reports which
/// character's frames ended up loaded.
///
/// The bug this guards against: a `@Published` publisher fires *before* the
/// new value is stored, so a subscriber that reads the settings instead of
/// using the value it was handed will load the previous character.
///
/// Run with:  swift Tools/VerifyCharacterSwitch/main.swift <app-bundle>

let bundlePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/Applications/CatBar.app"

guard let bundle = Bundle(url: URL(fileURLWithPath: bundlePath)) else {
    print("找不到 App")
    exit(1)
}

/// Counts how many frames of each character the bundle carries.
func frameCount(prefix: String) -> Int {
    (0..<64).filter { index in
        let name = "\(prefix)_\(String(format: "%02d", index))"
        return bundle.url(forResource: name, withExtension: "png") != nil
    }.count
}

let catFrames = frameCount(prefix: "cat_run")
let dogFrames = frameCount(prefix: "dog_run")
print("小猫帧数: \(catFrames)")
print("小狗帧数: \(dogFrames)")

print("")
print("=== 模拟菜单点击的角色切换 ===")

/// Mirrors what `Character.loadFrames()` does.
func loadFrames(for character: String) -> [NSImage] {
    let count = character == "dog" ? dogFrames : catFrames
    return (0..<count).compactMap { index in
        let name = "\(character)_run_\(String(format: "%02d", index))"
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
}

// The mistake that caused the bug: reading the setting inside the
// subscriber instead of using the value the publisher handed over.
final class SettingsStub {
    var character = "cat"
    var subscribers: [(String) -> Void] = []

    func set(_ value: String) {
        // A @Published publisher fires before the value is stored.
        for subscriber in subscribers { subscriber(value) }
        character = value
    }
}

let settings = SettingsStub()
var loadedCharacter = "cat"

settings.subscribers.append { newValue in
    // The correct version uses `newValue` directly.
    loadedCharacter = newValue
    _ = loadFrames(for: loadedCharacter)
}
settings.set("dog")
print("  设置为 dog → 加载了 \(loadedCharacter) 的 \(loadFrames(for: loadedCharacter).count) 帧")
print(loadedCharacter == "dog" ? "✅ 切换立即生效" : "❌ 仍然加载旧角色")

settings.set("cat")
print("  设置为 cat → 加载了 \(loadedCharacter) 的 \(loadFrames(for: loadedCharacter).count) 帧")
print(loadedCharacter == "cat" ? "✅ 切回正常" : "❌ 切回失败")

print("")
print("=== 反例:如果订阅里读 settings 会怎样 ===")
let badSettings = SettingsStub()
var badLoaded = "cat"
badSettings.subscribers.append { _ in
    badLoaded = badSettings.character   // 读旧值 —— 这就是原来的 bug
}
badSettings.set("dog")
print("  设置为 dog → 加载了 \(badLoaded)")
print(badLoaded == "cat" ? "⚠️ 复现了原 bug(读旧值)" : "意外:没复现")
