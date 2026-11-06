import AppKit

/// Fallback idle pose, used only when a character has no bundled rest image.
///
/// Both characters now ship their own resting artwork — the cat a standing
/// still chroma-keyed from its green-screen video, the dog a 120-frame
/// animation — so this drawn pose is a safety net for missing resources. It
/// is a curled-up animal that breathes and sways its tail, in the same
/// cream-and-brown palette as the coloured artwork so it stays legible on
/// both light and dark menu bars.
enum IdleArt {

    /// The size the pose is drawn at.
    static let canvasSize = NSSize(width: 44, height: 22)

    /// Builds the idle animation.
    ///
    /// - Parameters:
    ///   - character: the character the pose belongs to.
    ///   - count: number of frames in the cycle.
    static func buildFrames(for character: Character, count: Int = 5) -> [NSImage] {
        // A dedicated still image wins when the bundle has one.
        if let loaded = loadRestingFrames(for: character) {
            return loaded
        }
        return (0..<count).map { index in
            let t = Double(index) / Double(count)
            return render { ctx in draw(ctx, t: t, character: character) }
        }
    }

    /// Loads the resting artwork from the bundle, if it is there.
    ///
    /// An animated rest pose is a numbered sequence `rest_<character>_NNN.png`;
    /// a single `rest_<character>.png` is treated as a still. The images are
    /// shown as-is, so they should already be in the character's colours and
    /// include their own outline.
    static func loadRestingFrames(for character: Character) -> [NSImage]? {
        let prefix = "rest_\(character.rawValue)_"
        var sequence: [NSImage] = []
        var index = 0
        while let url = Bundle.main.url(
                forResource: "\(prefix)\(String(format: "%03d", index))",
                withExtension: "png"),
              let image = NSImage(contentsOf: url) {
            size(image, for: character)
            sequence.append(image)
            index += 1
        }
        if !sequence.isEmpty { return sequence }

        guard let url = Bundle.main.url(forResource: "rest_\(character.rawValue)",
                                        withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        size(image, for: character)
        return [image]
    }

    /// Reports a loaded image at the character's logical menu-bar size.
    private static func size(_ image: NSImage, for character: Character) {
        if let representation = image.representations.first as? NSBitmapImageRep {
            representation.size = character.canvasSize
        }
        image.size = character.canvasSize
    }

    // MARK: - Rendering helpers

    private static let scale: CGFloat = 4   // Retina backing store

    private static func render(_ body: (CGContext) -> Void) -> NSImage {
        let pixelWidth = Int(canvasSize.width * scale)
        let pixelHeight = Int(canvasSize.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return NSImage() }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: canvasSize.height)
            ctx.scaleBy(x: 1, y: -1)          // flip into top-left origin space
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            body(ctx)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: canvasSize)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    // MARK: - Idle cat

    /// A curled-up animal, drawn to match the silhouette style of the artwork.
    ///
    /// The cat and the dog differ in their ears and muzzle so the resting
    /// pose still reads as the character that is actually running.
    private static func draw(_ ctx: CGContext, t: Double, character: Character) {
        let breathe = CGFloat(sin(t * 2 * .pi)) * 0.4
        let tailSway = CGFloat(sin(t * 2 * .pi)) * 1.6
        let isDog = character == .dog

        // Cream fill with a dark brown outline, matching the bundled coloured
        // artwork and staying legible on both light and dark menu bars.
        let fill = NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.95, alpha: 1)
        let ink = NSColor(calibratedRed: 0.44, green: 0.34, blue: 0.26, alpha: 1)

        // Body: a low, compact haunch — the animal is lying down, so it
        // should not tower over the frame the way a sitting one would.
        let haunch = CGRect(x: 8.0, y: 4.6 + breathe, width: 14.5, height: 11.5)
        // Head, resting on the front paws.
        let head = CGRect(x: 19.8, y: 5.4 + breathe, width: 8.4, height: 8.4)
        // Muzzle, pointing right. The dog's is shorter and rounder.
        let muzzle = isDog
            ? CGRect(x: 25.6, y: 6.4 + breathe, width: 5.0, height: 4.4)
            : CGRect(x: 25.8, y: 6.6 + breathe, width: 5.0, height: 3.6)

        ctx.saveGState()
        ctx.setFillColor(fill.cgColor)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(0.9)
        for shape in [haunch, head, muzzle] {
            ctx.fillEllipse(in: shape)
            ctx.strokeEllipse(in: shape)
        }

        // Ears. The cat's fold back as it dozes; the dog's stay upright and
        // pointy, which is what makes the resting dog recognisable.
        let ears: [[CGPoint]] = isDog ? [
            [CGPoint(x: 20.8, y: 9.8 + breathe), CGPoint(x: 21.4, y: 4.8 + breathe), CGPoint(x: 24.0, y: 8.6 + breathe)],
            [CGPoint(x: 24.6, y: 8.4 + breathe), CGPoint(x: 26.4, y: 4.4 + breathe), CGPoint(x: 27.6, y: 9.0 + breathe)]
        ] : [
            [CGPoint(x: 21.0, y: 9.4 + breathe), CGPoint(x: 21.8, y: 5.6 + breathe), CGPoint(x: 24.2, y: 8.8 + breathe)],
            [CGPoint(x: 24.4, y: 8.6 + breathe), CGPoint(x: 26.2, y: 5.4 + breathe), CGPoint(x: 27.4, y: 9.2 + breathe)]
        ]
        for ear in ears {
            ctx.move(to: ear[0])
            for point in ear.dropFirst() { ctx.addLine(to: point) }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }

        // Tail curled around the body, tucked in front.
        let tailBase = CGPoint(x: 8.6, y: 13.6 + breathe)
        let tailTip = CGPoint(x: 22.4 + tailSway, y: 15.2 + breathe)
        let tailPath = taperedCurve(
            from: tailBase,
            control1: CGPoint(x: 4.0 - tailSway * 0.4, y: 16.6 + breathe),
            control2: CGPoint(x: 16.0 + tailSway * 0.6, y: 17.0 + breathe),
            to: tailTip,
            baseWidth: 3.0,
            tipWidth: 1.0
        )
        ctx.addPath(tailPath)
        ctx.drawPath(using: .fillStroke)

        // Front paws, stretched out in front of the chest.
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(2.2)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 22.6, y: 11.0 + breathe))
        ctx.addLine(to: CGPoint(x: 23.6, y: 16.4))
        ctx.move(to: CGPoint(x: 25.4, y: 11.2 + breathe))
        ctx.addLine(to: CGPoint(x: 26.8, y: 16.4))
        ctx.strokePath()

        ctx.restoreGState()
    }

    /// Builds a closed path that follows a cubic Bézier with a width that
    /// tapers from base to tip — a stroked line cannot do this.
    private static func taperedCurve(
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint,
        baseWidth: CGFloat,
        tipWidth: CGFloat,
        samples: Int = 20
    ) -> CGPath {
        var spine: [CGPoint] = []
        spine.reserveCapacity(samples + 1)
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let mt = 1 - t
            let x = mt * mt * mt * start.x + 3 * mt * mt * t * control1.x + 3 * mt * t * t * control2.x + t * t * t * end.x
            let y = mt * mt * mt * start.y + 3 * mt * mt * t * control1.y + 3 * mt * t * t * control2.y + t * t * t * end.y
            spine.append(CGPoint(x: x, y: y))
        }

        let path = CGMutablePath()
        var left: [CGPoint] = []
        var right: [CGPoint] = []

        for (index, point) in spine.enumerated() {
            let t = CGFloat(index) / CGFloat(samples)
            let width = baseWidth + (tipWidth - baseWidth) * pow(t, 0.75)
            let half = width / 2

            let previous = spine[max(0, index - 1)]
            let next = spine[min(spine.count - 1, index + 1)]
            var dx = next.x - previous.x
            var dy = next.y - previous.y
            let length = max(0.0001, hypot(dx, dy))
            dx /= length
            dy /= length

            left.append(CGPoint(x: point.x - dy * half, y: point.y + dx * half))
            right.append(CGPoint(x: point.x + dy * half, y: point.y - dx * half))
        }

        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }
        for point in right.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}
