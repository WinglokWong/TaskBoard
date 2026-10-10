import SwiftUI
import AppKit

struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        r = Double(ns.redComponent)
        g = Double(ns.greenComponent)
        b = Double(ns.blueComponent)
        a = Double(ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// 相对亮度（近似），用于决定前景文字颜色
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// 在该背景色上应使用的文字颜色
    var foreground: Color { (a < 0.45 || luminance > 0.6) ? Color.black.opacity(0.85) : .white }

    func isClose(to other: RGBAColor?) -> Bool {
        guard let other else { return false }
        return abs(r - other.r) < 0.01 && abs(g - other.g) < 0.01
            && abs(b - other.b) < 0.01 && abs(a - other.a) < 0.01
    }
}

struct PaletteColor: Identifiable {
    let name: String
    let value: RGBAColor
    var id: String { name }
}

enum Palette {
    static let presets: [PaletteColor] = [
        // 鲜艳
        .init(name: "绿", value: RGBAColor(hex: 0x4BCE97)),
        .init(name: "黄", value: RGBAColor(hex: 0xF5CD47)),
        .init(name: "橙", value: RGBAColor(hex: 0xFEA362)),
        .init(name: "红", value: RGBAColor(hex: 0xF87168)),
        .init(name: "紫", value: RGBAColor(hex: 0x9F8FEF)),
        .init(name: "蓝", value: RGBAColor(hex: 0x579DFF)),
        .init(name: "天蓝", value: RGBAColor(hex: 0x6CC3E0)),
        .init(name: "粉", value: RGBAColor(hex: 0xE774BB)),
        // 浅色
        .init(name: "浅绿", value: RGBAColor(hex: 0xBAF3DB)),
        .init(name: "浅黄", value: RGBAColor(hex: 0xF8E6A0)),
        .init(name: "浅橙", value: RGBAColor(hex: 0xFEDEC8)),
        .init(name: "浅红", value: RGBAColor(hex: 0xFFD5D2)),
        .init(name: "浅紫", value: RGBAColor(hex: 0xDFD8FD)),
        .init(name: "浅蓝", value: RGBAColor(hex: 0xCCE0FF)),
        .init(name: "浅灰", value: RGBAColor(hex: 0xEBECF0)),
        .init(name: "白", value: RGBAColor(hex: 0xFFFFFF)),
        // 深色
        .init(name: "深绿", value: RGBAColor(hex: 0x1F845A)),
        .init(name: "深黄", value: RGBAColor(hex: 0x946F00)),
        .init(name: "深橙", value: RGBAColor(hex: 0xC25100)),
        .init(name: "深红", value: RGBAColor(hex: 0xC9372C)),
        .init(name: "深紫", value: RGBAColor(hex: 0x6E5DC6)),
        .init(name: "深蓝", value: RGBAColor(hex: 0x0C66E4)),
        .init(name: "灰", value: RGBAColor(hex: 0x626F86)),
        .init(name: "墨", value: RGBAColor(hex: 0x172B4D)),
    ]

    static func name(for color: RGBAColor) -> String? {
        presets.first(where: { $0.value.isClose(to: color) })?.name
    }

    static func color(named name: String) -> RGBAColor? {
        presets.first(where: { $0.name == name })?.value
    }
}

/// 预设色板 + 系统取色器
struct ColorSwatchPicker: View {
    @Binding var selection: RGBAColor?
    var allowsNone = true
    var noneHelp = "默认"

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Palette.presets) { preset in
                    swatch(preset.value.color, selected: preset.value.isClose(to: selection))
                        .onTapGesture { selection = preset.value }
                        .help(preset.name)
                }
            }
            HStack(spacing: 10) {
                if allowsNone {
                    Button {
                        selection = nil
                    } label: {
                        Label(noneHelp, systemImage: selection == nil ? "checkmark.circle.fill" : "circle.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ColorPicker(
                    "自定义颜色",
                    selection: Binding(
                        get: { selection?.color ?? .white },
                        set: { selection = RGBAColor($0) }
                    ),
                    supportsOpacity: true
                )
                .controlSize(.small)
            }
        }
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color)
            .frame(width: 26, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15),
                                  lineWidth: selected ? 2.5 : 1)
            )
            .contentShape(Rectangle())
    }
}
