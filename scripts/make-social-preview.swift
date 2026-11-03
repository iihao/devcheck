#!/usr/bin/env swift
// 生成 GitHub Social Preview（1280×640，上传到 Settings → Social preview）
//
//   swift scripts/make-social-preview.swift docs/social-preview.png
//
// GitHub 不支持 API 上传这些图，需要手动传一次。
// 设计目标：在 Twitter/X 的时间线里 3 秒能读懂「这是个什么东西 + 解决了什么」。

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/social-preview.png"

let width: CGFloat = 1280
let height: CGFloat = 640

guard let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
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
bitmapRep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
NSGraphicsContext.current?.imageInterpolation = .high

// MARK: - 背景：深色渐变 + 右上角绿色光斑
let background = NSGradient(colors: [
    NSColor(srgbRed: 0.055, green: 0.067, blue: 0.086, alpha: 1),
    NSColor(srgbRed: 0.020, green: 0.031, blue: 0.043, alpha: 1),
])
background?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -60)

let glow = NSGradient(colors: [
    NSColor(srgbRed: 0.494, green: 0.906, blue: 0.529, alpha: 0.16),
    NSColor(srgbRed: 0.494, green: 0.906, blue: 0.529, alpha: 0.0),
])
glow?.draw(in: NSRect(x: width * 0.52, y: height * 0.42, width: width * 0.56, height: height * 0.7), angle: 0)

// MARK: - 图标
if let icon = NSImage(contentsOfFile: "docs/icon.png") {
    let size: CGFloat = 132
    icon.draw(in: NSRect(x: 88, y: height - 92 - size, width: size, height: size))
}

// MARK: - 文案
func draw(_ text: String, font: NSFont, color: NSColor, at point: NSPoint) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    (text as NSString).draw(at: point, withAttributes: attributes)
}

let titleFont = NSFont.systemFont(ofSize: 72, weight: .bold)
let subtitleFont = NSFont.systemFont(ofSize: 34, weight: .medium)
let monoFont = NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
let smallFont = NSFont.systemFont(ofSize: 24, weight: .regular)

let green = NSColor(srgbRed: 0.494, green: 0.906, blue: 0.529, alpha: 1)
let blue = NSColor(srgbRed: 0.475, green: 0.753, blue: 1.0, alpha: 1)
let white = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.96, alpha: 1)
let gray = NSColor(srgbRed: 0.55, green: 0.60, blue: 0.66, alpha: 1)

draw("DevCheck", font: titleFont, color: white, at: NSPoint(x: 250, y: height - 200))
draw("Menu bar port map for macOS", font: subtitleFont, color: green, at: NSPoint(x: 254, y: height - 254))

draw("Who holds :3000, which project it belongs to,", font: smallFont, color: gray, at: NSPoint(x: 254, y: height - 306))
draw("and what to do about it. No sudo. No telemetry.", font: smallFont, color: gray, at: NSPoint(x: 254, y: height - 342))

// 终端片段
let panel = NSRect(x: 88, y: 132, width: width - 176, height: 128)
let panelPath = NSBezierPath(roundedRect: panel, xRadius: 16, yRadius: 16)
NSColor(srgbRed: 0.078, green: 0.094, blue: 0.118, alpha: 1).setFill()
panelPath.fill()
NSColor(srgbRed: 0.19, green: 0.22, blue: 0.25, alpha: 1).setStroke()
panelPath.lineWidth = 1.5
panelPath.stroke()

draw("$ devcheck why 5000", font: monoFont, color: white, at: NSPoint(x: 120, y: 216))

// 高亮 "AirPlay" 一行
let line = "Port 5000 is macOS AirPlay Receiver — turn it off in System Settings, or use 5001."
let attributed = NSMutableAttributedString(
    string: line,
    attributes: [.font: monoFont, .foregroundColor: gray]
)
for keyword in ["AirPlay Receiver", "5001"] {
    let range = (line as NSString).range(of: keyword)
    if range.location != NSNotFound {
        attributed.addAttribute(.foregroundColor, value: green, range: range)
    }
}
attributed.draw(at: NSPoint(x: 120, y: 172))

// 右下角：一句话愿景
draw("github.com/iihao/devcheck", font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium),
     color: blue, at: NSPoint(x: 120, y: 96))

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode png\n".utf8))
    exit(1)
}
let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: url)
print("wrote \(outputPath) (\(Int(width))x\(Int(height)), \(png.count / 1024) KB)")