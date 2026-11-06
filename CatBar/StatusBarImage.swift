import AppKit

/// Builds the image shown in the status bar: the character, plus an optional
/// numeric CPU readout.
///
/// Both bundled characters are coloured drawings with dark outlines, so they
/// are shown as-is. The recolouring helper below is kept for monochrome
/// artwork that may be added later.
enum StatusBarImage {

    /// Height of the composed image, in points.
    static let height: CGFloat = 22

    /// The colour the cat's silhouette is drawn in.
    ///
    /// White works on both light and dark menu bars, so it needs no setting.
    static let silhouetteColor = NSColor.white

    /// Recolours a rendered frame.
    static func recolor(_ image: NSImage, to color: NSColor) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let width = source.width
        let height = source.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw the original as a mask so only the silhouette keeps the colour.
        context.setBlendMode(.destinationIn)
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let output = context.makeImage() else { return image }

        // The bitmap is rendered at full pixel resolution (4x), but it must
        // still report the *logical* size. `addRepresentation` copies the
        // representation's size onto the image, so without this the icon
        // would end up 352 points wide and vanish from the menu bar.
        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = image.size

        let result = NSImage(size: image.size)
        result.addRepresentation(representation)
        result.isTemplate = false
        return result
    }

    /// Builds the image shown in the status bar: the cat, plus an optional
    /// numeric readout to its right.
    static func compose(cat: NSImage, text: String?, appearance: NSAppearance) -> NSImage {
        let catSize = cat.size
        let textFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        var textWidth: CGFloat = 0
        var textSize = NSSize.zero
        if let text, !text.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: textFont]
            textSize = (text as NSString).size(withAttributes: attributes)
            textWidth = ceil(textSize.width)
        }

        let width = catSize.width + (textWidth > 0 ? textWidth + 4 : 0)
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let catRect = NSRect(
            x: 0,
            y: (height - catSize.height) / 2,
            width: catSize.width,
            height: catSize.height
        )
        cat.draw(in: catRect, from: .zero, operation: .sourceOver, fraction: 1)

        if let text, !text.isEmpty {
            var attributes: [NSAttributedString.Key: Any] = [.font: textFont]
            attributes[.foregroundColor] = NSColor.labelColor
            let textRect = NSRect(
                x: catSize.width + 4,
                y: (height - textSize.height) / 2,
                width: textWidth,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }

        image.isTemplate = false
        return image
    }
}
