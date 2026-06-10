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

### 待完成：

- Flutter 桌面运行测试：需要在 Windows 上执行 `flutter run -d windows`。
- SSH 连接测试：需要连接真实 OpenSSH server 验证。
- 终端渲染测试：验证颜色、光标、中文/emoji 支持。
- 键盘输入测试：验证控制键、方向键是否正确发送。

### 下一步：

- 在 Windows 上运行 Flutter 应用，测试 SSH 连接流程。
- 连接远程服务器，验证终端输出和键盘输入。
- 修复可能的渲染和输入问题。
- 优化终端性能（大输出场景）。
