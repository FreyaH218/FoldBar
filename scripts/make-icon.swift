import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 205, yRadius: 205)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.47, green: 0.45, blue: 0.98, alpha: 1),
                                  ending: NSColor(srgbRed: 0.24, green: 0.23, blue: 0.69, alpha: 1))!
        gradient.draw(in: background, angle: -70)
        NSColor.white.withAlphaComponent(0.32).setFill()
        NSBezierPath(roundedRect: NSRect(x: 238, y: 252, width: 548, height: 260), xRadius: 63, yRadius: 63).fill()
        NSColor.white.withAlphaComponent(0.60).setFill()
        NSBezierPath(roundedRect: NSRect(x: 238, y: 363, width: 548, height: 260), xRadius: 63, yRadius: 63).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 238, y: 474, width: 548, height: 260), xRadius: 63, yRadius: 63).fill()
        NSColor(srgbRed: 0.40, green: 0.38, blue: 0.86, alpha: 1).setFill()
        for x in [340, 468, 596] {
            NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: 569, width: 76, height: 76), xRadius: 21, yRadius: 21).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Failed to render icon") }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    }
}

// ICNS supports embedded PNG representations. Assemble the container directly,
// so packaging does not depend on a running IconServices GUI connection.
func word(_ value: UInt32) -> Data {
    var big = value.bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
}
var chunks = Data()
let representations = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
]
for (type, file) in representations {
    let png = try Data(contentsOf: URL(fileURLWithPath: destination).appendingPathComponent(file))
    chunks.append(Data(type.utf8))
    chunks.append(word(UInt32(png.count + 8)))
    chunks.append(png)
}
var container = Data("icns".utf8)
container.append(word(UInt32(chunks.count + 8)))
container.append(chunks)
try container.write(to: URL(fileURLWithPath: destination).deletingPathExtension().appendingPathExtension("icns"))
