import AppKit
import SwiftUI

/// The settings window.
///
/// It hosts a SwiftUI view inside an AppKit window, so the app can keep its
/// menu-bar architecture while offering a proper interface for the values that
/// need room to adjust — the running speed above all.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow!
    private let settings: Settings
    private let onChange: () -> Void

    /// Creates the controller.
    ///
    /// - Parameters:
    ///   - settings: the shared settings object the window edits.
    ///   - onChange: called whenever a setting changes, so the menu bar can
    ///     apply it immediately.
    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init()
    }

    /// Shows the window, bringing it to the front if it is already open.
    func show() {
        if window == nil {
            buildWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
    }

    private func buildWindow() {
        let hosting = NSHostingController(
            rootView: SettingsView(settings: settings, onChange: onChange)
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RunBar 设置"
        window.contentViewController = hosting
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        // `--at X Y` puts the window at a given spot, which makes it possible
        // to capture it on a screen where something else would cover it.
        if let index = CommandLine.arguments.firstIndex(of: "--at"),
           index + 2 < CommandLine.arguments.count,
           let x = Double(CommandLine.arguments[index + 1]),
           let y = Double(CommandLine.arguments[index + 2]) {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the window around so reopening it is instant, but let it go
        // when the app quits.
    }
}

/// The SwiftUI contents of the settings window.
struct SettingsView: View {

    @ObservedObject var settings: Settings
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $settings.selectedTab) {
                appearanceTab
                    .tabItem { Label("外观", systemImage: "paintbrush") }
                    .tag(0)
                animationTab
                    .tabItem { Label("动画", systemImage: "hare") }
                    .tag(1)
                behaviourTab
                    .tabItem { Label("行为", systemImage: "gearshape") }
                    .tag(2)
            }
            // The tabs scroll inside themselves; without this the form would
            // push the footer out of the window.
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            versionFooter
        }
        .frame(width: 460, height: 720)
    }

    /// The version and author, shown along the bottom of the window.
    private var versionFooter: some View {
        HStack {
            Text("RunBar \(AppInfo.version)")
                .monospacedDigit()
            Spacer()
            Text("作者：\(AppInfo.author)")
            Spacer()
            Text(AppInfo.buildDate)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("角色", selection: $settings.character) {
                    ForEach(Character.allCases) { character in
                        Text(character.title).tag(character)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.character) { _ in onChange() }
            } header: {
                Text("菜单栏图标")
            } footer: {
                Text("小猫是橘白走路动画，小狗是彩色手绘奔跑动画，都带深色描边，明暗两种菜单栏下都清晰可见。\nCPU 空闲时，小狗会坐下休息（摇尾巴、眨眼），小猫保持静止姿势。")
            }

            Section {
                Toggle("在菜单栏显示 CPU 百分比", isOn: $settings.showsPercentage)
                    .onChange(of: settings.showsPercentage) { _ in onChange() }
            } footer: {
                Text("显示后，图标旁边会出现实时占用数字，例如 42%。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Animation

    private var animationTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("整体倍率")
                        Spacer()
                        Text(String(format: "%.2f×", settings.speedMultiplier))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.speedMultiplier,
                        in: Settings.minimumSpeedMultiplier...Settings.maximumSpeedMultiplier,
                        step: 0.05
                    )
                    .onChange(of: settings.speedMultiplier) { _ in onChange() }

                    HStack {
                        Text("很慢")
                        Spacer()
                        Text("原速")
                        Spacer()
                        Text("很快")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("整体倍率")
            } footer: {
                Text("在下面各档位的基础上统一缩放。\n1.00× 是默认节奏；调到 0.10× 会慢到能看清小猫的每一个动作。")
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(LoadTier.allCases, id: \.self) { tier in
                        tierSpeedRow(tier)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("各档位速度")
            } footer: {
                Text("CPU 占用分成十档，每档可以单独设定步速，数值越大跑得越快。\n0–10% 是休息档，不参与调速：小猫保持静止姿势，小狗播放休息动画。\n上限 11.5 步/秒 —— 再快就超过屏幕刷新率，动画会丢帧。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One row: a load range with its own speed slider.
    private func tierSpeedRow(_ tier: LoadTier) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tier.rangeText)
                    .monospacedDigit()
                    .frame(width: 74, alignment: .leading)
                    .frame(width: 48, alignment: .leading)
                Spacer()
                if tier.isResting {
                    Text("休息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(format: "%.1f 步/秒", settings.baseSpeed(for: tier)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if tier.isResting {
                Text("CPU 占用低于 10% 时，小猫保持静止姿势，小狗播放休息动画。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Slider(
                    value: Binding(
                        get: { settings.baseSpeed(for: tier) },
                        set: { settings.setSpeed($0, for: tier) }
                    ),
                    in: Settings.minimumTierSpeed...Settings.maximumTierSpeed,
                    step: 0.5
                )
                .onChange(of: settings.tierSpeeds) { _ in onChange() }
            }
        }
    }

    // MARK: - Behaviour

    private var behaviourTab: some View {
        Form {
            Section {
                Picker("采样间隔", selection: $settings.samplingInterval) {
                    ForEach(Settings.samplingIntervals, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(Int(seconds)) 秒" : "\(Int(seconds / 60)) 分钟")
                            .tag(seconds)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.samplingInterval) { _ in onChange() }
            } header: {
                Text("CPU 采样")
            } footer: {
                Text("多久读一次 CPU。间隔越长越省资源，但负载突然升高时小猫要等下一个采样点才会跑起来。")
            }

            Section {
                Toggle("开机时自动启动", isOn: $settings.launchesAtLogin)
            } footer: {
                Text("通过 LaunchAgent 实现，登录后自动运行 RunBar。")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
