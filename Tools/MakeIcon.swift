#!/usr/bin/env swift
// Generates the Zilla app icon at every size required by
// Zilla/Assets.xcassets/AppIcon.appiconset. A clean theropod footprint
// (heel pad + three teardrop toes) on a warm gradient.
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

func gradient(for mode: Mode) -> (CGColor, CGColor) {
    switch mode {
    case .standard:
        return (
            NSColor(srgbRed: 1.00, green: 0.58, blue: 0.32, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.92, green: 0.30, blue: 0.18, alpha: 1.0).cgColor
        )
    case .dark:
        return (
            NSColor(srgbRed: 0.20, green: 0.24, blue: 0.34, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1.0).cgColor
        )
    case .tinted:
        return (
            NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.04, green: 0.04, blue: 0.04, alpha: 1.0).cgColor
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

    // macOS app-icon corner radius (Apple's continuous corner ≈ 22.37% of side).
    let corner = s * 0.2237
    let bg = CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()

    let (top, bottom) = gradient(for: mode)
    let grad = CGGradient(
        colorsSpace: ctx.colorSpace,
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: s / 2, y: s),
        end: CGPoint(x: s / 2, y: 0),
        options: []
    )

    let footprint = makeFootprint(canvas: s)
    ctx.addPath(footprint)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.97).cgColor)
    ctx.fillPath()

    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

func makeFootprint(canvas s: CGFloat) -> CGPath {
    let path = CGMutablePath()

    // Heel pad — wide stadium shape, dominant base of the print.
    let heelW = s * 0.62
    let heelH = s * 0.20
    let heelRect = CGRect(x: (s - heelW) / 2, y: s * 0.14, width: heelW, height: heelH)
    let heelPath = CGPath(
        roundedRect: heelRect,
        cornerWidth: heelH * 0.5,
        cornerHeight: heelH * 0.5,
        transform: nil
    )
    path.addPath(heelPath)

    // Three toes — fat stadiums embedded into the top of the heel pad.
    let heelTop = heelRect.maxY

    addToe(
        to: path,
        base: CGPoint(x: s * 0.50, y: heelTop - s * 0.07),
        length: s * 0.50,
        width: s * 0.20,
        angle: 0
    )
    addToe(
        to: path,
        base: CGPoint(x: s * 0.275, y: heelTop - s * 0.05),
        length: s * 0.40,
        width: s * 0.17,
        angle: -0.42
    )
    addToe(
        to: path,
        base: CGPoint(x: s * 0.725, y: heelTop - s * 0.05),
        length: s * 0.40,
        width: s * 0.17,
        angle: 0.42
    )

    return path
}

// Adds a stadium-shaped toe (rectangle with semicircular ends) to `path`.
// `angle` is radians clockwise from straight up.
func addToe(to path: CGMutablePath,
            base: CGPoint,
            length: CGFloat,
            width: CGFloat,
            angle: CGFloat) {
    let toeRect = CGRect(x: -width / 2, y: 0, width: width, height: length)
    let toe = CGPath(
        roundedRect: toeRect,
        cornerWidth: width / 2,
        cornerHeight: width / 2,
        transform: nil
    )
    var transform = CGAffineTransform(translationX: base.x, y: base.y)
        .rotated(by: -angle)
    if let transformed = toe.copy(using: &transform) {
        path.addPath(transformed)
    }
}

// MARK: - Run

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for icon in icons {
    let data = renderIcon(size: icon.pixelSize, mode: icon.mode)
    let url = URL(fileURLWithPath: "\(outputDir)/\(icon.filename)")
    try data.write(to: url)
    print("wrote \(url.path) (\(icon.pixelSize)px, \(icon.mode))")
}
