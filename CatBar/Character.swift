import AppKit

/// The character shown in the menu bar.
///
/// Each character knows how many animation frames it has and how to load
/// them, so the rest of the app does not have to care which one is active.
enum Character: String, CaseIterable, Identifiable {

    /// The running cat from [RunCat365](https://github.com/runcat-dev/RunCat365)
    /// (Apache-2.0).
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
    /// The dog's cycle was interpolated up to thirty-two frames from the
    /// sixteen in the source animation, so it can be played back smoothly.
    var frameCount: Int {
        switch self {
        case .cat: return 5
        case .dog: return 32
        }
    }

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
    /// The cat is a monochrome silhouette, so it can be tinted black or white
    /// to match the menu bar. The dog is a coloured drawing whose black
    /// outline is what makes it recognisable at this size — flattening it to
    /// a solid shape turns it into an unreadable blob — so it keeps its
    /// colours and works on both light and dark menu bars.
    var supportsRecolouring: Bool {
        self == .cat
    }

    /// How much to scale the tier's speed for this character.
    ///
    /// The speeds in `LoadTier` are expressed in strides per second, and one
    /// stride covers the character's whole animation cycle. The cat's cycle is
    /// five frames and the dog's is thirty-two, so at the same stride rate
    /// the dog would appear to move more than six times faster. Scaling by
    /// the frame-count ratio keeps the visual pace the same for both.
    var speedScale: Double {
        Double(Character.cat.frameCount) / Double(frameCount)
    }

    /// How fast the resting artwork plays, in frames per second.
    ///
    /// The resting loop is independent of the running speeds: its bucket has
    /// no stride rate to use. The cat's five-frame procedural pose turns over
    /// at 0.8 cycles per second (4 fps), while the dog's resting artwork is a
    /// six-second animation exported at 20 fps and plays at its native rate.
    var restingFrameRate: Double {
        switch self {
        case .cat: return 4.0
        case .dog: return 20.0
        }
    }

    /// The fastest this character may run, in strides per second.
    ///
    /// The limit is really about the *visual* frame rate: a stride of the cat
    /// shows five frames and a stride of the dog shows thirty-two, so the same
    /// stride rate would ask the dog for far more frames than the display can
    /// show. Capping at the frame rate keeps both characters within it.
    var maximumSpeed: Double {
        LoadTier.maximumSafeSpeed * Double(Character.cat.frameCount) / Double(frameCount)
    }
}
