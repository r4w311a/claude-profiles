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

    static func dot(_ color: NSColor, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
