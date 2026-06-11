# Flutter UI 与 Rust Core 技术选型

本文作为新项目的架构技术选型文档，回答三个问题：

- Flutter UI 侧用什么技术栈构建桌面级 SSH 工具。
- Rust 底层用什么库实现 SSH、PTY、终端解析、SFTP、Serial 等核心能力。
- Flutter 如何调用 Rust，Rust 如何把终端输出、认证请求、SFTP 进度等事件回推给 Flutter。

## 架构结论

推荐主线：

```text
Flutter Desktop App
  - UI / Tab / Split Pane / Session Tree / Settings / SFTP Panel
  - Riverpod state
  - Drift local database
  - CustomPainter terminal viewport
  - flutter_rust_bridge generated bindings

Rust Core
  - Session actor model
  - ssh2/libssh2 for MVP SSH/SFTP
  - portable-pty for local shell
  - alacritty_terminal or vte + custom grid for terminal parser
  - serialport for Serial
  - tokio for async runtime
  - platform keychain adapter for secrets
```

核心边界：

- Flutter 不实现 SSH 协议。
- Flutter 不解析复杂 ANSI/VT 状态机。
- Flutter 负责绘制 terminal grid、处理 UI 焦点/快捷键/布局。
- Rust 负责把协议字节变成 terminal cell，把 Flutter 输入变成协议写入。

## Flutter UI 技术选型

### 基础框架

| 能力 | 推荐 | 原因 |
| --- | --- | --- |
| UI 框架 | Flutter stable channel | 跨 macOS/Windows/Linux，桌面支持成熟，后续可扩展移动端。 |
| 状态管理 | Riverpod | 适合 session 列表、连接状态、设置、传输任务等异步状态。 |
| 路由 | go_router | 官方维护，适合设置页、连接管理页、日志页等可 URL 化页面。 |
| 本地数据库 | Drift + drift_flutter | SQLite 上层类型安全、迁移、响应式查询，适合 profile、history、layout、tasks。 |
| 数据模型 | freezed + json_serializable | 不可变模型、copyWith、序列化，适合 profile/event/settings。 |
| 桌面窗口 | window_manager | 窗口大小、位置、最大化、关闭确认、透明度等桌面能力。 |
| 键盘系统 | Focus / Shortcuts / Actions + HardwareKeyboard | 终端输入需要更底层事件，应用快捷键用 Actions/Shortcuts。 |

### Flutter 模块建议

```text
lib/
  app/
    app.dart
    router.dart
    theme.dart
  core_bridge/
    rust_api.dart
    rust_events.dart
    core_error.dart
  features/
    terminal/
      terminal_view.dart
      terminal_painter.dart
      terminal_input_controller.dart
      terminal_selection.dart
    sessions/
      session_tree.dart
      session_editor.dart
      session_controller.dart
    sftp/
      sftp_panel.dart
      transfer_queue.dart
    settings/
      settings_page.dart
    security/
      auth_prompt_dialog.dart
      host_key_dialog.dart
  data/
    db/
    models/
```

### 终端 UI 绘制

建议不要用普通 `Text` widget 一格一格画终端，性能和布局都会很痛。推荐：

- Phase 1：`CustomPainter` + `TextPainter` 按行绘制。
- Phase 2：缓存 glyph run、只重绘 dirty rows。
- Phase 3：如性能不够，评估 Flutter texture/native renderer，但先别过早复杂化。

Flutter terminal viewport 输入：

- 普通文本输入：走 Flutter text input/IME，提交为 text。
- 物理键：`HardwareKeyboard` 捕获方向键、Ctrl、Alt、功能键。
- 应用快捷键：用 `Shortcuts` / `Actions`，但终端获得焦点时要避免抢走 Ctrl+C、Ctrl+D、Tab 等远端输入。
- 鼠标：选区、本地右键菜单、远端 mouse protocol 需要分模式处理。

## Rust Core 技术选型

### SSH/SFTP 库

#### 推荐 MVP: `ssh2` crate + `libssh2`

理由：

- `ssh2` 是 libssh2 的 Rust binding，定位就是 SSH client。
- libssh2 支持 SSH v2、channel、PTY、shell、exec、SFTP、SCP、known_hosts、agent、keepalive、port forwarding 等常用客户端能力。
- 对 MVP 风险最低，尤其 SFTP 功能比较完整。

使用场景：

- Phase 1 SSH terminal。
- Phase 3 SFTP。
- Phase 5 local/reverse port forwarding、agent、keepalive。

风险：

- libssh2 是 C 库，需要处理 OpenSSL/LibreSSL、静态链接、平台打包。
- async 不是原生 Rust async，需要用阻塞线程或非阻塞 socket + poll 封装。
- 算法支持取决于 libssh2 与 crypto backend，需要验证目标服务器兼容性。

#### 备选: `russh`

理由：

- 纯 Rust，基于 tokio/futures 的 async SSH client/server。
- 架构更现代，和 Rust actor 模型更自然。

风险：

- 需要重点验证客户端功能完整度：known_hosts、agent、SFTP、ProxyJump、端口转发、算法覆盖、Windows/macOS/Linux 打包。
- 如果某些企业环境算法或认证方式缺失，MVP 会被卡住。

建议：

- M1-M3 用 `ssh2/libssh2` 确保能落地。
- 同时做一条 `russh` spike：连接、认证、PTY shell、resize、SFTP、known_hosts、agent。
- 等 spike 结论稳定后，再决定是否替换 SSH backend，或者保留可插拔 backend。

### 本地 PTY

推荐：`portable-pty`

理由：

- 提供跨平台 PTY API。
- macOS/Linux 使用系统 PTY。
- Windows 可走 ConPTY/winpty 相关实现。
- 该库来自 WezTerm 生态，适合终端类产品。

补充：

- 仍要做平台 adapter，因为本项目需要统一 resize、process exit、working directory、environment、shell discovery。
- Windows 需要明确最低版本策略：优先 ConPTY，不再支持太老系统时可以省掉 winpty fallback。

### 终端解析与屏幕模型

候选：

| 方案 | 优点 | 风险 |
| --- | --- | --- |
| `alacritty_terminal` | 成熟终端核心，含 parser/grid/pty 相关经验，性能强。 | API 主要服务 Alacritty 自身，嵌入成本和版本兼容要验证。 |
| `vte` + 自研 grid | parser 相对轻，边界可控。 | 自研 grid、scrollback、selection、wide char、alternate screen 工作量大。 |
| 全自研 parser/grid | 完全可控。 | 不推荐，VT/xterm 细节太多。 |

建议：

- Phase 0 做两个 spike：
  - `alacritty_terminal` 输出 dirty lines 给 Flutter。
  - `vte` parser + 最小 grid。
- 如果 `alacritty_terminal` 可控，优先它。
- 如果 API 嵌入太重，退回 `vte + custom grid`。

必须支持的终端能力：

- UTF-8 decoder。
- CSI/SGR 光标与颜色。
- 256 色、true-color。
- alternate screen。
- bracketed paste。
- mouse protocol。
- wide char / combining / emoji。
- scrollback。
- resize reflow 策略。

### Serial / Raw TCP / Telnet

| 能力 | 推荐库/方式 |
| --- | --- |
| Raw TCP | Rust `tokio::net::TcpStream` 或 `std::net::TcpStream`，取决于 session runtime。 |
| Telnet | 自研 Telnet IAC parser，接入 terminal engine。 |
| Serial | `serialport` crate。 |

Telnet 不建议找大而全依赖，IAC 协商状态机可控范围不大，结合 WindTerm 推导文档实现 NAWS/TTYPE/ECHO/SGA/BINARY 即可。

### Async Runtime 与 Actor

推荐：`tokio`

Rust core 结构：

```text
CoreRuntime
  - tokio runtime
  - EventBus
  - SessionRegistry
  - SecretStore
  - KnownHostsStore

SessionActor
  - command_rx
  - event_tx
  - transport
  - terminal_engine
  - reconnect_policy
```

每个 session 独立 actor：

- Flutter 发命令到 actor。
- actor 管理 SSH/PTTY/Telnet/SFTP 任务。
- actor 把 `CoreEvent` 推给 Flutter。
- terminal grid 由 actor 独占，避免跨线程锁。

## Flutter 与 Rust 交互方式

### 推荐: `flutter_rust_bridge`

理由：

- 生成 Dart/Rust 绑定，减少手写 FFI。
- 支持 async Rust。
- 支持 Rust 调 Dart 或事件流模式。
- 支持桌面与移动端，适合前期快速迭代。

使用方式：

```text
Flutter
  -> generated Dart API
  -> flutter_rust_bridge
  -> Rust public API
  -> CoreRuntime / SessionActor
```

建议约束：

- FFI API 保持粗粒度，不要每个 terminal cell 都跨 FFI 调一次。
- 终端更新只发 dirty ranges 或 snapshot handle。
- 大数据如 SFTP 文件内容不要经过 Dart，Rust 直接读写文件。
- 所有事件统一走 `Stream<CoreEvent>`。

### 备选: 手写 `dart:ffi` + C ABI

适合后期性能稳定后做局部替换：

- terminal snapshot 获取。
- 大量 cell buffer 读取。
- 零拷贝共享内存或外部 typed data。

不建议 Phase 0 就手写所有 FFI，初期会拖慢产品验证。

### Platform Channel 的位置

Platform Channel 只用于 Flutter 插件层无法避免的系统 UI 能力，例如：

- 原生文件选择器。
- 系统通知。
- keychain 插件如果选择 Dart 侧方案。

协议核心不要走 Platform Channel。

## FFI API 分层

### Command API

Flutter 调 Rust：

```text
core_init(config)
session_open(profile)
session_close(session_id)
session_resize(session_id, cols, rows)
session_send_key(session_id, key_event)
session_send_text(session_id, text)
session_paste(session_id, text, mode)
session_reconnect(session_id)
sftp_list(session_id, path)
sftp_upload(session_id, local_path, remote_path)
sftp_download(session_id, remote_path, local_path)
```

### Event API

Rust 推 Flutter：

```text
CoreEvent
- SessionStateChanged
- TerminalUpdated
- HostKeyVerificationRequired
- AuthPromptRequired
- SftpTaskProgress
- SftpTaskCompleted
- SftpTaskFailed
- LogMessage
- Error
```

### Snapshot API

Flutter 在收到 `TerminalUpdated` 后主动拉取当前 viewport：

```text
terminal_snapshot(session_id, first_row, row_count) -> TerminalSnapshot
```

避免 Rust 每次推全屏 cell。

## Rust Workspace 设计

建议：

```text
rust/
  Cargo.toml
  crates/
    core/
      src/
        runtime.rs
        event.rs
        error.rs
        session/
        terminal/
        security/
    bridge/
      src/
        api.rs
        frb_generated.rs
    ssh_backend/
      src/
        ssh2_backend.rs
        russh_backend.rs
    pty_backend/
    telnet/
    serial_backend/
    sftp/
```

依赖方向：

```text
bridge -> core
core -> ssh_backend / pty_backend / telnet / serial_backend / sftp
backend crates -> platform/system libraries
```

## SSH Backend 接口

抽象 trait：

```rust
trait SshBackend {
    fn connect(&mut self, config: SshConnectConfig) -> Result<HostKeyStatus>;
    fn verify_host_key(&mut self, decision: HostKeyDecision) -> Result<()>;
    fn authenticate(&mut self, auth: AuthRequest) -> Result<AuthStatus>;
    fn open_shell(&mut self, pty: PtyRequest) -> Result<Box<dyn RemoteShell>>;
    fn open_sftp(&mut self) -> Result<Box<dyn SftpClient>>;
    fn keepalive(&mut self) -> Result<KeepaliveStatus>;
}
```

这样可以先实现 `Ssh2Backend`，以后评估 `RusshBackend`。

## 关键技术风险

| 风险 | 缓解 |
| --- | --- |
| Flutter 终端绘制性能不足 | dirty rows、glyph cache、viewport snapshot、必要时 native texture。 |
| SSH 库算法不兼容 | 建测试矩阵：OpenSSH 新旧版本、企业服务器、弱算法禁用策略。 |
| FFI 事件过多 | 合并事件，帧节流，Flutter 主动拉 snapshot。 |
| Windows PTY 差异 | 优先 ConPTY，建立 Windows 专项测试。 |
| known_hosts/认证 UI 被远端输出混淆 | 安全对话框永远由 Flutter 原生 UI 展示，不在终端中交互。 |
| SFTP 大文件占内存 | Rust 侧直接流式文件 IO，不穿 Dart。 |
| 凭据泄露 | 平台 keychain + Rust zeroize + 日志脱敏。 |

## 技术决策记录

| 决策 | 选择 | 状态 |
| --- | --- | --- |
| Flutter/Rust 桥 | flutter_rust_bridge | 推荐采用 |
| SSH MVP | ssh2/libssh2 | 推荐采用 |
| SSH 纯 Rust 备选 | russh | 需要 spike |
| 本地 PTY | portable-pty | 推荐采用 |
| 终端核心 | alacritty_terminal 优先，vte 备选 | 需要 spike |
| 本地数据库 | Drift | 推荐采用 |
| Flutter 状态管理 | Riverpod | 推荐采用 |
| Flutter 路由 | go_router | 推荐采用 |

## 第一轮技术 Spike

### Spike A: Flutter/Rust 桥

目标：

- Flutter 调 Rust `core_init()`。
- Rust 创建 mock session。
- Rust 每 16ms 或按需发 `TerminalUpdated`。
- Flutter 订阅 event stream 并重绘。

通过标准：

- 无内存泄漏。
- UI 不阻塞。
- 事件频率可控。

### Spike B: SSH2 shell

目标：

- Rust 使用 `ssh2` 连接 OpenSSH。
- password/key auth。
- known_hosts check。
- request pty + shell。
- resize。

通过标准：

- `vim`、`top`、`stty size` 可用。

### Spike C: Terminal parser

目标：

- 比较 `alacritty_terminal` 和 `vte + custom grid`。
- 输入 `vttest` 基础输出。
- 输出 dirty ranges 到 Flutter。

通过标准：

- SGR、光标移动、清屏、alternate screen、中文宽字符基本正确。

### Spike D: SFTP

目标：

- list/upload/download/delete/rename。
- 大文件流式传输。
- 进度事件。

通过标准：

- 传输 10GB 文件时 Flutter 内存不随文件大小增长。

## 参考资料

- Flutter 官方文档：https://docs.flutter.dev/
- Flutter keyboard focus：https://docs.flutter.dev/ui/interactivity/focus
- Flutter Actions/Shortcuts：https://docs.flutter.dev/ui/interactivity/actions-and-shortcuts
- flutter_rust_bridge：https://pub.dev/packages/flutter_rust_bridge
- flutter_rust_bridge init：https://cjycode.com/flutter_rust_bridge/guides/how-to/init
- ssh2 crate：https://docs.rs/ssh2/latest/ssh2/
- libssh2 API docs：https://libssh2.org/docs.html
- russh crate：https://docs.rs/russh/latest/russh/
- portable-pty：https://docs.rs/portable-pty/
- alacritty_terminal：https://docs.rs/crate/alacritty_terminal/latest
- Riverpod：https://riverpod.dev/
- go_router：https://pub.dev/packages/go_router
- Drift：https://pub.dev/packages/drift
- Freezed：https://pub.dev/packages/freezed
- json_serializable：https://pub.dev/packages/json_serializable
- window_manager：https://pub.dev/packages/window_manager
