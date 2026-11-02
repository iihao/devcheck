#!/usr/bin/env swift
// 渲染 App 图标母版（1024×1024 PNG）
//
// 用法：swift scripts/make-icon.swift <输出路径>
//
// 设计：深色圆角底板（和终端/菜单栏气质一致）+ 绿色连线符号（对应端口地图）
// 纯离屏绘制，不需要 NSApplication，可在 CI 上跑（但 CI 直接复用已提交的 .icns）

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/icon_1024.png"

let size: CGFloat = 1024

// 用显式位图上下文，避免 lockFocus 在高 DPI 屏幕上画出 2048×2048
guard let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("failed to allocate bitmap\n".utf8))
    exit(1)
}
bitmapRep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
NSGraphicsContext.current?.imageInterpolation = .high

// MARK: - 底板：圆角矩形 + 对角渐变（macOS 图标四周留白约 6%）
let inset = size * 0.055
let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let platePath = NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.225, yRadius: plate.width * 0.225)

let top = NSColor(srgbRed: 0.086, green: 0.106, blue: 0.133, alpha: 1)      // #161B22
let bottom = NSColor(srgbRed: 0.043, green: 0.055, blue: 0.071, alpha: 1)   // #0B0E12
NSGradient(starting: top, ending: bottom)?.draw(in: platePath, angle: -90)

// 顶部一道极淡的高光，让底板不显得死板
NSGraphicsContext.saveGraphicsState()
platePath.addClip()
let glow = NSGradient(colors: [
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07),
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
])
glow?.draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 描边：1px 内发光边
NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10).setStroke()
platePath.lineWidth = size * 0.004
platePath.stroke()

// MARK: - 符号：端口/连线语义
let accent = NSColor(srgbRed: 0.494, green: 0.906, blue: 0.529, alpha: 1)  // #7EE787
let secondary = NSColor(srgbRed: 0.475, green: 0.753, blue: 1.0, alpha: 0.85) // #79C0FF

func tinted(_ symbol: NSImage, with color: NSColor) -> NSImage {
    let image = NSImage(size: symbol.size)
    image.lockFocus()
    symbol.draw(at: .zero, from: NSRect(origin: .zero, size: symbol.size),
                operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    image.unlockFocus()
    return image
}

func drawSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor, center: NSPoint) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let tintedImage = tinted(symbol, with: color)
    let drawSize = tintedImage.size
    let origin = NSPoint(x: center.x - drawSize.width / 2, y: center.y - drawSize.height / 2)
    tintedImage.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

// 主符号：三点连线（端口拓扑）
drawSymbol("point.3.connected.trianglepath.dotted",
           pointSize: size * 0.46,
           weight: .medium,
           color: accent,
           center: NSPoint(x: size / 2, y: size * 0.54))

// 副符号：终端提示符，暗示 CLI
drawSymbol("chevron.left.forwardslash.chevron.right",
           pointSize: size * 0.15,
           weight: .semibold,
           color: secondary,
           center: NSPoint(x: size / 2, y: size * 0.245))

NSGraphicsContext.restoreGraphicsState()

// MARK: - 落盘
guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode png\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
do {
    try png.write(to: url)
    print("wrote \(outputPath) (\(png.count / 1024) KB)")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}