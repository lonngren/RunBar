import AppKit

/// The character shown in the menu bar.
///
/// Each character knows how many animation frames it has and how to load
/// them, so the rest of the app does not have to care which one is active.
enum Character: String, CaseIterable, Identifiable {

    /// The orange-and-white walking cat, chroma-keyed out of a green-screen
    /// video supplied by the user.
    case cat

    /// The bouncing dog, drawn by hand and supplied by the user.
    case dog

    var id: String { rawValue }

    /// The name shown in the settings.
    var title: String {
        switch self {
        case .cat: return "小猫"
        case .dog: return "小狗"
        }
    }

    /// Number of frames in one animation cycle.
    ///
    /// Both characters ship 32-frame cycles: the cat's walk is a closed loop
    /// chroma-keyed from the user's green-screen video, and the dog's cycle
    /// was interpolated up to thirty-two frames from the sixteen in its source.
    var frameCount: Int { 32 }

    /// The loop length that one "stride" was originally defined against.
    ///
    /// Tier speeds are expressed in strides per second using the original
    /// five-frame cat as the reference. Keeping that number fixed — instead of
    /// deriving it from `frameCount` — means swapping in a longer animation
    /// does not silently multiply the frame rate: at 32 frames, an unscaled
    /// 9 strides/s would ask the display for 288 frames per second.
    static let referenceCycleLength: Double = 5

    /// The names of the bundled frame resources, in playback order.
    private var frameNames: [String] {
        let prefix = self == .cat ? "cat_run" : "dog_run"
        return (0..<frameCount).map { "\(prefix)_\(String(format: "%02d", $0))" }
    }

    /// The size the character is drawn at in the menu bar.
    var canvasSize: NSSize {
        switch self {
        case .cat: return NSSize(width: 44, height: 22)
        case .dog: return NSSize(width: 29, height: 22)
        }
    }

    /// Loads the character's animation frames.
    func loadFrames() -> [NSImage] {
        frameNames.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
                return nil
            }
            guard let image = NSImage(contentsOf: url) else { return nil }

            // The PNGs are 4x artwork. Report them at their logical size so
            // the menu bar lays the icon out correctly — setting `image.size`
            // alone is not enough, because the representation keeps its own
            // pixel-derived size.
            if let representation = image.representations.first as? NSBitmapImageRep {
                representation.size = canvasSize
            }
            image.size = canvasSize
            return image
        }
    }

    /// Whether the character's artwork can be recoloured.
    ///
    /// Both characters are coloured drawings with a dark outline: flattening
    /// them to a single colour loses the markings that make them readable at
    /// 22 points, so neither is tinted. The switch stays here in case a
    /// monochrome artwork is added later.
    var supportsRecolouring: Bool { false }

    /// How much to scale the tier's speed for this character.
    ///
    /// One stride covers the character's whole animation cycle. A 32-frame
    /// cycle would play over six times faster than the five-frame loop the
    /// speeds were written for, so the speed is scaled by the ratio between
    /// the reference loop and the real frame count. This keeps the visual
    /// frame rate identical for both characters.
    var speedScale: Double {
        Character.referenceCycleLength / Double(frameCount)
    }

    /// How fast the resting artwork plays, in frames per second.
    ///
    /// The resting loop is independent of the running speeds: its bucket has
    /// no stride rate to use. The cat uses a single standing still cut from
    /// its green-screen video, so the rate is irrelevant; the dog's resting
    /// artwork is a six-second animation exported at 20 fps and plays at its
    /// native rate. If a still is missing, `IdleArt` falls back to five
    /// procedurally drawn poses at 4 fps.
    var restingFrameRate: Double {
        switch self {
        case .cat: return 4.0
        case .dog: return 20.0
        }
    }

    /// The fastest this character may run, in strides per second.
    ///
    /// The limit is really about the *visual* frame rate: a stride shows the
    /// whole frame cycle, so the cap has to shrink as the cycle grows. Using
    /// the fixed reference loop keeps both characters within the display's
    /// refresh rate.
    var maximumSpeed: Double {
        LoadTier.maximumSafeSpeed * Character.referenceCycleLength / Double(frameCount)
    }
}
