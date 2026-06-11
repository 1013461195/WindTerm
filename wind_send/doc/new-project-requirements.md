# Flutter + Rust SSH 工具需求与里程碑

## 项目目标

重写一个跨平台 SSH/终端工具，吸收 WindTerm 的产品逻辑，但避免继承其停止维护后的安全与架构风险。

核心目标：

- Flutter 做跨平台 UI、会话编排、设置、文件管理、交互体验。
- Rust 做协议、PTY、终端解析、SFTP、重连、加密与平台适配。
- 不依赖系统 `ssh`/`sftp` 命令作为核心链路。
- 优先保证安全、稳定、可测试，再逐步补齐高级体验。

目标平台：

- 第一优先级：macOS、Windows、Linux 桌面。
- 第二优先级：iPadOS/Android 平板，受限于本地 PTY、文件系统、后台连接能力，需要单独评估。

## 非目标

- 第一版不追求完整复刻 WindTerm 全部功能。
- 第一版不实现自研 SSH 协议栈，优先使用成熟 Rust/C 库。
- 第一版不实现 tmux 深度集成、ZModem、X11 forwarding、ControlMaster、动态内存压缩。
- 不把敏感凭据明文保存在配置文件。

## 用户画像

- DevOps/SRE：需要多 SSH 会话、跳板、SFTP、日志、稳定重连。
- 后端/全栈开发：需要本地 shell、远程 shell、端口转发、快捷命令。
- 网络/嵌入式工程师：后续需要 Telnet、Serial、Raw TCP。

## 阶段划分

### Phase 0: 技术预研

目标：验证 Flutter + Rust 架构能跑通，不做完整产品。

交付：

- Flutter 桌面空壳。
- Rust core 动态库或静态库。
- Dart 通过 FFI 调用 Rust。
- Rust 启动一个本地 mock terminal session，持续推送文本事件到 Flutter。
- Flutter 使用 `CustomPainter` 或初步终端组件绘制固定宽度字符。

验收：

- macOS/Windows/Linux 至少两个平台可运行。
- FFI 双向调用稳定。
- Rust 后台线程向 Flutter 推事件不卡 UI。

### Phase 1: MVP 远程 SSH 终端

目标：完成最小可用 SSH 客户端。

功能：

- 新建 SSH session：host、port、username。
- 密码登录。
- 私钥登录，支持 passphrase。
- known_hosts 校验：OK、UNKNOWN、CHANGED、OTHER、NOT_FOUND。
- 打开远程 PTY shell。
- 基础终端渲染：ASCII、UTF-8、SGR 颜色、光标移动、清屏、换行。
- 基础键盘输入：字符、Enter、Backspace、Tab、方向键、Ctrl+C、Ctrl+D。
- 窗口 resize 同步到远程 PTY。
- 手动断开、手动重连。
- 连接超时、认证错误、host key 变更错误提示。
- session profile 本地保存，但不保存明文密码。

验收：

- 可以连接常见 OpenSSH server。
- 可以运行 `vim`、`top`、`htop`、`less` 的基础交互。
- known_hosts changed 时默认阻止连接。
- resize 后远端 `stty size` 与窗口一致。

### Phase 2: 本地 Shell 与终端增强

目标：让工具成为日常终端。

功能：

- 本地 shell：macOS/Linux 使用 PTY，Windows 使用 ConPTY。
- Tab、多 session。
- 分屏。
- 复制/粘贴、选区、右键菜单。
- 搜索当前终端缓冲。
- scrollback。
- 256 色、true-color。
- Unicode 宽字符、中文、emoji、combining mark。
- 鼠标协议。
- 配色方案、字体、字号、行高。

验收：

- 本地 shell 与远程 SSH 共享同一终端渲染核心。
- `vttest` 基础项通过率达到可用水平。
- 中文/emoji 不破坏光标列位置。
- 大量输出不卡 UI，滚动稳定。

### Phase 3: SFTP 与文件管理

目标：补齐 DevOps 高频文件操作。

功能：

- SFTP 连接复用当前 SSH session，或独立建立 SFTP session。
- 远程目录浏览。
- 上传、下载、删除、重命名、新建文件/目录。
- 本地文件管理面板。
- 传输队列、进度、速度、取消、失败重试。
- 权限与时间戳显示。
- 大文件分块传输。

验收：

- 10GB 单文件上传/下载不中断。
- 递归目录上传/下载可恢复失败项。
- 权限不足、磁盘满、连接断开时错误可读。

### Phase 4: 会话管理与生产力

目标：接近 WindTerm 的核心工作流。

功能：

- session tree、文件夹、标签。
- 快速打开、命令面板。
- 自动登录策略。
- 启动恢复上次 tabs/layout。
- 手动/自动 session logging。
- 快捷命令、Command sender。
- 多 pane 同步输入。
- Paste dialog，支持慢速粘贴和确认。
- 主题、tab color、窗口透明。

验收：

- 用户可管理上百个 session。
- 恢复布局不会误自动执行敏感命令。
- 日志可按 session/日期归档。

### Phase 5: 网络高级能力

目标：覆盖复杂企业网络环境。

功能：

- ProxyCommand。
- ProxyJump / jump server。
- HTTP proxy、SOCKS5 proxy。
- 本地端口转发。
- 远程端口转发。
- 动态端口转发。
- SSH agent 与 agent forwarding。
- keepalive 配置、自动重连策略。

验收：

- 多跳 SSH 可以稳定连接。
- 端口转发能显示状态、流量、错误。
- 自动重连不会在认证失败或 host key 变化时盲目重试。

### Phase 6: Telnet / Serial / Raw TCP

目标：覆盖网络设备、串口设备和裸 TCP 场景。

功能：

- Telnet IAC parser。
- Telnet NAWS、TTYPE、ECHO、SGA、BINARY。
- Raw TCP session。
- Serial port 枚举、baud rate、data bits、parity、stop bits、flow control。
- 会话编码配置。
- Telnet/Serial 专用换行策略。

验收：

- 常见网络设备 Telnet 可登录。
- 串口日志输出稳定，断开设备能提示。
- resize 对 Telnet NAWS 生效。

### Phase 7: 安全加固与发布

目标：从可用走向可信。

功能：

- 凭据加密存储与平台 keychain 集成。
- 主密码模式。
- host key pinning。
- 安全审计日志。
- 依赖漏洞扫描。
- 自动更新与签名。
- 崩溃报告脱敏。

验收：

- 通过基础威胁建模检查。
- 敏感数据不会出现在日志、crash dump、普通配置文件。
- 所有第三方依赖有 license 与漏洞清单。

## 里程碑建议

| 里程碑 | 建议周期 | 结果 |
| --- | --- | --- |
| M0 | 1-2 周 | Flutter/Rust/FFI 技术闭环 |
| M1 | 3-5 周 | SSH MVP 可登录可交互 |
| M2 | 4-6 周 | 本地 shell + 终端增强可日用 |
| M3 | 3-5 周 | SFTP 文件管理可用 |
| M4 | 4-8 周 | 会话管理与生产力功能 |
| M5 | 4-8 周 | 代理、跳板、端口转发 |
| M6 | 3-6 周 | Telnet/Serial/Raw TCP |
| M7 | 持续 | 安全加固、测试、发布 |

