import AppKit
import ObjectiveC
import SwiftTerm

/// 清屏 action 的独立 target。
/// 必须脱离 TerminalView 本身作为 target：
/// TerminalView.validateUserInterfaceItem 对未知 selector 一律返回 false，
/// 若 target 是视图，自定义"清屏"项会被自动禁用。
final class ClearScreenHandler: NSObject {
    let onClear: () -> Void

    init(onClear: @escaping () -> Void) {
        self.onClear = onClear
    }

    @objc func clearScreen(_ sender: Any?) { onClear() }
}

private var clearHandlerKey: UInt8 = 0

private func clearHandler(for view: TerminalView) -> ClearScreenHandler {
    if let existing = objc_getAssociatedObject(view, &clearHandlerKey) as? ClearScreenHandler {
        return existing
    }
    let handler = ClearScreenHandler { [weak view] in
        (view as? MenuedTerminalView)?.onClearScreen?()
        (view as? MenuedLocalTerminalView)?.onClearScreen?()
    }
    objc_setAssociatedObject(view, &clearHandlerKey, handler, .OBJC_ASSOCIATION_RETAIN)
    return handler
}

/// 右键菜单：复制 / 粘贴 / 全选 / 清屏
/// - 复制粘贴全选 target 走 responder chain，可用性由 TerminalView.validateUserInterfaceItem 控制
/// - 清屏 target 为视图关联的 ClearScreenHandler，避免被上述校验默认禁用
private func buildTerminalMenu(view: TerminalView) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    menu.addItem(.separator())
    let clearItem = menu.addItem(withTitle: "清屏", action: #selector(ClearScreenHandler.clearScreen(_:)), keyEquivalent: "")
    clearItem.target = clearHandler(for: view)
    return menu
}

extension TerminalView {
    /// 隐藏 SwiftTerm 自带的滚动条。
    ///
    /// SwiftTerm 把一条 NSScroller 作为常驻子视图贴在终端右边缘，且不像 NSScrollView
    /// 那样会自动收起；没有滚动缓冲时滑块占满整条轨道，视觉上就是终端右侧一条竖线。
    /// 隐藏后滚轮 / 触控板回溯历史仍然可用，且 SwiftTerm 的 reservedScrollerWidth
    /// 会返回 0，把这段宽度还给终端网格。
    func hideBuiltInScroller() {
        subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }
}

/// SSH 终端视图：带右键菜单
final class MenuedTerminalView: TerminalView {
    /// 注入的清屏动作（如向 PTY 发送 Ctrl-L）
    var onClearScreen: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        buildTerminalMenu(view: self)
    }
}

/// 本地终端视图：带右键菜单
final class MenuedLocalTerminalView: LocalProcessTerminalView {
    /// 注入的清屏动作（如向 PTY 发送 Ctrl-L）
    var onClearScreen: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        buildTerminalMenu(view: self)
    }
}
