// アプリアイコンを描いて Resources/AppIcon.icns を作る
// 使い方: swift scripts/make_icon.swift
import AppKit

let canvas: CGFloat = 1024

func symbol(_ name: String, pointSize: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func drawIcon() -> NSImage {
    NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
        // 背景：macOS の標準的なアイコン枠（824pt の角丸四角）
        let inset: CGFloat = 100
        let rect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
        let background = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.black.setFill()
        background.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.75, blue: 0.85, alpha: 1),
        ])!.draw(in: background, angle: 90)

        // SDカード
        let card = symbol("sdcard.fill", pointSize: 430, color: .white)
        let cardSize = card.size
        card.draw(in: NSRect(x: (canvas - cardSize.width) / 2 - 40, y: (canvas - cardSize.height) / 2 + 20,
                             width: cardSize.width, height: cardSize.height))

        // 取り込み矢印のバッジ
        let badgeDiameter: CGFloat = 300
        let badgeRect = NSRect(x: canvas - inset - badgeDiameter - 30, y: inset + 50, width: badgeDiameter, height: badgeDiameter)
        NSGraphicsContext.saveGraphicsState()
        let badgeShadow = NSShadow()
        badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        badgeShadow.shadowBlurRadius = 16
        badgeShadow.shadowOffset = NSSize(width: 0, height: -6)
        badgeShadow.set()
        NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        let arrow = symbol("arrow.down", pointSize: 170, color: .white, weight: .bold)
        let arrowSize = arrow.size
        arrow.draw(in: NSRect(x: badgeRect.midX - arrowSize.width / 2, y: badgeRect.midY - arrowSize.height / 2,
                              width: arrowSize.width, height: arrowSize.height))
        return true
    }
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let icon = drawIcon()
for size in [16, 32, 128, 256, 512] {
    try writePNG(icon, pixels: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try writePNG(icon, pixels: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try writePNG(icon, pixels: 512, to: root.appendingPathComponent("Resources/AppIcon-preview.png"))
print("作成しました: \(output.path)")
