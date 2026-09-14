import SwiftUI

struct HostSidebarView: View {
    @ObservedObject var hostStore: HostStore
    @ObservedObject var sessionManager: SessionManager
    @Binding var selectedHostID: UUID?
    var onConnect: (HostConfig) -> Void
    var onNewHost: () -> Void
    var onEdit: (HostConfig) -> Void

    @AppStorage("showHostSubtitle") private var showHostSubtitle = false
    @State private var hoveredHostID: UUID?
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        List(selection: $selectedHostID) {
            if hostStore.hosts.isEmpty {
                Section("主机") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("还没有保存的主机")
                        Text("点击左下角 + 新建连接")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
                }
            } else if hostStore.groupNames == [""] {
                // 一个分组都没设置时，不显示分组节
                Section("主机") {
                    ForEach(hostStore.hosts) { host in
                        row(host)
                            .tag(host.id)
                            .contextMenu {
                                Button("连接") { onConnect(host) }
                                Button("编辑…") { onEdit(host) }
                                Button(showHostSubtitle ? "隐藏主机地址" : "显示主机地址") {
                                    showHostSubtitle.toggle()
                                }
                                Divider()
                                Button("删除", role: .destructive) { hostStore.remove(host) }
                            }
                    }
                }
            } else {
                ForEach(hostStore.groupNames, id: \.self) { group in
                    let hostsInGroup = hostStore.hosts(inGroup: group)
                    Section {
                        if !collapsedGroups.contains(group) {
                            ForEach(hostsInGroup) { host in
                                row(host)
                                    .tag(host.id)
                                    .contextMenu {
                                        Button("连接") { onConnect(host) }
                                        Button("编辑…") { onEdit(host) }
                                        Button(showHostSubtitle ? "隐藏主机地址" : "显示主机地址") {
                                            showHostSubtitle.toggle()
                                        }
                                        Divider()
                                        Button("删除", role: .destructive) { hostStore.remove(host) }
                                    }
                            }
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                Button(action: onNewHost) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .help("新建主机连接")

                Button {
                    sessionManager.newLocalShell()
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 13))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("新建本地终端")

                Spacer(minLength: 8)

                Button {
                    showHostSubtitle.toggle()
                } label: {
                    Image(systemName: showHostSubtitle ? "caption.1.bottom" : "caption.0.bottom")
                        .font(.system(size: 12))
                        .foregroundColor(showHostSubtitle ? .accentColor : .secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .help(showHostSubtitle ? "隐藏主机地址" : "显示主机地址")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - 分组节头（点击折叠/展开）

    private func groupHeader(_ group: String) -> some View {
        let isCollapsed = collapsedGroups.contains(group)
        return HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            Text(group.isEmpty ? "未分组" : group)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCollapsed {
                collapsedGroups.remove(group)
            } else {
                collapsedGroups.insert(group)
            }
        }
    }

    // MARK: - 主机行

    @ViewBuilder
    private func row(_ host: HostConfig) -> some View {
        let isHovered = hoveredHostID == host.id
        let state = sessionManager.stateFor(host)

        HStack(spacing: 8) {
            Circle()
                .fill(HostSidebarView.stateColor(state))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(host.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if showHostSubtitle {
                    Text("\(host.username)@\(host.host)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredHostID = host.id
            } else if hoveredHostID == host.id {
                hoveredHostID = nil
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onConnect(host) }
        )
    }

    static func stateColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .closed: return .orange
        case .idle: return .gray
        }
    }
}
