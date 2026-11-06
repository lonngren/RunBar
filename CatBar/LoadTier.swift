import Foundation

/// Maps CPU load onto a small set of speeds.
///
/// A continuous mapping makes the cat's speed change on every sample, which
/// reads as a twitch. Bucketing the load into ten ranges and giving each one
/// its own speed means the animation is perfectly steady between samples and
/// only changes when the load crosses a threshold.
///
/// Each bucket's speed can be set individually by the user; `defaultSpeed`
/// is only the starting point.
///
/// At a threshold the load often hovers right on the boundary, which would make
/// the cat flip between two speeds on consecutive samples. A hysteresis band
/// keeps it in the current bucket until the load moves clearly past the edge.
enum LoadTier: Int, CaseIterable {

    /// The fastest the character may run, in strides per second.
    ///
    /// Over the 5 animation frames this is 57.5 frames/s, just under the
    /// display's refresh rate. An exact multiple of the frame rate would
    /// advance a whole frame on every tick, which occasionally skips a frame
    /// and reads as a stutter.
    static let maximumSafeSpeed: Double = 11.5

    /// The load ranges, ten percent each.
    ///
    /// The raw value is the index of the range, so the first one covers
    /// 0–10%, the second 10–20%, and so on. The lowest range is the resting
    /// one; the rest speed up by one stride per second each.
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

    /// Lower edge of the range, in percent.
    var lowerBound: Double {
        Double(rawValue) * 10
    }

    /// Upper edge of the range, in percent.
    var upperBound: Double {
        Double(rawValue + 1) * 10
    }

    /// The range this bucket covers, as shown in the settings.
    var rangeText: String {
        "\(Int(lowerBound))–\(Int(upperBound))%"
    }

    /// The starting speed for this range, in strides per second.
    ///
    /// The user can override each range individually; this is only what a
    /// fresh install starts with. The resting range is still, and every
    /// running range is one step per second faster than the one below it.
    var defaultSpeed: Double {
        isResting ? 0 : Double(rawValue)
    }

    /// Whether this range shows the resting artwork instead of running.
    ///
    /// The lowest bucket is idle: the machine is not busy enough to be worth
    /// running about, so the character shows its resting pose — an animated
    /// one for the dog, a still one for the cat.
    var isResting: Bool {
        self == .resting
    }

    /// The bucket a load percentage falls into, without hysteresis.
    static func tier(for loadPercent: Double) -> LoadTier {
        let index = Int((loadPercent / 10).rounded(.down))
        let clamped = max(0, min(allCases.count - 1, index))
        return LoadTier(rawValue: clamped) ?? .resting
    }

    /// The bucket a load percentage belongs to, taking the current bucket and
    /// the hysteresis band into account.
    static func tier(for loadPercent: Double, current: LoadTier, hysteresis: Double) -> LoadTier {
        let target = tier(for: loadPercent)
        guard target != current else { return current }

        if target.rawValue > current.rawValue {
            // Moving up: the load has to clear the new bucket's floor.
            guard loadPercent >= target.lowerBound + hysteresis else { return current }
        } else {
            // Moving down: the load has to fall below the old bucket's floor.
            guard loadPercent <= current.lowerBound - hysteresis else { return current }
        }
        return target
    }
}
