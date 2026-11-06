import AppKit
import Combine

/// The app's entry point.
///
/// `@main` on an `NSApplicationDelegate` does not start the run loop on its
/// own — the delegate protocol does not provide a `main()` — so the
/// application is created and run explicitly here.
@main
enum Main {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    /// The "角色" submenu, kept for refreshing its checkmarks.
    private var characterMenu: NSMenu!
    /// The "CPU 采样间隔" submenu, kept for refreshing its checkmarks.
    private var intervalMenu: NSMenu!

    private let sampler = SystemCPUSampler()

    /// The character's running frames, as bundled in the app.
    private var runFrames: [NSImage] = []
    private var idleFrames: [NSImage] = []
    /// Frames shown in the status bar. For coloured artwork these are the
    /// originals; a monochrome character would be tinted here.
    private var tintedRunFrames: [NSImage] = []
    private var tintedIdleFrames: [NSImage] = []

    /// Number of frames in the active character's animation cycle.
    private var frameCount: Int = Character.cat.frameCount

    /// The load bucket the cat is currently in.
    private var tier: LoadTier = .resting
    /// The speed the cat is running at right now.
    private var currentSpeed: Double = LoadTier.resting.defaultSpeed
    /// The speed of the current bucket; `currentSpeed` eases towards it.
    private var targetSpeed: Double = LoadTier.resting.defaultSpeed
    /// The multiplier the user set, applied on top of the tier's speed.
    private var appliedMultiplier: Double = 1.0
    /// Raw reading, used for the numeric readout.
    private var rawLoad: Double = 0
    /// How far through the current stride we are.
    private var stridePhase: Double = 0
    /// Total time the app has been running, used to derive the frame index.
    private var elapsed: Double = 0
    private var lastTick = Date()
    private var sampleAccumulator: Double = 0

    private var isIdle = true
    private var lastPercentageText = ""
    /// The frame the animation currently wants to show.
    private var currentFrameIndex = 0
    /// The frame that was last drawn into the status item.
    ///
    /// This has to be separate from `currentFrameIndex`: comparing the frame
    /// to draw against the frame that was drawn is what tells the app that
    /// the animation moved on.
    private var lastDrawnFrameIndex = -1

    /// Whether the frames have already been tinted, and for which appearance.
    private var tintedIsDark: Bool?
    /// All user settings, shared with the settings window.
    private let settings = Settings()
    private var settingsWindow: SettingsWindowController?

    /// The character currently shown in the menu bar.
    private var character: Character = .cat
    /// Holds the Combine subscriptions that react to setting changes.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Order matters: the status item must exist before anything tries to
        // update its image, and the frames must be loaded and tinted before
        // the item can be given one.
        buildStatusItem()
        loadCharacterFrames(for: settings.character)
        buildMenu()

        log("RunBar 已启动：状态栏项 \(statusItem.button == nil ? "创建失败" : "创建成功")，"
            + "运行帧 \(runFrames.count)，静止帧 \(idleFrames.count)，"
            + "已着色 \(tintedRunFrames.count) 帧，"
            + "采样间隔 \(String(format: "%.0f", settings.samplingInterval)) 秒，"

            + "速度倍率 \(String(format: "%.2f", settings.speedMultiplier))×")
        if let button = statusItem.button {
            log("按钮 image=\(button.image?.size ?? .zero)，"
                + "状态栏项长度=\(statusItem.length)")
        }
        // When the user changes the speed multiplier, the current tier's speed
        // has to be recalculated — the cat should pick up the new pace
        // immediately rather than at the next sample.
        // Switching the character reloads the frames and restarts the
        // animation with the new cycle length.
        settings.$character
            .dropFirst()
            .sink { [weak self] newCharacter in
                guard let self else { return }
                self.loadCharacterFrames(for: newCharacter)
                // The new character has its own frame rate, so the speed has
                // to be recalculated — otherwise it keeps the old character's
                // pace.
                self.targetSpeed = self.settings.speed(for: self.tier,
                                                       character: self.character)
                self.updateStatusImage(force: true)
                self.refreshMenu()
                self.log("角色切换 → \(self.settings.character.title)")
            }
            .store(in: &cancellables)

        // Changing any range's speed affects the current one immediately.
        settings.$tierSpeeds
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.targetSpeed = self.settings.speed(for: self.tier,
                                                       character: self.character)
                self.updateStatusImage(force: true)
            }
            .store(in: &cancellables)

        settings.$speedMultiplier
            .dropFirst()
            .sink { [weak self] multiplier in
                guard let self else { return }
                self.targetSpeed = self.settings.speed(for: self.tier, character: self.character)
                self.log(String(format: "速度倍率 → %.2f×（当前档位 %.1f 步/秒）",
                                multiplier, self.targetSpeed))
            }
            .store(in: &cancellables)

        // A launch argument opens the settings window straight away, which
        // makes it possible to check the layout without going through the
        // menu bar.
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }

        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)

        // Re-tint the frames whenever the system appearance changes — but only
        // in automatic mode, so an explicit choice is never overridden.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshAppearance()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing to tear down — the run loop ends with the process.
    }

    /// Writes a line to stderr, which shows up in the console when the app is
    /// launched from a terminal. Used for diagnosing startup problems.
    private func log(_ message: String) {
        let line = "[RunBar] " + message + "\n"
        FileHandle.standardError.write(Data(line.utf8))
        // Also write to a file, so the log survives when the app is launched
        // by the system rather than from a terminal.
        let url = URL(fileURLWithPath: "/tmp/catpreview/runtime.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    // MARK: - Character

    /// Loads the frames for the active character.
    ///
    /// Both characters are coloured drawings, so their bundled frames are
    /// shown as-is.
    ///
    /// - Parameter character: the character to load. It is passed in rather
    ///   than read from the settings, because a `@Published` publisher fires
    ///   before the new value is stored — reading the settings inside the
    ///   subscriber would still see the old character.
    private func loadCharacterFrames(for character: Character) {
        self.character = character

        runFrames = character.loadFrames()
        idleFrames = IdleArt.buildFrames(for: character)

        // `speedScale` normalises the stride rate to this character's cycle
        // length, so both characters keep the same visual pace.
        frameCount = character.frameCount

        // Force the tint to be recomputed for the new character's frames.
        tintedIsDark = nil
        currentFrameIndex = 0
        lastDrawnFrameIndex = -1
        refreshAppearance(force: true)
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusButtonClicked)
            // Handle both mouse buttons so right-click can open the menu.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.toolTip = "RunBar · 点击显示/隐藏 CPU 百分比"
        }
        // The image is set once the frames have been tinted — see
        // `refreshAppearance`, which runs straight after this.
    }

    /// Prepares the frames for the current appearance.
    ///
    /// Runs on launch and whenever the system appearance changes. Coloured
    /// artwork is used unchanged; a monochrome character would be tinted here.
    private func refreshAppearance(force: Bool = false) {
        let isDark = false

        guard force || tintedIsDark != isDark else { return }
        tintedIsDark = isDark

        // Both characters are coloured drawings whose outlines make them
        // recognisable at 22 points, so neither is flattened into a silhouette.
        if character.supportsRecolouring {
            let color = StatusBarImage.silhouetteColor
            tintedRunFrames = runFrames.map { StatusBarImage.recolor($0, to: color) }
            tintedIdleFrames = idleFrames.map { StatusBarImage.recolor($0, to: color) }
        } else {
            tintedRunFrames = runFrames
            tintedIdleFrames = idleFrames
        }

        currentFrameIndex = 0
        lastDrawnFrameIndex = -1
        updateStatusImage(force: true)
    }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()

        let title = NSMenuItem(title: "RunBar", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let stats = NSMenuItem(title: "CPU 采样中…", action: nil, keyEquivalent: "")
        stats.isEnabled = false
        stats.tag = 1001
        menu.addItem(stats)

        let mode = NSMenuItem(title: "状态：—", action: nil, keyEquivalent: "")
        mode.isEnabled = false
        mode.tag = 1002
        menu.addItem(mode)

        // A read-only summary of the speed buckets, so the mapping between
        // load ranges and the cat's speed is visible.
        let tiers = NSMenuItem(title: "速度档位", action: nil, keyEquivalent: "")
        tiers.isEnabled = false
        menu.addItem(tiers)
        let tierMenu = NSMenu()
        for tier in LoadTier.allCases {
            // Show the speed the user set for this band. The internal stride
            // rate is scaled to the character's cycle length (see
            // `Character.speedScale`), so showing it here would disagree with
            // the sliders in the settings window.
            let speed = settings.baseSpeed(for: tier) * settings.speedMultiplier
            let label = tier.isResting
                ? "\(tier.rangeText) → 休息"
                : "\(tier.rangeText) → \(String(format: "%.1f", speed)) 步/秒"
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            tierMenu.addItem(item)
        }
        tiers.submenu = tierMenu

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "在菜单栏显示 CPU 百分比", action: #selector(togglePercentageAction), keyEquivalent: "")
        toggle.target = self
        toggle.tag = 1003
        menu.addItem(toggle)

        // Character submenu — cat or dog.
        let characterItem = NSMenuItem(title: "角色", action: nil, keyEquivalent: "")
        characterMenu = NSMenu()
        for (index, character) in Character.allCases.enumerated() {
            let option = NSMenuItem(
                title: character.title,
                action: #selector(selectCharacter(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = index
            option.state = (character == settings.character) ? .on : .off
            characterMenu.addItem(option)
        }
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)

        // Sampling interval submenu.
        let intervalItem = NSMenuItem(title: "CPU 采样间隔", action: nil, keyEquivalent: "")
        intervalMenu = NSMenu()
        for (index, seconds) in Settings.samplingIntervals.enumerated() {
            let option = NSMenuItem(
                title: seconds < 60 ? "\(Int(seconds)) 秒" : "\(Int(seconds / 60)) 分钟",
                action: #selector(selectSamplingInterval(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = index
            option.state = (seconds == settings.samplingInterval) ? .on : .off
            intervalMenu.addItem(option)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let autostart = NSMenuItem(title: "开机时自动启动", action: #selector(toggleAutostartAction), keyEquivalent: "")
        autostart.target = self
        autostart.tag = 1004
        menu.addItem(autostart)

        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let activity = NSMenuItem(title: "打开活动监视器", action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 RunBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func refreshMenu() {
        let percent = Int((rawLoad * 100).rounded())
        menu.item(withTag: 1001)?.title = "CPU 占用：\(percent)%"
        menu.item(withTag: 1002)?.title = "状态：\(statusDescription)"
        menu.item(withTag: 1003)?.state = settings.showsPercentage ? .on : .off
        menu.item(withTag: 1004)?.state = settings.launchesAtLogin ? .on : .off

        // Keep the submenus in sync with the current choices.
        for option in characterMenu.items {
            guard let character = Character.allCases[safe: option.tag] else { continue }
            option.state = (character == settings.character) ? .on : .off
        }
        for option in intervalMenu.items {
            guard Settings.samplingIntervals.indices.contains(option.tag) else { continue }
            option.state = (Settings.samplingIntervals[option.tag] == settings.samplingInterval) ? .on : .off
        }
    }

    private var statusDescription: String {
        if isIdle { return "休息 💤" }
        // `currentSpeed` is scaled for the artwork; divide it back so the
        // readout matches the numbers shown in the settings window.
        let shown = currentSpeed / max(0.0001, character.speedScale)
        return "\(tier.rangeText)（\(String(format: "%.1f", shown)) 步/秒）"
    }

    // MARK: - Actions

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            refreshMenu()
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        } else {
            togglePercentage()
        }
    }

    @objc private func togglePercentageAction(_ sender: NSMenuItem) {
        togglePercentage()
    }

    private func togglePercentage() {
        settings.showsPercentage = !settings.showsPercentage
        updateStatusImage(force: true)
        refreshMenu()
    }

    @objc private func toggleAutostartAction(_ sender: NSMenuItem) {
        settings.launchesAtLogin.toggle()
        refreshMenu()
    }

    /// Switches between the cat and the dog.
    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let character = Character.allCases[safe: sender.tag] else { return }
        // The subscription above loads the frames and refreshes the menu.
        settings.character = character
    }

    /// Changes how often the CPU is sampled.
    @objc private func selectSamplingInterval(_ sender: NSMenuItem) {
        guard Settings.samplingIntervals.indices.contains(sender.tag) else { return }
        settings.samplingInterval = Settings.samplingIntervals[sender.tag]
        // Apply the new interval immediately rather than waiting for the
        // current one to elapse.
        sampleAccumulator = settings.samplingInterval
        refreshMenu()
    }

    /// Opens the settings window.
    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] in
                self?.applySettings()
            }
        }
        settingsWindow?.show()
    }

    /// Applies the current settings to the menu bar.
    func applySettings() {
        refreshAppearance(force: true)
        refreshMenu()
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Animation loop

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        sampleAccumulator += delta

        if sampleAccumulator >= settings.samplingInterval {
            sampleAccumulator = 0
            let reading = sampler.sample()
            rawLoad = reading

            // Move to a new bucket only when the load clearly crosses the
            // threshold, so a load hovering on a boundary does not flip the
            // cat's speed back and forth.
            let updated = LoadTier.tier(
                for: reading * 100,
                current: tier,
                hysteresis: Self.tierHysteresis
            )
            if updated != tier {
                tier = updated
                targetSpeed = settings.speed(for: updated, character: character)
                log(String(format: "档位切换 → %@（%.1f 步/秒）",
                          updated.rangeText, targetSpeed))
            }
        }

        // Ease towards the bucket's speed. Within a bucket this settles at a
        // constant rate, so the animation is completely steady; the easing
        // only shows when the bucket changes.
        currentSpeed += (targetSpeed - currentSpeed) * min(1, delta * 6.0)

        advanceStride(by: delta)
        updateStatusImage(force: false)
    }

    /// Advances the animation using the current bucket's speed.
    ///
    /// The frame index comes from *absolute* elapsed time rather than an
    /// accumulated phase, so the motion does not drift or judder.
    private func advanceStride(by delta: Double) {
        // The lowest range is the resting one: the machine is not busy enough
        // to be worth running about.
        isIdle = tier.isResting

        elapsed += delta

        if isIdle {
            // The resting bucket has no stride rate, so the resting artwork
            // plays at its own frame rate: a slow breathing cycle for the cat,
            // and the supplied sitting-dog animation for the dog.
            let rate = character.restingFrameRate
            currentFrameIndex = Int(elapsed * rate) % max(1, idleFrames.count)
            return
        }

        let phase = elapsed * currentSpeed
        currentFrameIndex = Int(phase * Double(frameCount)) % max(1, frameCount)
    }

    /// How far past a threshold the load must move before the bucket changes.
    private static let tierHysteresis: Double = 3.0

    private func updateStatusImage(force: Bool) {
        guard let button = statusItem?.button else { return }

        let frames = isIdle ? tintedIdleFrames : tintedRunFrames
        guard !frames.isEmpty else { return }

        // The frame to draw, clamped into the available range.
        let index = max(0, min(currentFrameIndex, frames.count - 1))
        let percentageText = settings.showsPercentage ? String(format: "%.0f%%", rawLoad * 100) : nil

        // Redraw when the animation moved on, when the readout changed, or
        // when something explicitly asked for a refresh.
        let needsUpdate = force
            || index != lastDrawnFrameIndex
            || percentageText != lastPercentageText

        guard needsUpdate else { return }

        lastDrawnFrameIndex = index
        lastPercentageText = percentageText ?? ""
        let image = StatusBarImage.compose(
            cat: frames[index],
            text: percentageText,
            appearance: NSApp.effectiveAppearance
        )
        button.image = image
    }
}

extension Array {
    /// Returns the element at `index`, or nil when the index is out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
