#!/usr/bin/env swift
// Generates the Zilla app icon at every size required by
// Zilla/Assets.xcassets/AppIcon.appiconset. A clean theropod footprint
// with sharp claws on a warm sand gradient — minimal Mac styling.
//
// Usage:
//   swift Tools/MakeIcon.swift                  # writes into AppIcon set
//   swift Tools/MakeIcon.swift /tmp/preview     # writes into a temp dir

import AppKit
import CoreGraphics
import Foundation

let outputDir = CommandLine.arguments.dropFirst().first
    ?? "Zilla/Assets.xcassets/AppIcon.appiconset"

enum Mode { case standard, dark, tinted }

struct IconRequest {
    let pixelSize: Int
    let filename: String
    let mode: Mode
}

let icons: [IconRequest] = [
    .init(pixelSize: 16,   filename: "icon_16.png",          mode: .standard),
    .init(pixelSize: 32,   filename: "icon_16@2x.png",       mode: .standard),
    .init(pixelSize: 32,   filename: "icon_32.png",          mode: .standard),
    .init(pixelSize: 64,   filename: "icon_32@2x.png",       mode: .standard),
    .init(pixelSize: 128,  filename: "icon_128.png",         mode: .standard),
    .init(pixelSize: 256,  filename: "icon_128@2x.png",      mode: .standard),
    .init(pixelSize: 256,  filename: "icon_256.png",         mode: .standard),
    .init(pixelSize: 512,  filename: "icon_256@2x.png",      mode: .standard),
    .init(pixelSize: 512,  filename: "icon_512.png",         mode: .standard),
    .init(pixelSize: 1024, filename: "icon_512@2x.png",      mode: .standard),
    .init(pixelSize: 1024, filename: "icon_ios.png",         mode: .standard),
    .init(pixelSize: 1024, filename: "icon_ios_dark.png",    mode: .dark),
    .init(pixelSize: 1024, filename: "icon_ios_tinted.png",  mode: .tinted),
]

struct Palette {
    let top: CGColor
    let bottom: CGColor
    let footprint: CGColor
}

func palette(for mode: Mode) -> Palette {
    switch mode {
    case .standard:
        return Palette(
            top: NSColor(srgbRed: 0.957, green: 0.871, blue: 0.682, alpha: 1.0).cgColor,
            bottom: NSColor(srgbRed: 0.706, green: 0.482, blue: 0.243, alpha: 1.0).cgColor,
            footprint: NSColor(srgbRed: 0.118, green: 0.067, blue: 0.039, alpha: 1.0).cgColor
        )
    case .dark:
        return Palette(
            top: NSColor(srgbRed: 0.184, green: 0.165, blue: 0.133, alpha: 1.0).cgColor,
            bottom: NSColor(srgbRed: 0.078, green: 0.067, blue: 0.051, alpha: 1.0).cgColor,
            footprint: NSColor(srgbRed: 0.937, green: 0.851, blue: 0.659, alpha: 1.0).cgColor
        )
    case .tinted:
        return Palette(
            top: NSColor(srgbRed: 0.22, green: 0.22, blue: 0.22, alpha: 1.0).cgColor,
            bottom: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1.0).cgColor,
            footprint: NSColor.white.cgColor
        )
    }
}

func makeContext(size: Int) -> CGContext {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx
}

func renderIcon(size: Int, mode: Mode) -> Data {
    let s = CGFloat(size)
    let ctx = makeContext(size: size)
    let bounds = CGRect(x: 0, y: 0, width: s, height: s)

    let corner = s * 0.2237
    let bg = CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()

    let p = palette(for: mode)
    let grad = CGGradient(
        colorsSpace: ctx.colorSpace,
        colors: [p.top, p.bottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: s / 2, y: s),
        end: CGPoint(x: s / 2, y: 0),
        options: []
    )

    ctx.setFillColor(p.footprint)
    for shape in makeFootprintShapes(canvas: s) {
        ctx.addPath(shape)
        ctx.fillPath()
    }

    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

func makeFootprintShapes(canvas s: CGFloat) -> [CGPath] {
    let scale = s / 1024.0
    var shapes: [CGPath] = []

    let baseX = 512 * scale
    let baseY = (1024 - 540) * scale

    addToeShapes(to: &shapes,
                 baseX: baseX, baseY: baseY,
                 angle: 0,
                 length: 560 * scale, width: 220 * scale,
                 clawHeight: 96 * scale, clawWidth: 80 * scale,
                 gap: 24 * scale)

    addToeShapes(to: &shapes,
                 baseX: baseX, baseY: baseY,
                 angle: 42 * .pi / 180,
                 length: 480 * scale, width: 200 * scale,
                 clawHeight: 86 * scale, clawWidth: 74 * scale,
                 gap: 22 * scale)

    addToeShapes(to: &shapes,
                 baseX: baseX, baseY: baseY,
                 angle: -42 * .pi / 180,
                 length: 480 * scale, width: 200 * scale,
                 clawHeight: 86 * scale, clawWidth: 74 * scale,
                 gap: 22 * scale)

    return shapes
}

func addToeShapes(to shapes: inout [CGPath],
                  baseX: CGFloat, baseY: CGFloat,
                  angle: CGFloat,
                  length: CGFloat, width: CGFloat,
                  clawHeight: CGFloat, clawWidth: CGFloat,
                  gap: CGFloat) {
    let bodyHeight = length - clawHeight - gap
    var transform = CGAffineTransform(translationX: baseX, y: baseY)
        .rotated(by: angle)

    let body = CGMutablePath()
    body.move(to: CGPoint(x: width / 2, y: width / 2))
    body.addLine(to: CGPoint(x: width / 2, y: bodyHeight - width / 2))
    body.addArc(center: CGPoint(x: 0, y: bodyHeight - width / 2),
                radius: width / 2,
                startAngle: 0,
                endAngle: .pi,
                clockwise: false)
    body.addLine(to: CGPoint(x: -width / 2, y: width / 2))
    body.addArc(center: CGPoint(x: 0, y: width / 2),
                radius: width / 2,
                startAngle: .pi,
                endAngle: 0,
                clockwise: false)
    body.closeSubpath()
    if let transformed = body.copy(using: &transform) {
        shapes.append(transformed)
    }

    let claw = CGMutablePath()
    let clawBase = bodyHeight + gap
    claw.move(to: CGPoint(x: 0, y: clawBase + clawHeight))
    claw.addLine(to: CGPoint(x: -clawWidth / 2, y: clawBase))
    claw.addLine(to: CGPoint(x: clawWidth / 2, y: clawBase))
    claw.closeSubpath()
    if let transformed = claw.copy(using: &transform) {
        shapes.append(transformed)
    }
}

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for icon in icons {
    let data = renderIcon(size: icon.pixelSize, mode: icon.mode)
    let url = URL(fileURLWithPath: "\(outputDir)/\(icon.filename)")
    try data.write(to: url)
    print("wrote \(url.path) (\(icon.pixelSize)px, \(icon.mode))")
}
