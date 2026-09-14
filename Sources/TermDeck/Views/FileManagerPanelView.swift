import SwiftUI
import AppKit

struct FileManagerPanelView: View {
    @ObservedObject var browser: RemoteFileBrowser

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showRenameAlert = false
    @State private var renameValue = ""
    @State private var renameTarget: RemoteEntry?
    @State private var showDeleteConfirm = false
    @State private var showGoToAlert = false
    @State private var goToValue = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            TransferListView(browser: browser)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("新建文件夹", isPresented: $showNewFolderAlert) {
            TextField("名称", text: $newFolderName)
            Button("创建") {
                let name = newFolderName
                Task { await browser.createDirectory(named: name) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: $showRenameAlert) {
            TextField("新名称", text: $renameValue)
            Button("确定") {
                guard let target = renameTarget else { return }
                Task { await browser.rename(target, to: renameValue) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "确认删除",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除 \(browser.selectedEntries.count) 项", role: .destructive) {
                let targets = browser.selectedEntries
                Task { await browser.delete(targets) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，确认继续？")
        }
        .alert("前往文件夹", isPresented: $showGoToAlert) {
            TextField("输入路径", text: $goToValue)
            Button("前往", action: submitGoTo)
            Button("取消", role: .cancel) {}
        } message: {
            Text("支持绝对路径（/var/log）、主目录（~/code）或相对当前目录的路径；输入文件时将打开其所在目录")
        }
    }

    private func submitGoTo() {
        showGoToAlert = false
        let target = goToValue
        Task { await browser.goToPath(target) }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(.accentColor)
                Text("远程文件")
                    .font(.headline)
                if let title = browser.sessionTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { browser.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!browser.canBrowse)
                .help("刷新")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            pathBar
            Divider()

            // 图标按钮使用收窄的点击区（见 PanelIconButtonStyle）：
            // 系统样式的按钮最小点击区约 28pt，8 个排一行需要 ~325pt，
            // 面板窄于此宽度时 HStack 会居中溢出，导致首个图标贴到面板左边缘。
            HStack(spacing: 10) {
                Button(action: { browser.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse || browser.path.count <= 1)
                .help("上一级")

                Button {
                    Task { await browser.goHome() }
                } label: {
                    Image(systemName: "house")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse)
                .help("主目录")

                Button {
                    goToValue = browser.path
                    showGoToAlert = true
                } label: {
                    Image(systemName: "arrow.forward.circle")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("前往文件夹（⌘⇧G）")

                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse)
                .help("新建文件夹")

                Button(action: pickUploadFiles) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse || browser.busy)
                .help("上传文件到当前目录")

                Button(action: downloadSelection) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse || browser.selectedEntries.isEmpty)
                .help("下载选中项")

                Button(action: renameSelection) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse || browser.selectedEntries.count != 1)
                .help("重命名")

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.panelIcon)
                .disabled(!browser.canBrowse || browser.selectedEntries.isEmpty)
                .help("删除")

                Spacer(minLength: 8)
                if browser.busy {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Text("\(browser.entries.count) 项")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
        }
    }

    private var pathBar: some View {
        Group {
            if browser.state == .noSession {
                HStack {
                    Text("未连接远程主机")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button(action: { open("/") }) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)

                        let components = browser.path
                            .split(separator: "/", omittingEmptySubsequences: true)
                            .map(String.init)
                        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                            Button(component) {
                                let prefix = "/" + components[0...index].joined(separator: "/")
                                open(prefix)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch browser.state {
        case .noSession:
            VStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                Text("连接主机后，可以在这里浏览远程文件\n并上传 / 下载")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") { browser.refresh() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            List(selection: $browser.selectedNames) {
                ForEach(browser.entries) { entry in
                    row(entry)
                        .tag(entry.id)
                        .contextMenu { contextMenu(entry) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ entry: RemoteEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                .font(.system(size: 13))
                .foregroundColor(entry.isDirectory ? .blue : .secondary)
                .frame(width: 18)
            Text(entry.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .help(entry.name)
            Spacer()
            Text(entry.sizeText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .trailing)
            Text(entry.modifiedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 122, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { browser.enter(entry) })
    }

    @ViewBuilder
    private func contextMenu(_ entry: RemoteEntry) -> some View {
        if entry.isDirectory {
            Button("打开") { browser.enter(entry) }
            Divider()
        }
        Button("下载…") { browser.download([entry]) }
        Button("复制完整路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
        }
        Divider()
        Button("重命名…") {
            renameTarget = entry
            renameValue = entry.name
            showRenameAlert = true
        }
        Button("删除", role: .destructive) {
            browser.selectedNames = [entry.id]
            showDeleteConfirm = true
        }
    }

    // MARK: - 动作

    private func open(_ path: String) {
        Task { await browser.list(path: path) }
    }

    private func downloadSelection() {
        browser.download(browser.selectedEntries)
    }

    private func renameSelection() {
        guard let target = browser.selectedEntries.first else { return }
        renameTarget = target
        renameValue = target.name
        showRenameAlert = true
    }

    private func pickUploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "选择要上传到 \(browser.path) 的文件"
        panel.begin { response in
            guard response == .OK else { return }
            browser.upload(localURLs: panel.urls)
        }
    }
}

// MARK: - 图标按钮样式

/// 面板工具栏的图标按钮：把点击区收窄到图标本身宽度。
///
/// 系统 .borderless 样式会给图标按钮 ~28pt 的最小点击区，一行 8 个就需要 ~325pt；
/// 面板窄于该宽度时 HStack 溢出并居中，首个图标就会被推到贴着面板左边缘。
/// 这里保持与 secondary 一致的配色，只压缩布局宽度，并把禁用态压得更淡以便区分。
struct PanelIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.45))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PanelIconButtonStyle {
    static var panelIcon: PanelIconButtonStyle { PanelIconButtonStyle() }
}

// MARK: - 传输列表

struct TransferListView: View {
    @ObservedObject var browser: RemoteFileBrowser

    var body: some View {
        if browser.transfers.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("传输")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("清除已完成") {
                        browser.clearFinishedTransfers()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(browser.transfers) { task in
                            TransferRow(task: task) {
                                browser.cancelTransfer(task.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 150)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}

private struct TransferRow: View {
    let task: TransferTask
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.direction == .upload
                ? "arrow.up.circle.fill"
                : "arrow.down.circle.fill")
                .foregroundColor(task.direction == .upload ? .orange : .green)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.fileName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    statusText
                }
                if task.state == .running {
                    ProgressView(value: task.fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }

            if task.state == .running {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("取消")
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch task.state {
        case .running:
            Text(task.progressText)
                .font(.caption2)
                .foregroundColor(.secondary)
        case .done:
            Text("完成")
                .font(.caption2)
                .foregroundColor(.green)
        case .cancelled:
            Text("已取消")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }
}
