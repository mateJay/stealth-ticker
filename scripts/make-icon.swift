// 生成 AppIcon.icns。用法：swift scripts/make-icon.swift
// 设计：深色圆角底 + 一颗绿色圆点 + 一圈淡淡的脉冲环，呼应菜单栏里的样子。

import AppKit

let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let inset = canvas * 0.095
let base = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let rounded = NSBezierPath(roundedRect: base, xRadius: canvas * 0.225, yRadius: canvas * 0.225)

// 底色
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1),
    NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1),
])!
gradient.draw(in: rounded, angle: -90)

// 内描边，让边缘在浅色背景上更清晰
NSColor.white.withAlphaComponent(0.07).setStroke()
rounded.lineWidth = canvas * 0.005
rounded.stroke()

// 脉冲环
let ringDiameter = canvas * 0.46
let ring = NSBezierPath(ovalIn: NSRect(
    x: (canvas - ringDiameter) / 2,
    y: (canvas - ringDiameter) / 2,
    width: ringDiameter,
    height: ringDiameter
))
NSColor(srgbRed: 0.20, green: 0.86, blue: 0.45, alpha: 0.18).setStroke()
ring.lineWidth = canvas * 0.018
ring.stroke()

// 中心圆点
let dotDiameter = canvas * 0.27
let dot = NSBezierPath(ovalIn: NSRect(
    x: (canvas - dotDiameter) / 2,
    y: (canvas - dotDiameter) / 2,
    width: dotDiameter,
    height: dotDiameter
))
NSColor(srgbRed: 0.20, green: 0.86, blue: 0.45, alpha: 1).setFill()
dot.fill()

NSGraphicsContext.restoreGraphicsState()

let output = URL(fileURLWithPath: "AppIcon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path)")
