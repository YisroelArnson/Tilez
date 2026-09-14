import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: Double(pixels) / 1024, y: Double(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 204, yRadius: 204)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.34, blue: 0.37, alpha: 1),
                                  ending: NSColor(srgbRed: 0.14, green: 0.65, blue: 0.61, alpha: 1))!
        gradient.draw(in: background, angle: 45)
        let tiles: [(CGRect, CGFloat)] = [
            (CGRect(x: 208, y: 532, width: 280, height: 280), 1),
            (CGRect(x: 532, y: 532, width: 280, height: 280), 0.84),
            (CGRect(x: 208, y: 208, width: 280, height: 280), 0.84),
            (CGRect(x: 532, y: 208, width: 280, height: 280), 0.56)
        ]
        for (rect, alpha) in tiles {
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 54, yRadius: 54).fill()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = rep.representation(using: .png, properties: [:])!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: iconset.appendingPathComponent(filename))
    }
}
