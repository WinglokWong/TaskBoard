import SwiftUI

/// 统一的动画参数。开启“减弱动态效果”时，位置移动改为直接切换，只保留淡入淡出。
enum Motion {
    /// 卡片 / 列表移动、重新排序
    static let move = Animation.snappy(duration: 0.32, extraBounce: 0.02)
    /// 拖放时让出空位
    static let gap = Animation.spring(response: 0.26, dampingFraction: 0.86)
    /// 拖放落位：浮动副本从鼠标处滑入目标位置并落下
    static let settle = Animation.spring(response: 0.3, dampingFraction: 0.82)
    /// 悬停、选中等轻量状态
    static let quick = Animation.easeOut(duration: 0.15)

    static func move(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : move }
    static func gap(_ reduceMotion: Bool) -> Animation? { reduceMotion ? .easeOut(duration: 0.1) : gap }
    static func settle(_ reduceMotion: Bool) -> Animation { reduceMotion ? .easeOut(duration: 0.15) : settle }

    /// 卡片出现 / 消失
    static func cardTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}
