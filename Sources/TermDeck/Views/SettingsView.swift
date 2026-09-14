import Foundation
import SwiftUI
import AppKit

/// 应用级设置：本地终端默认启动目录（空 = 用户主目录）；支持 ~ 前缀
enum AppSettings {
    static let localShellCwdKey = "localShellCwd"

    static var localShellCwd: String {
        get { UserDefaults.standard.string(forKey: localShellCwdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: localShellCwdKey) }
    }

    /// 解析为可直接传给 shell 的绝对路径；无效/不存在时回退主目录
    static func resolvedLocalShellCwd() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = localShellCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return home }
        let path = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return home
        }
        return path
    }
}

/// 设置页（工具栏齿轮 / ⌘, 打开）
struct SettingsView: View {
    @State private var cwd = AppSettings.localShellCwd
    @State private var showConfirm = false
    @State private var confirmMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地终端启动目录")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("留空 = 主目录，支持 ~", text: $cwd, prompt: Text("~/projects 或 /var/log"))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 260)
                Button("浏览…", action: browse)
                    .controlSize(.small)
            }
            Text("新打开的本地终端标签将从该目录启动；留空或目录无效时回退主目录。SSH 远程会话的启动目录由远端登录 shell 决定。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("恢复默认（主目录）") { cwd = "" }
                    .controlSize(.small)
                Spacer()
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 420)
        .confirmationDialog(confirmMessage, isPresented: $showConfirm) {
            Button("仍然使用", role: .destructive, action: commit)
            Button("取消", role: .cancel) {}
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "选择启动目录"
        panel.message = "新打开的本地终端将进入此目录"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            // 主目录内路径转成 ~ 形式，更短更直观
            if url.path.hasPrefix(home + "/") {
                cwd = "~" + url.path.dropFirst(home.count)
            } else {
                cwd = url.path
            }
        }
    }

    private func save() {
        let raw = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            let path = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue {
                confirmMessage = "目录 \(path) 不存在（或不是文件夹），保存后将回退主目录。仍然使用？"
                showConfirm = true
                return
            }
        }
        commit()
    }

    private func commit() {
        AppSettings.localShellCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        ToastCenter.shared.show("已保存，新打开的本地终端生效")
    }
}

/// 轻量 toast（AppKit 层，避免各视图重复实现）
final class ToastCenter {
    static let shared = ToastCenter()

    func show(_ message: String) {
        DispatchQueue.main.async {
            guard let screen = NSScreen.main else { return }
            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.sizeToFit()
            let padding: CGFloat = 14
            let width = label.frame.width + padding * 2
            let height = label.frame.height + 16
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = height / 2
            label.frame.origin = NSPoint(x: padding, y: 8)
            background.addSubview(label)
            panel.contentView = background
            let x = screen.frame.midX - width / 2
            let y = screen.frame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                panel.close()
            }
        }
    }
}
