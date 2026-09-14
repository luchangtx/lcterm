import Foundation
import AppKit
import Citadel
import NIOCore

struct RemoteEntry: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    let permissions: UInt32?

    var sizeText: String {
        isDirectory ? "文件夹" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var modifiedText: String {
        guard let modified else { return "—" }
        return RemoteFileBrowser.timeFormatter.string(from: modified)
    }
}

struct TransferTask: Identifiable, Equatable {
    enum Direction: String {
        case upload, download
    }

    enum State: Equatable {
        case running
        case done
        case failed(String)
        case cancelled
    }

    let id: UUID
    let direction: Direction
    let fileName: String
    var total: Int64 = 0
    var done: Int64 = 0
    var state: State = .running

    var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }

    var progressText: String {
        ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
    }
}

enum PanelState: Equatable {
    case noSession
    case loading
    case loaded
    case error(String)
}

struct TransferCancelled: LocalizedError {
    var errorDescription: String? { "已取消" }
}

/// 远程文件浏览器（SFTP）：每个 SSHSession 拥有一个实例
@MainActor
final class RemoteFileBrowser: ObservableObject {
    @Published private(set) var state: PanelState = .noSession
    @Published private(set) var path: String = ""
    @Published private(set) var entries: [RemoteEntry] = []
    @Published var selectedNames: Set<String> = []
    @Published private(set) var transfers: [TransferTask] = []
    @Published private(set) var busy = false

    private weak var session: SSHSession?
    private var cancelRequests = Set<UUID>()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var canBrowse: Bool {
        switch state {
        case .loaded, .error: return true
        default: return false
        }
    }
    var selectedEntries: [RemoteEntry] {
        entries.filter { selectedNames.contains($0.id) }
    }
    var sessionTitle: String? { session?.title }

    func bind(session: SSHSession?) {
        self.session = session
        selectedNames = []
        entries = []
        transfers = []
        if session == nil {
            path = ""
            state = .noSession
        }
    }

    /// SSH 连接建立、SFTP 可用后调用
    func markAvailable() {
        Task { await goHome() }
    }

    // MARK: - 导航

    func goHome() async {
        guard let sftp = session?.sftpClient else {
            state = .noSession
            return
        }
        do {
            let home = try await sftp.getRealPath(atPath: ".")
            await list(path: home)
        } catch {
            await list(path: path.isEmpty ? "/" : path)
        }
    }

    func list(path target: String) async {
        guard let sftp = session?.sftpClient else {
            state = .noSession
            return
        }
        state = .loading
        do {
            let names = try await sftp.listDirectory(atPath: target)
            var result: [RemoteEntry] = []
            for name in names {
                for component in name.components {
                    let fileName = component.filename
                    guard fileName != ".", fileName != ".." else { continue }
                    result.append(RemoteEntry(
                        path: join(target, fileName),
                        name: fileName,
                        isDirectory: Self.isDirectory(component),
                        size: Int64(component.attributes.size ?? 0),
                        modified: component.attributes.accessModificationTime?.modificationTime,
                        permissions: component.attributes.permissions
                    ))
                }
            }
            entries = result.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            path = target
            selectedNames = []
            state = .loaded
        } catch {
            state = .error("获取目录失败：\(SSHError.describe(error))")
        }
    }

    func goUp() {
        guard path.count > 1 else { return }
        let parent = (path as NSString).deletingLastPathComponent
        Task { await list(path: parent.isEmpty ? "/" : parent) }
    }

    /// 按输入路径跳转：支持 ~ 前缀、相对当前目录的路径与 "."/".."；
    /// 若指向文件则跳转到其所在目录并选中该文件
    func goToPath(_ raw: String) async {
        guard session?.sftpClient != nil else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var input = trimmed
        if input.hasPrefix("~/") || input == "~" {
            let home = try? await session?.sftpClient?.getRealPath(atPath: ".")
            guard let home, !home.isEmpty else {
                state = .error("无法解析主目录，请直接输入绝对路径")
                return
            }
            input = home + input.dropFirst(1)
        }
        if !input.hasPrefix("/") {
            input = (path.isEmpty ? "/" : path) + "/" + input
        }
        // 规范化：折叠 . / .. / 多余斜杠
        let comps = input.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [String] = []
        for c in comps {
            switch c {
            case ".": continue
            case "..": if !stack.isEmpty { stack.removeLast() }
            default: stack.append(String(c))
            }
        }
        let target = "/" + stack.joined(separator: "/")
        await list(path: target)
        // 跳转失败时可能是文件：进入其父目录并选中
        if case .error = state, stack.count > 1 {
            let fileName = stack.removeLast()
            let parent = "/" + stack.joined(separator: "/")
            await list(path: parent)
            if case .loaded = state {
                let filePath = join(parent, fileName)
                if entries.contains(where: { $0.path == filePath }) {
                    selectedNames = [filePath]
                }
            }
        }
    }

    func enter(_ entry: RemoteEntry) {
        guard entry.isDirectory else { return }
        Task { await list(path: entry.path) }
    }

    func refresh() {
        guard !path.isEmpty else { return }
        Task { await list(path: path) }
    }

    // MARK: - 目录操作

    func createDirectory(named name: String) async {
        guard let sftp = session?.sftpClient, !name.isEmpty else { return }
        do {
            try await sftp.createDirectory(atPath: join(path, name))
            await list(path: path)
        } catch {
            state = .error("新建文件夹失败：\(SSHError.describe(error))")
        }
    }

    func rename(_ entry: RemoteEntry, to newName: String) async {
        guard let sftp = session?.sftpClient, !newName.isEmpty else { return }
        do {
            try await sftp.rename(at: entry.path, to: join(path, newName))
            await list(path: path)
        } catch {
            state = .error("重命名失败：\(SSHError.describe(error))")
        }
    }

    func delete(_ targets: [RemoteEntry]) async {
        guard let sftp = session?.sftpClient, !targets.isEmpty else { return }
        busy = true
        defer { busy = false }
        for target in targets {
            do {
                try await removeRecursive(target)
            } catch {
                state = .error("删除失败：\(SSHError.describe(error))")
                await list(path: path)
                return
            }
        }
        await list(path: path)
    }

    private func removeRecursive(_ entry: RemoteEntry) async throws {
        guard let sftp = session?.sftpClient else { return }
        if entry.isDirectory {
            let children = try await sftp.listDirectory(atPath: entry.path)
            for name in children {
                for component in name.components {
                    let fileName = component.filename
                    guard fileName != ".", fileName != ".." else { continue }
                    try await removeRecursive(RemoteEntry(
                        path: join(entry.path, fileName),
                        name: fileName,
                        isDirectory: Self.isDirectory(component),
                        size: Int64(component.attributes.size ?? 0),
                        modified: nil,
                        permissions: nil
                    ))
                }
            }
            try await sftp.rmdir(at: entry.path)
        } else {
            try await sftp.remove(at: entry.path)
        }
    }

    // MARK: - 上传 / 下载

    func upload(localURLs: [URL]) {
        guard !localURLs.isEmpty else { return }
        Task { await performUploads(localURLs) }
    }

    private func performUploads(_ urls: [URL]) async {
        guard let sftp = session?.sftpClient else { return }
        busy = true
        defer { busy = false }
        for url in urls {
            let fileName = url.lastPathComponent
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let total = (attributes?[.size] as? Int64) ?? 0
            let taskID = UUID()
            transfers.append(TransferTask(id: taskID, direction: .upload, fileName: fileName, total: total))
            do {
                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }
                let remoteFile = try await sftp.openFile(
                    filePath: join(path, fileName),
                    flags: [.write, .create, .truncate]
                )
                do {
                    var offset: UInt64 = 0
                    while true {
                        if cancelRequests.contains(taskID) { throw TransferCancelled() }
                        let data = fileHandle.readData(ofLength: 256 * 1024)
                        if data.isEmpty { break }
                        try await remoteFile.write(ByteBuffer(bytes: data), at: offset)
                        offset += UInt64(data.count)
                        updateTransfer(id: taskID) { $0.done = Int64(offset) }
                    }
                    try await remoteFile.close()
                    updateTransfer(id: taskID) {
                        $0.state = .done
                        $0.done = max($0.done, total)
                    }
                } catch {
                    try? await remoteFile.close()
                    throw error
                }
            } catch is TransferCancelled {
                updateTransfer(id: taskID) { $0.state = .cancelled }
            } catch {
                updateTransfer(id: taskID) { $0.state = .failed(SSHError.describe(error)) }
            }
        }
        cancelRequests.removeAll()
        await list(path: path)
    }

    func download(_ targets: [RemoteEntry]) {
        guard !targets.isEmpty, session?.sftpClient != nil else { return }
        if targets.count == 1, let entry = targets.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = entry.name
            panel.canCreateDirectories = true
            panel.message = "选择保存位置"
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                Task { await self?.performDownload(entry: entry, to: url) }
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "下载到此处"
            panel.message = "选择保存文件夹（共 \(targets.count) 项）"
            panel.begin { [weak self] response in
                guard response == .OK, let dir = panel.url else { return }
                Task {
                    for entry in targets {
                        await self?.performDownload(entry: entry, to: dir.appendingPathComponent(entry.name))
                    }
                }
            }
        }
    }

    private func performDownload(entry: RemoteEntry, to localURL: URL) async {
        guard let sftp = session?.sftpClient else { return }
        busy = true
        defer { busy = false }
        let taskID = UUID()
        transfers.append(TransferTask(id: taskID, direction: .download, fileName: entry.name, total: entry.size))
        do {
            guard FileManager.default.createFile(atPath: localURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let fileHandle = try FileHandle(forWritingTo: localURL)
            defer { try? fileHandle.close() }
            let remoteFile = try await sftp.openFile(filePath: entry.path, flags: [.read])
            do {
                var offset: UInt64 = 0
                while true {
                    if cancelRequests.contains(taskID) { throw TransferCancelled() }
                    let buffer = try await remoteFile.read(from: offset, length: 256 * 1024)
                    let data = Data(buffer.readableBytesView)
                    if data.isEmpty { break }
                    try fileHandle.write(contentsOf: data)
                    offset += UInt64(data.count)
                    updateTransfer(id: taskID) {
                        $0.done = Int64(offset)
                        if $0.total < $0.done { $0.total = $0.done }
                    }
                }
                try await remoteFile.close()
                updateTransfer(id: taskID) { $0.state = .done }
            } catch {
                try? await remoteFile.close()
                throw error
            }
        } catch is TransferCancelled {
            try? FileManager.default.removeItem(at: localURL)
            updateTransfer(id: taskID) { $0.state = .cancelled }
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            updateTransfer(id: taskID) { $0.state = .failed(SSHError.describe(error)) }
        }
    }

    func cancelTransfer(_ id: UUID) {
        cancelRequests.insert(id)
    }

    func clearFinishedTransfers() {
        transfers.removeAll { $0.state != .running }
    }

    // MARK: - 工具

    private func updateTransfer(id: UUID, _ mutate: (inout TransferTask) -> Void) {
        if let index = transfers.firstIndex(where: { $0.id == id }) {
            mutate(&transfers[index])
        }
    }

    private func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }

    nonisolated static func isDirectory(_ component: SFTPPathComponent) -> Bool {
        if let permissions = component.attributes.permissions {
            return (permissions & 0o170000) == 0o040000
        }
        return component.longname.hasPrefix("d")
    }
}
