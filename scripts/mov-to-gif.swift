#!/usr/bin/env swift
// 把录屏 .mov 转成 README 用的 GIF
//
// 用法：swift scripts/mov-to-gif.swift <input.mov> <output.gif> [fps] [maxWidth]
//
// 零依赖：AVFoundation 抽帧 + ImageIO 编码，不需要 ffmpeg。
// 对 UI 录屏（大面积纯色）系统 GIF 编码质量足够，体积也小。

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: mov-to-gif <in.mov> <out.gif> [fps] [maxWidth]\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let fps = arguments.count > 3 ? (Double(arguments[3]) ?? 12) : 12
let maxWidth = arguments.count > 4 ? (Double(arguments[4]) ?? 1000) : 1000

let asset = AVURLAsset(url: inputURL)
let durationSeconds = CMTimeGetSeconds(asset.duration)
guard durationSeconds.isFinite, durationSeconds > 0 else {
    FileHandle.standardError.write(Data("cannot read duration\n".utf8))
    exit(1)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

func scaled(_ image: CGImage) -> CGImage {
    let width = Double(image.width)
    guard width > maxWidth else { return image }
    let scale = maxWidth / width
    let newWidth = Int(maxWidth)
    let newHeight = Int(Double(image.height) * scale)

    guard let context = CGContext(
        data: nil,
        width: newWidth,
        height: newHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    return context.makeImage() ?? image
}

var frames: [CGImage] = []
let totalFrames = max(1, Int(durationSeconds * fps))
for index in 0..<totalFrames {
    let seconds = Double(index) / fps
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
    frames.append(scaled(image))
}

guard !frames.isEmpty else {
    FileHandle.standardError.write(Data("no frames extracted\n".utf8))
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    frames.count,
    nil
) else {
    FileHandle.standardError.write(Data("cannot create gif\n".utf8))
    exit(1)
}

let loopProperties: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
]
CGImageDestinationSetProperties(destination, loopProperties as CFDictionary)

let frameProperties: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: 1.0 / fps,
        kCGImagePropertyGIFUnclampedDelayTime: 1.0 / fps,
    ],
]

for frame in frames {
    CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("failed to write gif\n".utf8))
    exit(1)
}

let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("wrote \(outputURL.path)")
print("frames: \(frames.count) @ \(fps)fps · \(Int(frames[0].width))x\(Int(frames[0].height)) · \(Double(size ?? 0) / 1024.0 / 1024.0) MB")