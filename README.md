# TermDeck

macOS 原生（SwiftUI + SwiftTerm + Citadel）SSH 终端工具（需要 macOS 15+）：

- **本地终端**：多标签本地 zsh，基于 SwiftTerm 完整终端模拟（vim / htop 等全屏程序可用）
- **SSH 登录**：密码 / 私钥（OpenSSH 格式 Ed25519、RSA）两种认证，PTY 交互式 shell
- **远程文件管理**：SFTP 浏览目录、上传下载（带进度条、可取消）、新建文件夹、重命名、删除（递归）
- **主机管理**：保存主机列表，密码/私钥口令存入 macOS 钥匙串（Keychain），双击即连
- **主题**：明亮 / 暗黑 / 跟随系统，终端配色同步切换

## 布局

左侧主机列表 | 中间终端（多标签，本地 + SSH 混排）| 右侧远程文件面板（可折叠）

## 构建与运行

依赖：macOS 15+，Xcode Command Line Tools，Swift 5.10+。首次构建会自动拉取依赖，网络受限时请自行设置 HTTP 代理环境变量。

```bash
# 开发运行
swift run

# 打包成 .app
./make_app.sh          # release 构建
open build/TermDeck.app
```

## 使用

1. 左下角 **+** 新建主机连接（名称/主机/端口/用户名 + 密码或私钥），勾选"记住密码"后下次一键直连
2. 左下角 **终端图标** 或 ⌘T 新建本地终端
3. 连接成功后右侧文件面板自动加载远程主目录：
   - ⬆︎ 上传：选择本地文件传到当前远程目录
   - ⬇︎ 下载：选中文件后下载（单文件弹保存框，多文件选目标文件夹）
   - 双击进入文件夹，右键更多操作（下载/重命名/删除/复制路径）
4. 右上角切换明亮/暗黑主题，侧栏按钮折叠文件面板

## 目录结构

```
Sources/TermDeck/
├── TermDeckApp.swift        # App 入口
├── Appearance.swift         # 主题
├── Models/HostConfig.swift  # 主机配置模型
├── Services/
│   ├── SSHSession.swift     # SSH 连接 + PTY 流 + 认证
│   ├── RemoteFileBrowser.swift # SFTP 浏览/上传/下载/管理
│   ├── HostStore.swift      # 主机持久化
│   ├── KeychainStore.swift  # 钥匙串
│   └── Protected.swift      # 线程安全容器
├── Session/TerminalSession.swift # 标签页/会话管理 + SwiftTerm 桥接
└── Views/                   # SwiftUI 界面
```

## 已知限制

- 私钥目前支持 OpenSSH 格式的 Ed25519 与 RSA（`-----BEGIN OPENSSH PRIVATE KEY-----`）；PEM 老格式（PKCS#1 RSA）暂不支持
- 主机密钥采用 TOFU 策略（首次信任并记录指纹，之后不一致即拒绝连接，与 OpenSSH 首连行为一致）
- 上传下载为顺序传输（每会话串行），超大文件速度受 SFTP 单通道往返时延影响

## 安全说明

- **网络出站**：应用运行时只与你显式连接的 SSH 服务器通信（Citadel/swift-nio-ssh 协议栈），无任何遥测、统计、崩溃上报或第三方网络请求。全部依赖均为知名开源库（apple/swift-nio、apple/swift-crypto、SwiftTerm、Citadel 等），可自行审计。
- **凭据存储**：密码/私钥口令以 AES-256-GCM 加密存放于 `~/Library/Application Support/TermDeck/`（`secrets.json` + 独立密钥文件 `.secret-key`，均为 600 权限），已弃用钥匙串（避免反复弹授权框）。该加密防止偶然读取；对拥有本机磁盘完全访问权的攻击者不构成屏障，属桌面工具的常规安全级别。
- **主机地址**、密钥文件**路径**、分组以明文存于 `hosts.json`；私钥文件本体不被复制，只记录路径。
- **主机密钥校验**：TOFU——首次连接记录服务器指纹（`known-hosts.json`），之后指纹不一致将拒绝连接并提示；确认服务器合法变更后可在界面一键重新信任。
- **权限**：应用无沙箱外特权（无 entitlements）、不读通讯录/定位/相册等任何系统隐私数据。连接内网地址时 macOS 可能弹一次"本地网络"系统权限，与 TermDeck 无关，允许即可。

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源，可自由使用、修改、再分发及商用；保留版权声明与许可证副本，改动处请注明。
