import SwiftUI
import AppKit

enum BoardKey {
    case up, down, left, right, open, quickLook, toggleDone, archive, newCard, escape

    /// 将按键事件转换为看板快捷键；带 ⌘ / ⌃ / ⌥ 的组合键不处理
    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty else { return nil }
        switch event.keyCode {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 36, 76: self = .open
        case 49: self = .quickLook
        case 51, 117: self = .archive
        case 53: self = .escape
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n": self = .newCard
            case "d": self = .toggleDone
            default: return nil
            }
        }
    }
}

/// 监听主窗口的按键。正在输入文字、或有表单 / 弹出窗口 / Quick Look 时不拦截。
final class KeyMonitor {
    private var token: Any?

    func start(_ handler: @escaping (BoardKey) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = NSApp.keyWindow,
                  window.attachedSheet == nil,
                  window.sheetParent == nil,
                  !(window is NSPanel),
                  !String(describing: type(of: window)).contains("Popover"),
                  !(window.firstResponder is NSText),
                  let key = BoardKey(event: event)
            else { return event }
            return handler(key) ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit { stop() }
}

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(String, String)] = [
        ("↑ ↓ ← →", "在卡片之间移动选择"),
        ("鼠标悬停", "选中卡片"),
        ("Return", "打开选中的卡片"),
        ("Space", "用 Quick Look 预览卡片附件"),
        ("D", "标记完成 / 未完成"),
        ("Delete", "归档选中的卡片"),
        ("N", "在当前列表添加卡片"),
        ("Esc", "取消选择"),
        ("⌘Z / ⇧⌘Z", "撤销 / 重做"),
        ("⇧⌘N", "新建看板"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("键盘快捷键", systemImage: "keyboard")
                .font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(rows, id: \.0) { key, action in
                    GridRow {
                        Text(key)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                        Text(action)
                    }
                }
            }
            Text("在看板上（没有正在输入文字时）可用。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("好") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
