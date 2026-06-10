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
