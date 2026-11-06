import AppKit
import Combine

/// The app's user settings, in one place.
///
/// Both the settings window and the right-click menu read and write this
/// object, so there is a single source of truth and no risk of the two
/// disagreeing. Values are persisted to `UserDefaults` as they change.
final class Settings: ObservableObject {

    /// The intervals the user can pick from, in seconds.
    static let samplingIntervals: [Double] = [1, 2, 3, 5, 10, 30]

    /// The upper bound of the speed multiplier.
    ///
    /// It is not arbitrary: the fastest range already sits at the display's
    /// refresh limit, so a much larger multiplier would push the top ranges
    /// past it — they would all clamp to the same speed and the slider would
    /// appear to stop working.
    static let maximumSpeedMultiplier: Double = 1.2

    /// The lower bound of the speed multiplier.
    ///
    /// The low end lets the animation crawl, which is handy when the
    /// difference between load levels needs to be obvious.
    static let minimumSpeedMultiplier: Double = 0.1

    /// The range a single load band can be set to, in strides per second.
    static let minimumTierSpeed: Double = 0
    static let maximumTierSpeed: Double = 11.5

    /// How often the CPU is sampled, in seconds.
    @Published var samplingInterval: Double {
        didSet { defaults.set(samplingInterval, forKey: Keys.samplingInterval) }
    }

    /// The speed of each load range, in strides per second.
    ///
    /// Stored per range so the user can tune them one by one — a busy machine
    /// might want a lazy cat at low load and a frantic one at high load.
    @Published var tierSpeeds: [Double] {
        didSet { persistTierSpeeds() }
    }

    /// Scales every range's speed. 1.0 leaves the per-range values alone.
    @Published var speedMultiplier: Double {
        didSet { defaults.set(speedMultiplier, forKey: Keys.speedMultiplier) }
    }

    /// Whether the CPU percentage is shown next to the cat.
    @Published var showsPercentage: Bool {
        didSet { defaults.set(showsPercentage, forKey: Keys.showPercentage) }
    }

    /// Whether the app starts when the user logs in.
    @Published var launchesAtLogin: Bool {
        didSet { AutoStart.setEnabled(launchesAtLogin) }
    }

    /// Which tab the settings window is showing.
    ///
    /// It lives here rather than in the view so the window can be opened on a
    /// chosen page — the `--tab` argument picks one.
    @Published var selectedTab: Int = AppInfo.initialTab

    /// The character shown in the menu bar.
    @Published var character: Character {
        didSet { defaults.set(character.rawValue, forKey: Keys.character) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let samplingInterval = "CatBar.samplingInterval"
        static let speedMultiplier = "CatBar.speedMultiplier"
        static let showPercentage = "CatBar.showPercentage"
        static let character = "CatBar.character"
        static let tierSpeeds = "CatBar.tierSpeeds"
    }

    init() {
        let storedInterval = defaults.double(forKey: Keys.samplingInterval)
        // A stored value of 0 means "never set" — fall back to the default.
        samplingInterval = storedInterval > 0 ? storedInterval : 3

        let storedMultiplier = defaults.double(forKey: Keys.speedMultiplier)
        speedMultiplier = storedMultiplier > 0 ? storedMultiplier : 1.0

        showsPercentage = defaults.bool(forKey: Keys.showPercentage)
        launchesAtLogin = AutoStart.isEnabled

        let storedCharacter = defaults.string(forKey: Keys.character)
        character = Character(rawValue: storedCharacter ?? "") ?? .cat

        // Restore the per-range speeds, filling in any range that was not
        // stored (or that was stored as zero before the resting tier existed).
        var speeds = LoadTier.allCases.map(\.defaultSpeed)
        if let stored = defaults.array(forKey: Keys.tierSpeeds) as? [Double],
           stored.count == speeds.count {
            for (index, value) in stored.enumerated() {
                // A stored zero for a running range would freeze it, so only
                // the resting tier is allowed to keep a zero.
                if value > 0 || LoadTier.allCases[index].isResting {
                    speeds[index] = value
                }
            }
        }
        tierSpeeds = speeds
    }

    /// The speed of a range before the multiplier is applied.
    func baseSpeed(for tier: LoadTier) -> Double {
        let index = tier.rawValue
        guard tierSpeeds.indices.contains(index) else { return tier.defaultSpeed }
        return tierSpeeds[index]
    }

    /// Sets the speed of a single range.
    func setSpeed(_ value: Double, for tier: LoadTier) {
        let index = tier.rawValue
        guard tierSpeeds.indices.contains(index) else { return }
        tierSpeeds[index] = value
    }

    /// The speed of a tier after the user's multiplier is applied.
    ///
    /// The multiplier scales the *ratio* between the ranges rather than the raw
    /// values. Scaling the ratio keeps all five ranges distinct: a plain
    /// multiplication would push the top ranges past the safe limit, where they
    /// would all clamp to the same speed and the slider would appear to stop
    /// working on the fast end.
    ///
    /// The character's own scale is applied on top, so the dog moves at the
    /// same visual pace as the cat despite having a longer cycle.
    func speed(for tier: LoadTier, character: Character = .cat) -> Double {
        let base = baseSpeed(for: tier)
        guard base > 0 else { return 0 }

        // Scale relative to the fastest range, so the multiplier nudges every
        // range without dragging the slow ones down with it.
        let reference = LoadTier.allCases
            .map { baseSpeed(for: $0) }
            .max() ?? 1
        let ratio = reference > 0 ? base / reference : 1

        let scaled = reference * ratio * speedMultiplier * character.speedScale
        let floor = 0.05 * character.speedScale
        return min(character.maximumSpeed, max(floor, scaled))
    }

    private func persistTierSpeeds() {
        defaults.set(tierSpeeds, forKey: Keys.tierSpeeds)
    }
}
