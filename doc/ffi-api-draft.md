# FFI 接口草案

本文定义 Dart/Flutter 与 Rust core 的初始边界。接口会演进，但核心原则是：Flutter 发命令，Rust 发事件。

## 基本概念

ID：

```text
SessionId: string
TaskId: string
ProfileId: string
RequestId: string
```

命令结果：

```text
Ok(value)
Err(CoreError)
```

事件流：

```text
CoreEvent
- session_id?
- task_id?
- kind
- payload
```

## 初始化

```text
core_init(app_config) -> CoreInfo
core_shutdown() -> void
core_subscribe_events(callback) -> Subscription
```

`app_config`：

```json
{
  "data_dir": "...",
  "log_level": "info",
  "platform": "macos"
}
```

## Session API

```text
session_open(profile) -> SessionId
session_close(session_id) -> void
session_reconnect(session_id) -> void
session_resize(session_id, cols, rows) -> void
session_write_bytes(session_id, bytes) -> void
session_send_key(session_id, key_event) -> void
session_send_text(session_id, text) -> void
session_get_snapshot(session_id, viewport) -> TerminalSnapshot
```

Profile 示例：

```json
{
  "kind": "ssh",
  "host": "example.com",
  "port": 22,
  "username": "deploy",
  "auth": {
    "kind": "private_key",
    "key_path": "/Users/me/.ssh/id_ed25519",
    "passphrase_ref": "keychain://..."
  },
  "terminal": {
    "term": "xterm-256color",
    "cols": 120,
    "rows": 36,
    "encoding": "utf-8"
  }
}
```

## Host Key 交互

当 Rust 发现 unknown/changed host key，不应直接继续，必须发事件：

```text
HostKeyVerificationRequired
- request_id
- session_id
- host
- port
- algorithm
- fingerprint_sha256
- status: unknown | changed | other_algorithm | not_found
```

Flutter 弹窗后调用：

```text
host_key_decide(request_id, decision)
```

decision：

```text
accept_once
accept_and_save
reject
replace_existing
```

## 认证交互

```text
AuthPromptRequired
- request_id
- session_id
- prompt_type: password | passphrase | keyboard_interactive
- title
- instruction
- prompts[]
```

响应：

```text
auth_prompt_answer(request_id, answers)
auth_prompt_cancel(request_id)
```

## Terminal Event

```text
TerminalUpdated
- session_id
- dirty_ranges: [{start_row, end_row}]
- cursor
- scrollback_len
```

Flutter 收到后可调用：

```text
session_get_snapshot(session_id, viewport)
```

Snapshot：

```text
TerminalSnapshot
- cols
- rows
- cursor
- lines[]
```

Line：

```text
cells[]
```

Cell：

```text
text
width
fg
bg
flags
```

## SFTP API

```text
sftp_open(session_id) -> SftpHandle
sftp_list(handle, path) -> TaskId
sftp_upload(handle, local_path, remote_path, options) -> TaskId
sftp_download(handle, remote_path, local_path, options) -> TaskId
sftp_remove(handle, path) -> TaskId
sftp_rename(handle, old_path, new_path) -> TaskId
sftp_mkdir(handle, path) -> TaskId
sftp_cancel(task_id) -> void
```

事件：

```text
SftpTaskProgress
- task_id
- transferred
- total
- bytes_per_second

SftpTaskCompleted
- task_id

SftpTaskFailed
- task_id
- error
```

## 错误模型

错误应结构化，不只返回字符串：

```text
CoreError
- code
- message
- recoverable
- detail
```

错误 code：

```text
network_timeout
network_refused
host_key_unknown
host_key_changed
auth_failed
auth_canceled
private_key_invalid
passphrase_required
permission_denied
pty_failed
channel_closed
protocol_error
sftp_error
serial_port_not_found
internal_error
```

## 事件背压

终端输出可能非常快，事件策略：

- Rust 合并 dirty ranges。
- 每个 session 最多每帧推一次 terminal update。
- Flutter 拉 snapshot，而不是 Rust 主动推全量 grid。
- 大输出期间允许丢弃中间 repaint 事件，但不能丢 terminal data。

