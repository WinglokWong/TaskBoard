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
    /// 稳定的标识，不随界面语言变化
    let key: String
    /// 当前语言下的显示名称
    let name: String
    let value: RGBAColor
    var id: String { key }
}

enum Palette {
    static let presets: [PaletteColor] = [
        // 鲜艳
        .init(key: "green", name: String(localized: "绿", comment: "颜色名称"), value: RGBAColor(hex: 0x4BCE97)),
        .init(key: "yellow", name: String(localized: "黄", comment: "颜色名称"), value: RGBAColor(hex: 0xF5CD47)),
        .init(key: "orange", name: String(localized: "橙", comment: "颜色名称"), value: RGBAColor(hex: 0xFEA362)),
        .init(key: "red", name: String(localized: "红", comment: "颜色名称"), value: RGBAColor(hex: 0xF87168)),
        .init(key: "purple", name: String(localized: "紫", comment: "颜色名称"), value: RGBAColor(hex: 0x9F8FEF)),
        .init(key: "blue", name: String(localized: "蓝", comment: "颜色名称"), value: RGBAColor(hex: 0x579DFF)),
        .init(key: "sky", name: String(localized: "天蓝", comment: "颜色名称"), value: RGBAColor(hex: 0x6CC3E0)),
        .init(key: "pink", name: String(localized: "粉", comment: "颜色名称"), value: RGBAColor(hex: 0xE774BB)),
        // 浅色
        .init(key: "lightGreen", name: String(localized: "浅绿", comment: "颜色名称"), value: RGBAColor(hex: 0xBAF3DB)),
        .init(key: "lightYellow", name: String(localized: "浅黄", comment: "颜色名称"), value: RGBAColor(hex: 0xF8E6A0)),
        .init(key: "lightOrange", name: String(localized: "浅橙", comment: "颜色名称"), value: RGBAColor(hex: 0xFEDEC8)),
        .init(key: "lightRed", name: String(localized: "浅红", comment: "颜色名称"), value: RGBAColor(hex: 0xFFD5D2)),
        .init(key: "lightPurple", name: String(localized: "浅紫", comment: "颜色名称"), value: RGBAColor(hex: 0xDFD8FD)),
        .init(key: "lightBlue", name: String(localized: "浅蓝", comment: "颜色名称"), value: RGBAColor(hex: 0xCCE0FF)),
        .init(key: "lightGray", name: String(localized: "浅灰", comment: "颜色名称"), value: RGBAColor(hex: 0xEBECF0)),
        .init(key: "white", name: String(localized: "白", comment: "颜色名称"), value: RGBAColor(hex: 0xFFFFFF)),
        // 深色
        .init(key: "darkGreen", name: String(localized: "深绿", comment: "颜色名称"), value: RGBAColor(hex: 0x1F845A)),
        .init(key: "darkYellow", name: String(localized: "深黄", comment: "颜色名称"), value: RGBAColor(hex: 0x946F00)),
        .init(key: "darkOrange", name: String(localized: "深橙", comment: "颜色名称"), value: RGBAColor(hex: 0xC25100)),
        .init(key: "darkRed", name: String(localized: "深红", comment: "颜色名称"), value: RGBAColor(hex: 0xC9372C)),
        .init(key: "darkPurple", name: String(localized: "深紫", comment: "颜色名称"), value: RGBAColor(hex: 0x6E5DC6)),
        .init(key: "darkBlue", name: String(localized: "深蓝", comment: "颜色名称"), value: RGBAColor(hex: 0x0C66E4)),
        .init(key: "gray", name: String(localized: "灰", comment: "颜色名称"), value: RGBAColor(hex: 0x626F86)),
        .init(key: "navy", name: String(localized: "墨", comment: "颜色名称"), value: RGBAColor(hex: 0x172B4D)),
    ]

    static func name(for color: RGBAColor) -> String? {
        presets.first(where: { $0.value.isClose(to: color) })?.name
    }

    static func color(_ key: String) -> RGBAColor? {
        presets.first(where: { $0.key == key })?.value
    }
}

/// 预设色板 + 系统取色器
struct ColorSwatchPicker: View {
    @Binding var selection: RGBAColor?
    var allowsNone = true
    var noneHelp: LocalizedStringKey = "默认"

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
