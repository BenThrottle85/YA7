import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let metadata: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    .write(to: destination.appendingPathComponent("Contents.json"))

for (name, symbol) in [("YA7PackActionTemplate", "archivebox"), ("YA7ExtractActionTemplate", "folder.badge.plus"), ("YA7CheckActionTemplate", "checkmark.shield")] {
    guard let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 24, weight: .regular)) else {
        fatalError("Symbol unavailable: \(symbol)")
    }
    let imageSet = destination.appendingPathComponent(name + ".imageset", isDirectory: true)
    try FileManager.default.createDirectory(at: imageSet, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for scale in 1...2 {
        let pixels = 32 * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Bitmap unavailable") }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        context.cgContext.clear(bounds)
        let ratio = min(26 / source.size.width, 26 / source.size.height) * CGFloat(scale)
        let size = NSSize(width: source.size.width * ratio, height: source.size.height * ratio)
        source.draw(in: NSRect(x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2,
                              width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.black.setFill()
        bounds.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        let filename = name + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageSet.appendingPathComponent(filename))
        images.append(["idiom": "mac", "scale": "\(scale)x", "filename": filename])
    }
    let contents: [String: Any] = ["info": ["author": "xcode", "version": 1], "images": images,
                                  "properties": ["template-rendering-intent": "template"]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: imageSet.appendingPathComponent("Contents.json"))
}
