#!/usr/bin/env swift
// Regenerates the StorageBar app icon: an original capacity-ring glyph on a rounded square.
// Usage: swift scripts/make-icon.swift StorageBar/Assets.xcassets/AppIcon.appiconset
// Drawn from scratch with CoreGraphics (SF Symbols may not be used in app icons).
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // macOS icon grid: the body fills 80% of the canvas, leaving room for the shadow.
    let body = CGRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.2237, cornerHeight: body.width * 0.2237, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                 color: NSColor.black.withAlphaComponent(0.30).cgColor)
    cg.addPath(path)
    cg.setFillColor(NSColor(srgbRed: 0.04, green: 0.42, blue: 0.94, alpha: 1).cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [NSColor(srgbRed: 0.36, green: 0.72, blue: 1.0, alpha: 1).cgColor,
                 NSColor(srgbRed: 0.04, green: 0.40, blue: 0.93, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: size / 2, y: body.maxY), end: CGPoint(x: size / 2, y: body.minY), options: [])
    cg.restoreGState()

    // Capacity ring: faint full track, solid arc for used space, spindle dot in the middle.
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = body.width * 0.29
    let line = body.width * 0.095
    cg.setLineCap(.round)
    cg.setLineWidth(line)

    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.32).cgColor)
    cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    let start = CGFloat.pi / 2                       // 12 o'clock
    let end = start - CGFloat.pi * 2 * 0.64          // 64 % used, clockwise
    cg.setStrokeColor(NSColor.white.cgColor)
    cg.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    cg.strokePath()

    cg.setFillColor(NSColor.white.cgColor)
    let dot = body.width * 0.075
    cg.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let slots: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images = [[String: String]]()
for slot in slots {
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    try render(pixels: slot.points * slot.scale).write(to: outDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(slot.points)x\(slot.points)", "scale": "\(slot.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(slots.count) icons to \(outDir.path)")
