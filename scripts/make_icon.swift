// 生成应用图标：swift scripts/make_icon.swift <输出 .iconset 目录>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let bg = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: bg, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 0.34, green: 0.62, blue: 1, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.40, blue: 0.89, alpha: 1))!.draw(in: path, angle: -90)
    let colW = bg.width * 0.24, gap = bg.width * 0.06
    let left = bg.minX + (bg.width - colW * 3 - gap * 2) / 2
    let top = bg.maxY - bg.height * 0.16
    let heights: [CGFloat] = [0.62, 0.44, 0.30]
    let cardColors: [NSColor] = [.white, NSColor(red: 0.96, green: 0.80, blue: 0.28, alpha: 1), NSColor(red: 0.29, green: 0.81, blue: 0.59, alpha: 1)]
    for i in 0..<3 {
        let h = bg.height * heights[i]
        let r = NSRect(x: left + CGFloat(i) * (colW + gap), y: top - h, width: colW, height: h)
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: r, xRadius: s * 0.035, yRadius: s * 0.035).fill()
        let cardH = bg.height * 0.1
        var y = r.maxY - cardH - colW * 0.12
        while y > r.minY + colW * 0.08 {
            cardColors[i].setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX + colW * 0.12, y: y, width: colW * 0.76, height: cardH),
                         xRadius: s * 0.02, yRadius: s * 0.02).fill()
            y -= cardH + colW * 0.12
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
