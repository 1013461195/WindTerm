# 开发日志

## 2026-06-09 Phase 0

目标：打通 Flutter UI 与 Rust core 的最小闭环。

已完成：

- 创建 Flutter 桌面项目：`wind_send/`。
- 支持 macOS、Windows、Linux 平台目录。
- 新增 Phase 0 终端工作区 UI。
- 新增 `CustomPainter` 终端视图，用于后续绘制 terminal grid。
- 新增 Dart FFI bridge：`wind_send/lib/core_bridge/rust_core.dart`。
- 新增 Rust workspace：`wind_send/rust/`。
- 新增 Rust cdylib core：`core_version`、`core_open_mock_session`、`core_poll_event`、`core_string_free`。
- Flutter bridge 支持 Rust dylib 加载失败时回退到 Dart mock core，便于 UI 先行开发。

已验证：

- `flutter --no-version-check pub get` 成功。
- `dart format lib test` 成功。
- `flutter --no-version-check analyze` 通过。
- `flutter --no-version-check test` 通过。

待完成：

- 本机 Rust toolchain 通过 `rustup` 出现了 `cargo` shim，但 stable toolchain 处于半安装状态，`cargo build` 报缺少 `std`/manifest。
- 已尝试 `rustup default stable`、`rustup target add x86_64-apple-darwin`、`rustup toolchain install stable --profile minimal --force`；受网络/工具链修复耗时影响，本轮未完成 Rust 编译验证。
- Flutter 尚未运行桌面窗口截图验证。

下一步：

- 修复本机 Rust toolchain：重新执行 `~/.cargo/bin/rustup toolchain install stable --profile minimal` 直到完成。
- 执行 `cd wind_send/rust && ~/.cargo/bin/cargo build`。
- 运行 Flutter 桌面应用，确认 Rust dylib 被加载，终端输出从 `[rust]` 而不是 `[dart fallback]` 开始。

## 2026-06-10 Phase 0 补充

已完成：

- Rust toolchain 验证：`rustup show` 确认 stable-x86_64-unknown-linux-gnu 已安装。
- Rust core 编译成功：`cargo build` 生成 `librust_core.so` (4.7MB, ELF 64-bit shared object)。
- 编译路径：`wind_send/rust/target/debug/librust_core.so`。

Phase 0 状态：**代码层面全部完成**，仅剩 Flutter 桌面运行验证。

## 2026-06-10 Phase 1 - SSH MVP 开发

目标：实现最小可用 SSH 客户端，支持密码登录、终端输出、键盘输入。

### 已完成：

**Rust Core 层：**

- 新增依赖：`ssh2` (0.9)、`vte` (0.13)、`serde` (1)、`serde_json` (1)。
- 新增模块：`session.rs` - SSH session 管理（连接、认证、channel、读写）。
- 新增模块：`terminal.rs` - VTE 终端解析器，支持 ANSI 转义序列、SGR 颜色、光标移动。
- 重构 `lib.rs`：新增 FFI 函数 `core_session_open`、`core_session_close`、`core_session_read`、`core_session_write`、`core_session_resize`、`core_session_state`。
- 终端快照序列化为 JSON 传给 Flutter，包含 cells、颜色属性、光标位置。

**Dart FFI Bridge 层：**

- 扩展 `rust_core.dart`：新增 `SshSession` 类封装会话操作。
- 新增类型：`TerminalSnapshot`、`TerminalLine`、`TerminalCell`、`CellAttr`、`TerminalColor`。
- 新增方法：`readOutput()`、`writeInput()`、`writeBytes()`、`resize()`、`getState()`。

**Flutter UI 层：**

- 新增 `features/session/session_editor.dart`：SSH 连接表单（host、port、username、password）。
- 新增 `features/terminal/terminal_painter.dart`：升级终端渲染，支持 cell 级别的颜色和样式。
- 新增 `features/terminal/terminal_input.dart`：键盘输入处理器，支持控制键、方向键、功能键。
- 重构 `main.dart`：集成会话管理、终端轮询、键盘输入。

### 已验证：

- Rust 编译通过：`cargo build` 成功，无错误。
- 依赖下载正常：ssh2、vte、serde 等 34 个包。
- FFI 函数签名正确。
- Flutter 代码结构清晰。

### Bug 修复（2026-06-10）：

**Bug 1：`_Calloc` 无限递归导致栈溢出**

- 原因：`rust_core.dart` 中自定义的 `_Calloc` 类的 `allocate()` 和 `free()` 方法调用的是自身实例（全局变量 `calloc`），形成无限递归。
- 修复：删除 `_Calloc` 类，改用 `package:ffi` 提供的 `malloc` 分配器。添加 `ffi: ^2.1.0` 依赖。

**Bug 2：SSH 连接阻塞 UI 主线程导致界面卡死**

- 原因：`_connect()` 方法在 Flutter UI 主线程上同步调用 `_core.openSession()`，该 FFI 调用执行 TCP 连接 + SSH 握手 + 认证，耗时数秒，期间 UI 完全冻结。
- 修复：新增 `_openSessionIsolate()` 顶层函数，在独立 Isolate 中执行阻塞的 FFI 调用。`_connect()` 改为 `async`，连接中显示加载动画并禁用按钮。暴露 `RustCore.libraryCandidates()` 公共方法供 Isolate 使用。

**Bug 3：SSH channel 阻塞读取导致轮询冻结**

- 原因：`session.rs` 中 `read_output()` 调用 `channel.read()`，SSH channel 默认阻塞模式，无数据时 `read()` 永久等待，持有 mutex 锁，导致 UI 轮询冻结。
- 修复：在 SSH 握手、认证、PTY 请求、shell 请求全部完成后，调用 `session.set_blocking(false)` 切换为非阻塞模式。`core_session_read` 中减少锁持有时间，避免阻塞其他操作。

### 已验证（Windows）：

- `cargo build` 编译 `rust_core.dll` 成功。
- `flutter run -d windows` 应用启动正常。
- SSH 密码登录连接成功。
- 终端输出正常显示。
- UI 不再卡死。

### 待完成：

- 终端渲染测试：验证颜色、光标、中文/emoji 支持。
- 键盘输入测试：验证控制键、方向键是否正确发送。
- 终端性能优化：大输出场景下的渲染性能。
- 连接状态管理：断线重连、连接超时处理。
- 终端窗口大小自适应：窗口 resize 时同步调整 PTY 大小。

### 下一步：

- 连接远程服务器，验证终端输出和键盘输入。
- 修复可能的渲染和输入问题。
- 优化终端性能（大输出场景）。
- 添加连接超时和错误重试机制。

## 2026-06-10 Phase 1.5 - 终端增强与 VTE 完善

目标：增强终端模拟器功能，支持更多转义序列、颜色、宽字符和滚动。

### 已完成：

**Rust Core 层：**

- 修复 `snapshot()` 缺少 `scrollback` / `scroll_offset` 字段的编译错误。
- 新增 CJK 宽字符支持：`is_wide_char()` 判定，`Cell.wide` 字段标记（0=正常，1=宽字符首字符，2=续字符占位）。
- 新增 RGB (38;2;R;G;B / 48;2;R;G;B) 和 256 色索引 (38;5;N / 48;5;N) 的 SGR 解析。
- 新增滚动区域支持（DECSTBM - CSI r），scroll_up/scroll_down 在区域内操作。
- 新增 scrollback 缓冲区：滚动时将顶部行推入 scrollback，上限 10000 行。
- 新增 insert_lines (CSI L)、delete_lines (CSI M)、insert_chars (CSI @)、delete_chars (CSI P)。
- 新增 scroll_up_n (CSI S)、scroll_down_n (CSI T)。
- 新增 save_cursor (ESC 7 / CSI s)、restore_cursor (ESC 8 / CSI u)。
- 新增 insert_mode (IRM - CSI 4h/l) 支持。
- 新增更多 CSI 序列：cursor_absolute (G/d)，cursor_next_line (E)，cursor_prev_line (F)，erase_chars (X)。
- 新增 DEC 私有模式处理：DECAWM (7)，备用屏幕缓冲区 (1049)，DECTCEM (25)。
- 新增 ESC 序列：IND (D)，RI (M)，NEL (E)，RIS (c) 重置。
- `put_char()` 方法统一处理宽字符写入和插入模式。

**Dart FFI Bridge 层：**

- 新增 `RgbColor`、`IndexedColor` 类型，支持 RGB 和 256 色解析。
- `CellAttr` 新增 `fgRgb`、`bgRgb`、`fgIndexed`、`bgIndexed` 字段。
- `TerminalCell` 新增 `wide` 字段（宽字符标记）。
- `TerminalSnapshot` 新增 `scrollback` 和 `scrollOffset` 字段。
- JSON 反序列化支持 Rust serde 的 `{"Rgb": [r,g,b]}` 和 `{"Indexed": n}` 格式。

**Flutter UI 层：**

- 重写 `terminal_painter.dart`：
  - 支持 RGB / 256 色索引渲染（`_indexedToColor` 6x6x6 RGB 色块 + 灰度渐变）。
  - 支持 inverse 属性（前景/背景互换）。
  - 支持宽字符渲染（跳过 wide==2 占位符，宽字符首字符正常绘制）。
  - 性能优化：合并连续相同属性字符为 TextSpan 批量绘制（减少 TextPainter 创建次数）。
  - 新增鼠标滚轮滚动支持：可查看 scrollback 历史行。
  - 新增滚动指示器 UI。
- 重写 `terminal_input.dart`：
  - 支持完整 Ctrl+A ~ Ctrl+Z 组合键。
  - 支持 Ctrl+[ / Ctrl+\ / Ctrl+] 控制字符。
  - 支持 Alt+字符 发送 ESC 前缀序列。
  - 支持 Shift+Tab 反向 Tab。
  - 新增 Insert 键支持。
  - 完整 UTF-8 编码支持（多字节字符正确发送）。

**测试与验证：**

- `cargo build` 编译通过，0 warnings。
- `dart format` 通过。
- `flutter analyze` 通过（No issues found!）。
- `flutter test` 通过。
- 单元测试更新：适配 Phase 1 UI 变化。

### 待完成：

- 终端渲染测试：连接远程服务器，验证颜色、宽字符、scrollback 实际效果。
- 终端性能优化：超大输出场景（如 `cat` 大文件）下的帧率和内存。
- 连接状态管理：断线重连、连接超时重试机制。
- 剪贴板集成：支持 Ctrl+Shift+C/V 复制粘贴。
- 鼠标事件支持：跟踪模式鼠标事件（CSI M 等）。

### 下一步：

- 连接远程服务器验证终端渲染效果。
- 优化大输出场景的渲染性能。
- 添加剪贴板支持。
- 添加连接错误重试机制。
