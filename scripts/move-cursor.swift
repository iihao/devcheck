#!/usr/bin/env swift
// 录屏 Demo 用：让光标沿菜单平滑移动，形成"浏览菜单"的效果
//
// 用法：swift scripts/move-cursor.swift <x> <yStart> <yEnd> <durationSeconds>
//
// 用 CGEvent 投递真实 mouseMoved 事件（warp 不会触发 AppKit 菜单高亮）。
// 需要「辅助功能」权限；没有权限时事件会被系统丢弃，但不会报错。

import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 5,
      let x = Double(CommandLine.arguments[1]),
      let yStart = Double(CommandLine.arguments[2]),
      let yEnd = Double(CommandLine.arguments[3]),
      let duration = Double(CommandLine.arguments[4])
else {
    FileHandle.standardError.write(Data("usage: move-cursor <x> <yStart> <yEnd> <duration>\n".utf8))
    exit(2)
}

let steps = max(2, Int(duration * 60))
let stepDelay = useconds_t(duration / Double(steps) * 1_000_000)

func post(_ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

// 从屏幕外的安全位置滑入，避免一上来就瞬移
post(CGPoint(x: x - 200, y: yStart))
usleep(useconds_t(0.15 * 1_000_000))

for step in 0...steps {
    let t = Double(step) / Double(steps)
    // ease-in-out，结尾慢一点，方便看清最后停留的位置
    let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    let y = yStart + (yEnd - yStart) * eased
    post(CGPoint(x: x, y: y))
    usleep(stepDelay)
}

// 在末尾停住，让最后一项保持高亮
usleep(useconds_t(1.2 * 1_000_000))