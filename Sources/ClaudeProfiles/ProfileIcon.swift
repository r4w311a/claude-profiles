import AppKit
import ImageIO

enum ProfileIcon {
    static let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

    static func write(for profile: Profile, to url: URL) throws {
        let base = NSWorkspace.shared.icon(forFile: Paths.claudeApp.path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString,
                                                                pixelSizes.count, nil)
        else { throw ProfileError("Could not create the icon for \(profile.name).") }

        for pixels in pixelSizes {
            guard let image = render(base: base, profile: profile, pixels: pixels) else {
                throw ProfileError("Could not draw the icon for \(profile.name).")
            }
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ProfileError("Could not save the icon for \(profile.name).")
        }
    }

    private static func render(base: NSImage, profile: Profile, pixels: Int) -> CGImage? {
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

        base.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        let diameter = side * 0.44
        let inset = side * 0.05
        let badge = NSRect(x: side - diameter - inset, y: inset, width: diameter, height: diameter)
        Palette.drawBadge(profile.initial, color: profile.nsColor, in: badge, ring: max(1, side * 0.022))

        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}
