#!/usr/bin/env swift
// Renders the app icon and menu bar template icons into Switches/Assets.xcassets.
//
// Usage (from the repo root): swift scripts/make_icons.swift

import AppKit
import Foundation

let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Switches/Assets.xcassets")

func png(size: Int, draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    let url = assets.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func writeJSON(_ object: Any, _ path: String) throws {
    try write(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), path)
}

// MARK: App icon

func drawAppIcon(in rect: CGRect) {
    let s = rect.width
    // macOS icon grid: 824/1024 body with ~185/1024 corner radius.
    let body = rect.insetBy(dx: s * 100 / 1024, dy: s * 100 / 1024)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
    )!.draw(in: bodyPath, angle: -90)

    // Keycap: skirt + dished top.
    let cap = body.insetBy(dx: body.width * 0.2, dy: body.height * 0.2).offsetBy(dx: -body.width * 0.06, dy: -body.height * 0.02)
    let skirt = NSBezierPath(roundedRect: cap, xRadius: s * 0.06, yRadius: s * 0.06)
    NSGradient(
        starting: NSColor(calibratedRed: 0.93, green: 0.55, blue: 0.20, alpha: 1),
        ending: NSColor(calibratedRed: 0.78, green: 0.33, blue: 0.10, alpha: 1)
    )!.draw(in: skirt, angle: -90)

    let top = NSRect(
        x: cap.minX + cap.width * 0.12, y: cap.minY + cap.height * 0.2,
        width: cap.width * 0.76, height: cap.height * 0.68
    )
    let topPath = NSBezierPath(roundedRect: top, xRadius: s * 0.045, yRadius: s * 0.045)
    NSGradient(
        starting: NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.40, alpha: 1),
        ending: NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.24, alpha: 1)
    )!.draw(in: topPath, angle: -90)

    // Sound waves to the right of the cap.
    NSColor(calibratedWhite: 1, alpha: 0.85).setStroke()
    for i in 0..<2 {
        let r = s * (0.07 + 0.06 * CGFloat(i))
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: cap.maxX + s * 0.01, y: cap.midY),
            radius: r, startAngle: -40, endAngle: 40
        )
        arc.lineWidth = s * 0.022
        arc.lineCapStyle = .round
        arc.stroke()
    }
}

let appIconSizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for (points, scale) in appIconSizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try write(png(size: points * scale, draw: drawAppIcon), "AppIcon.appiconset/\(name)")
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], "AppIcon.appiconset/Contents.json")

// MARK: Menu bar template icons

func drawMenuBarIcon(paused: Bool) -> (CGRect) -> Void {
    { rect in
        let config = NSImage.SymbolConfiguration(pointSize: rect.height * 0.62, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: paused ? 0.45 : 1)
        guard paused else { return }
        let line = NSBezierPath()
        line.move(to: NSPoint(x: rect.width * 0.15, y: rect.height * 0.12))
        line.line(to: NSPoint(x: rect.width * 0.85, y: rect.height * 0.88))
        line.lineCapStyle = .round
        NSGraphicsContext.current?.compositingOperation = .clear
        line.lineWidth = rect.height * 0.2
        line.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setStroke()
        line.lineWidth = rect.height * 0.08
        line.stroke()
    }
}

for (name, paused) in [("MenuBarIcon", false), ("MenuBarIconPaused", true)] {
    var entries: [[String: String]] = []
    for scale in [1, 2] {
        let file = "\(name)\(scale == 2 ? "@2x" : "").png"
        try write(png(size: 18 * scale, draw: drawMenuBarIcon(paused: paused)), "\(name).imageset/\(file)")
        entries.append(["filename": file, "idiom": "universal", "scale": "\(scale)x"])
    }
    try writeJSON(
        ["images": entries, "info": ["author": "xcode", "version": 1], "properties": ["template-rendering-intent": "template"]],
        "\(name).imageset/Contents.json"
    )
}

try writeJSON(["info": ["author": "xcode", "version": 1]], "Contents.json")
print("Icons written to \(assets.path)")
