// 生成 TermDeck 应用图标（iconset PNG），配合 iconutil 生成 .icns
// 用法: swift Scripts/make_icon.swift && iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func drawIcon(size: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // 背景圆角矩形 + 渐变
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: size * 0.185, yRadius: size * 0.185)
    bgPath.addClip()
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.18, green: 0.20, blue: 0.27, alpha: 1),
        ending: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.11, alpha: 1)
    )!
    gradient.draw(in: bgPath, angle: -70)

    // 内部终端窗口
    let margin = size * 0.17
    let win = rect.insetBy(dx: margin, dy: margin)
    let winPath = NSBezierPath(roundedRect: win, xRadius: size * 0.055, yRadius: size * 0.055)
    NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1).setFill()
    winPath.fill()

    // 红绿灯
    let dotSize = size * 0.052
    let dotY = win.maxY - size * 0.075
    let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
    for (index, color) in colors.enumerated() {
        let dot = NSRect(
            x: win.minX + size * 0.055 + CGFloat(index) * size * 0.078,
            y: dotY,
            width: dotSize,
            height: dotSize
        )
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    // 提示符 >_
    let text = ">_"
    let font = NSFont.monospacedSystemFont(ofSize: size * 0.30, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.38, green: 0.87, blue: 0.58, alpha: 1),
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textSize = string.size()
    string.draw(at: NSPoint(
        x: win.midX - textSize.width / 2,
        y: win.midY - textSize.height / 2 - size * 0.05
    ))
}

func pngData(pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(Int, String)] = [
    (16, "16x16"),
    (32, "16x16@2x"),
    (32, "32x32"),
    (64, "32x32@2x"),
    (128, "128x128"),
    (256, "128x128@2x"),
    (256, "256x256"),
    (512, "256x256@2x"),
    (512, "512x512"),
    (1024, "512x512@2x"),
]

let fileManager = FileManager.default
let dir = "AppIcon.iconset"
try? fileManager.removeItem(atPath: dir)
try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (pixelSize, name) in entries {
    let data = pngData(pixelSize: pixelSize)
    try data.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
print("AppIcon.iconset 已生成")
