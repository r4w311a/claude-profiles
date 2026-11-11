import AppKit
import ImageIO

enum ProfileIcon {
    static let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

    static func write(for profile: Profile, to url: URL) throws {
        try write(to: url, tint: profile.nsColor) { rect, side in
            Palette.drawBadge(profile.initial, color: profile.nsColor, in: rect, ring: max(1, side * 0.016))
        }
    }

    static func writeManagerIcon(to url: URL) throws {
        try write(to: url, tint: .systemGray) { rect, side in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor(white: 0.2, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: max(1, side * 0.016), dy: max(1, side * 0.016))).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.42, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            guard let symbol = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            let size = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                   width: size.width, height: size.height))
        }
    }

    private static func write(to url: URL, tint: NSColor, badge: (NSRect, CGFloat) -> Void) throws {
        let base = NSWorkspace.shared.icon(forFile: Paths.claudeApp.path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString,
                                                                pixelSizes.count, nil)
        else { throw ProfileError("Could not create the icon at \(url.path).") }

        for pixels in pixelSizes {
            guard let image = render(base: base, pixels: pixels, tint: tint, badge: badge) else {
                throw ProfileError("Could not draw the icon at \(url.path).")
            }
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ProfileError("Could not save the icon at \(url.path).")
        }
    }

    private static func render(base: NSImage, pixels: Int, tint: NSColor,
                               badge: (NSRect, CGFloat) -> Void) -> CGImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }

        let side = CGFloat(pixels)
        bitmap.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let canvas = NSRect(x: 0, y: 0, width: side, height: side)
        base.draw(in: canvas)
        if let mask = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.clip(to: canvas, mask: mask)
            cgContext.setBlendMode(.color)
            cgContext.setFillColor(tint.cgColor)
            cgContext.fill(canvas)
            cgContext.restoreGState()
        }
        let diameter = side * 0.36
        let inset = side * 0.135
        badge(NSRect(x: side - diameter - inset, y: inset, width: diameter, height: diameter), side)

        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}
