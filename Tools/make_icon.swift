import Cocoa

// Generates AppIcon.iconset PNGs from a source image.
// Center-crops to a square and clips to a macOS-style rounded rect so the
// source's background color doesn't leak into the icon corners.
// Usage: swift make_icon.swift <input.png> <output_iconset_dir>

let args = CommandLine.arguments
let srcPath = args.count > 1 ? args[1] : "Assets/IconSource.png"
let outDir = args.count > 2 ? args[2] : "AppIcon.iconset"

guard let src = NSImage(contentsOfFile: srcPath),
      let srcData = src.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcData) else {
    fatalError("cannot load \(srcPath)")
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int, to path: String) throws {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    // Center-crop the source to a square, trimmed ~6% to drop the stray
    // dark pixel at the bottom edge of the original image.
    let sw = CGFloat(srcRep.pixelsWide), sh = CGFloat(srcRep.pixelsHigh)
    let side = min(sw, sh) * 0.88
    let crop = NSRect(x: (sw - side) / 2, y: (sh - side) / 2, width: side, height: side)

    // Clip to a macOS-style squircle spanning the full canvas — the source's
    // light rounded tile becomes the icon's face.
    let clip = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                            xRadius: s * 0.2237, yRadius: s * 0.2237)
    clip.addClip()
    srcRep.draw(in: NSRect(x: 0, y: 0, width: s, height: s),
                from: crop, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: nil)

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("failed to render \(path)")
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in variants {
    try render(px, to: "\(outDir)/\(name)")
}
print("iconset written to \(outDir)")
