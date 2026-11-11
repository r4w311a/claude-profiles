import AppKit

enum Palette {
    static let colors: [(String, NSColor)] = [
        ("blue", .systemBlue), ("orange", .systemOrange), ("green", .systemGreen),
        ("purple", .systemPurple), ("red", .systemRed), ("pink", .systemPink),
        ("teal", .systemTeal), ("yellow", .systemYellow), ("indigo", .systemIndigo),
        ("mint", .systemMint), ("brown", .systemBrown), ("gray", .systemGray),
    ]
    static var names: [String] { colors.map(\.0) }

    static func color(named name: String) -> NSColor {
        colors.first { $0.0 == name.lowercased() }?.1 ?? .systemGray
    }

    static func badge(_ letter: String, color: NSColor, size: CGFloat = 16, alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawBadge(letter, color: color.withAlphaComponent(alpha), in: rect.insetBy(dx: 0.5, dy: 0.5), ring: 0)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func drawBadge(_ letter: String, color: NSColor, in rect: NSRect, ring: CGFloat) {
        if ring > 0 {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: ring, dy: ring)).fill()

        let font = NSFont.systemFont(ofSize: rect.height * 0.58, weight: .bold)
        let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.white])
        let width = text.size().width
        let baseline = rect.midY - font.capHeight / 2
        text.draw(at: NSPoint(x: rect.midX - width / 2, y: baseline + font.descender))
    }
}
