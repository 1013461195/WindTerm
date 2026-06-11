#![allow(clippy::missing_safety_doc)]

mod crypto;
mod local_shell;
mod network;
mod protocol;
mod raw_tcp;
mod security;
mod serial;
mod session;
mod sftp;
mod telnet;
mod terminal;
mod update;

use local_shell::{LocalShellConfig, LocalShellSession, LocalShellState};
use raw_tcp::RawTcpSession;
use serial::SerialSession;
use session::{SessionConfig, SessionState, SshSession};
use sftp::{SftpSession, SftpTransferState, SftpTransferTask};
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::AtomicBool;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;
use telnet::TelnetSession;
use terminal::{MouseButton, MouseEvent, MouseEventType, Terminal};

#[derive(serde::Deserialize)]
struct OpenSessionRequest {
    host: String,
    port: u16,
    username: String,
    password: Option<String>,
    private_key_path: Option<String>,
    passphrase: Option<String>,
    known_hosts_path: Option<String>,
    #[serde(default)]
    accept_unknown_host: bool,
    #[serde(default)]
    network: network::NetworkConfig,
}

static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<u64, SshSession>>> = OnceLock::new();
static LOCAL_SHELLS: OnceLock<Mutex<HashMap<u64, LocalShellSession>>> = OnceLock::new();
static SFTP_SESSIONS: OnceLock<Mutex<HashMap<u64, SftpSession>>> = OnceLock::new();
static TERMINALS: OnceLock<Mutex<HashMap<u64, Terminal>>> = OnceLock::new();
static PROTOCOL_SESSIONS: OnceLock<Mutex<HashMap<u64, ProtocolSession>>> = OnceLock::new();
static SFTP_TRANSFERS: OnceLock<Mutex<HashMap<u64, SftpTransferRuntime>>> = OnceLock::new();
static LAST_OPEN_ERROR: OnceLock<Mutex<Option<String>>> = OnceLock::new();

struct SftpTransferRuntime {
    task: Arc<Mutex<SftpTransferTask>>,
    canceled: Arc<AtomicBool>,
}

enum ProtocolSession {
    Telnet(TelnetSession),
    RawTcp(RawTcpSession),
    Serial(SerialSession),
}

#[derive(serde::Deserialize)]
#[serde(tag = "type", content = "config", rename_all = "snake_case")]
enum OpenProtocolRequest {
    Telnet(protocol::TelnetConfig),
    RawTcp(protocol::RawTcpConfig),
    Serial(protocol::SerialConfig),
}

fn sessions() -> &'static Mutex<HashMap<u64, SshSession>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn local_shells() -> &'static Mutex<HashMap<u64, LocalShellSession>> {
    LOCAL_SHELLS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn sftp_sessions() -> &'static Mutex<HashMap<u64, SftpSession>> {
    SFTP_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn terminals() -> &'static Mutex<HashMap<u64, Terminal>> {
    TERMINALS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn protocol_sessions() -> &'static Mutex<HashMap<u64, ProtocolSession>> {
    PROTOCOL_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn sftp_transfers() -> &'static Mutex<HashMap<u64, SftpTransferRuntime>> {
    SFTP_TRANSFERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn set_last_open_error(error: impl Into<String>) {
    *LAST_OPEN_ERROR
        .get_or_init(|| Mutex::new(None))
        .lock()
        .expect("last open error mutex poisoned") = Some(error.into());
}

/// 获取 core 版本
#[no_mangle]
pub extern "C" fn core_version() -> *mut c_char {
    into_c_string("rust core phase 1 - ssh mvp")
}

/// 打开 SSH session
#[no_mangle]
pub unsafe extern "C" fn core_session_open(
    host: *const c_char,
    port: u16,
    username: *const c_char,
    password: *const c_char,
) -> u64 {
    let host = match unsafe { CStr::from_ptr(host) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    let username = match unsafe { CStr::from_ptr(username) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    let password = match unsafe { CStr::from_ptr(password) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let config = SessionConfig {
        host,
        port,
        username,
        password: Some(password),
        private_key_path: None,
        passphrase: None,
        known_hosts_path: None,
        accept_unknown_host: false,
        network: network::NetworkConfig::default(),
    };

    open_session(config)
}

/// 使用 JSON 配置打开 SSH session。
///
/// # Safety
/// `request_json` 必须指向以 NUL 结尾且在调用期间有效的 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_session_open_json(request_json: *const c_char) -> u64 {
    if request_json.is_null() {
        set_last_open_error("SSH 配置为空");
        return 0;
    }
    let request = match unsafe { CStr::from_ptr(request_json) }.to_str() {
        Ok(json) => match serde_json::from_str::<OpenSessionRequest>(json) {
            Ok(request) => request,
            Err(error) => {
                set_last_open_error(format!("解析 SSH 配置失败: {error}"));
                return 0;
            }
        },
        Err(_) => {
            set_last_open_error("SSH 配置不是有效 UTF-8");
            return 0;
        }
    };

    open_session(SessionConfig {
        host: request.host,
        port: request.port,
        username: request.username,
        password: request.password,
        private_key_path: request.private_key_path,
        passphrase: request.passphrase,
        known_hosts_path: request.known_hosts_path,
        accept_unknown_host: request.accept_unknown_host,
        network: request.network,
    })
}

fn open_session(config: SessionConfig) -> u64 {
    set_last_open_error("");
    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let mut session = SshSession::new(session_id, config);

    // 连接
    if let Err(e) = session.connect() {
        set_last_open_error(e);
        return 0;
    }

    // 创建终端
    let terminal = Terminal::new(session.cols() as usize, session.rows() as usize);

    // 存储
    sessions()
        .lock()
        .expect("session mutex poisoned")
        .insert(session_id, session);
    terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .insert(session_id, terminal);

    session_id
}

#[no_mangle]
pub extern "C" fn core_session_last_open_error() -> *mut c_char {
    let error = LAST_OPEN_ERROR
        .get_or_init(|| Mutex::new(None))
        .lock()
        .expect("last open error mutex poisoned");
    error
        .as_deref()
        .filter(|value| !value.is_empty())
        .map(into_c_string)
        .unwrap_or(std::ptr::null_mut())
}

/// 关闭 session
#[no_mangle]
pub extern "C" fn core_session_close(session_id: u64) {
    sessions()
        .lock()
        .expect("session mutex poisoned")
        .remove(&session_id);
    terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .remove(&session_id);
}

/// 读取输出并更新终端
#[no_mangle]
pub extern "C" fn core_session_read(session_id: u64) -> *mut c_char {
    // 读取输出（短暂持有 sessions 锁）
    let output = {
        let mut sessions = sessions().lock().expect("session mutex poisoned");
        match sessions.get_mut(&session_id) {
            Some(s) => s.read_output(),
            None => return std::ptr::null_mut(),
        }
    };

    if output.is_empty() {
        return std::ptr::null_mut();
    }

    // 更新终端（短暂持有 terminals 锁）
    let (snapshot, responses) = snapshot_after_output(session_id, &output);
    if !responses.is_empty() {
        if let Some(session) = sessions()
            .lock()
            .expect("session mutex poisoned")
            .get_mut(&session_id)
        {
            let _ = session.write_input(&responses);
        }
    }
    snapshot
}

/// 发送输入
#[no_mangle]
pub unsafe extern "C" fn core_session_write(session_id: u64, data: *const u8, len: usize) -> i32 {
    let data = unsafe { std::slice::from_raw_parts(data, len) };

    let mut sessions = sessions().lock().expect("session mutex poisoned");
    let session = match sessions.get_mut(&session_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.write_input(data) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 调整终端大小
#[no_mangle]
pub extern "C" fn core_session_resize(session_id: u64, cols: u16, rows: u16) -> i32 {
    let mut sessions = sessions().lock().expect("session mutex poisoned");
    let session = match sessions.get_mut(&session_id) {
        Some(s) => s,
        None => return -1,
    };

    if session.resize(cols, rows).is_err() {
        return -1;
    }

    let mut terminals = terminals().lock().expect("terminal mutex poisoned");
    if let Some(terminal) = terminals.get_mut(&session_id) {
        terminal.resize(cols as usize, rows as usize);
    }

    0
}

/// 获取 session 状态
#[no_mangle]
pub extern "C" fn core_session_state(session_id: u64) -> *mut c_char {
    let sessions = sessions().lock().expect("session mutex poisoned");
    let session = match sessions.get(&session_id) {
        Some(s) => s,
        None => return into_c_string("unknown"),
    };

    let state_str = match session.state() {
        SessionState::Created => "created",
        SessionState::Connecting => "connecting",
        SessionState::Authenticating => "authenticating",
        SessionState::Running => "running",
        SessionState::Closed => "closed",
        SessionState::Error(_) => "error",
        SessionState::Disconnected => "disconnected",
        SessionState::Reconnecting => "reconnecting",
    };

    into_c_string(state_str)
}

/// 发送鼠标事件
#[no_mangle]
pub extern "C" fn core_session_mouse_event(
    session_id: u64,
    event_type: u8,
    button: u8,
    col: u16,
    row: u16,
    shift: bool,
    meta: bool,
    ctrl: bool,
) -> i32 {
    let event_type = match event_type {
        0 => MouseEventType::Press,
        1 => MouseEventType::Release,
        2 => MouseEventType::Motion,
        _ => return -1,
    };

    let button = match button {
        0 => MouseButton::Left,
        1 => MouseButton::Middle,
        2 => MouseButton::Right,
        3 => MouseButton::None,
        _ => return -1,
    };

    let event = MouseEvent {
        event_type,
        button,
        col: col as usize,
        row: row as usize,
        shift,
        meta,
        ctrl,
    };

    // 获取终端并编码鼠标事件
    let encoded = {
        let mut terminals = terminals().lock().expect("terminal mutex poisoned");
        match terminals.get_mut(&session_id) {
            Some(terminal) => terminal.encode_mouse_event(&event),
            None => return -1,
        }
    };

    if encoded.is_empty() {
        return 0;
    }

    if let Some(session) = sessions()
        .lock()
        .expect("session mutex poisoned")
        .get_mut(&session_id)
    {
        return if session.write_input(&encoded).is_ok() {
            0
        } else {
            -1
        };
    }
    if let Some(shell) = local_shells()
        .lock()
        .expect("local shell mutex poisoned")
        .get_mut(&session_id)
    {
        return if shell.write_input(&encoded).is_ok() {
            0
        } else {
            -1
        };
    }
    let mut protocols = protocol_sessions()
        .lock()
        .expect("protocol session mutex poisoned");
    let result = match protocols.get_mut(&session_id) {
        Some(ProtocolSession::Telnet(session)) => session.write_input(&encoded),
        Some(ProtocolSession::RawTcp(session)) => session.write_input(&encoded),
        Some(ProtocolSession::Serial(session)) => session.write_input(&encoded),
        None => return -1,
    };
    if result.is_ok() {
        0
    } else {
        -1
    }
}

/// 尝试重新连接
#[no_mangle]
pub extern "C" fn core_session_reconnect(session_id: u64) -> i32 {
    let mut sessions = sessions().lock().expect("session mutex poisoned");
    match sessions.get_mut(&session_id) {
        Some(session) => match session.reconnect() {
            Ok(()) => 0,
            Err(_) => -1,
        },
        None => -1,
    }
}

/// 获取重连次数
#[no_mangle]
pub extern "C" fn core_session_reconnect_attempts(session_id: u64) -> u32 {
    let sessions = sessions().lock().expect("session mutex poisoned");
    match sessions.get(&session_id) {
        Some(session) => session.reconnect_attempts(),
        None => 0,
    }
}

/// 检查是否可以重连
#[no_mangle]
pub extern "C" fn core_session_can_reconnect(session_id: u64) -> bool {
    let sessions = sessions().lock().expect("session mutex poisoned");
    match sessions.get(&session_id) {
        Some(session) => session.can_reconnect(),
        None => false,
    }
}

/// 获取最后错误信息
#[no_mangle]
pub extern "C" fn core_session_last_error(session_id: u64) -> *mut c_char {
    let sessions = sessions().lock().expect("session mutex poisoned");
    match sessions.get(&session_id) {
        Some(session) => match session.last_error() {
            Some(error) => into_c_string(error),
            None => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn core_session_port_forward_status(session_id: u64) -> *mut c_char {
    let sessions = sessions().lock().expect("session mutex poisoned");
    let Some(session) = sessions.get(&session_id) else {
        return std::ptr::null_mut();
    };
    serde_json::to_string(&session.port_forward_status())
        .map(|json| into_c_string(&json))
        .unwrap_or(std::ptr::null_mut())
}

/// 检查连接超时
#[no_mangle]
pub extern "C" fn core_session_check_timeout(session_id: u64) -> bool {
    let mut sessions = sessions().lock().expect("session mutex poisoned");
    match sessions.get_mut(&session_id) {
        Some(session) => session.check_timeout(),
        None => false,
    }
}

/// 释放字符串
#[no_mangle]
pub unsafe extern "C" fn core_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

fn into_c_string(value: &str) -> *mut c_char {
    CString::new(value)
        .expect("string contains interior nul")
        .into_raw()
}

// ── 本地 Shell FFI 函数 ──

/// 打开本地 Shell 会话
#[no_mangle]
pub unsafe extern "C" fn core_local_shell_open(
    shell: *const c_char,
    working_dir: *const c_char,
    cols: u16,
    rows: u16,
) -> u64 {
    let shell = match unsafe { CStr::from_ptr(shell) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let working_dir = if working_dir.is_null() {
        None
    } else {
        match unsafe { CStr::from_ptr(working_dir) }.to_str() {
            Ok(s) => Some(s.to_string()),
            Err(_) => None,
        }
    };

    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);

    let config = LocalShellConfig {
        shell,
        working_dir,
        cols,
        rows,
        ..Default::default()
    };

    let mut session = LocalShellSession::new(session_id, config);

    // 启动 Shell
    if let Err(e) = session.start() {
        eprintln!("启动本地 Shell 失败: {}", e);
        return 0;
    }

    // 创建终端
    let terminal = Terminal::new(cols as usize, rows as usize);

    // 存储
    local_shells()
        .lock()
        .expect("local_shell mutex poisoned")
        .insert(session_id, session);
    terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .insert(session_id, terminal);

    session_id
}

/// 关闭本地 Shell 会话
#[no_mangle]
pub extern "C" fn core_local_shell_close(session_id: u64) {
    local_shells()
        .lock()
        .expect("local_shell mutex poisoned")
        .remove(&session_id);
    terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .remove(&session_id);
}

/// 读取本地 Shell 输出
#[no_mangle]
pub extern "C" fn core_local_shell_read(session_id: u64) -> *mut c_char {
    // 读取输出（短暂持有 local_shells 锁）
    let output = {
        let mut shells = local_shells().lock().expect("local_shell mutex poisoned");
        match shells.get_mut(&session_id) {
            Some(s) => s.read_output(),
            None => return std::ptr::null_mut(),
        }
    };

    if output.is_empty() {
        return std::ptr::null_mut();
    }

    // 更新终端（短暂持有 terminals 锁）
    let (snapshot, responses) = snapshot_after_output(session_id, &output);
    if !responses.is_empty() {
        if let Some(shell) = local_shells()
            .lock()
            .expect("local_shell mutex poisoned")
            .get_mut(&session_id)
        {
            let _ = shell.write_input(&responses);
        }
    }
    snapshot
}

/// 发送本地 Shell 输入
#[no_mangle]
pub unsafe extern "C" fn core_local_shell_write(
    session_id: u64,
    data: *const u8,
    len: usize,
) -> i32 {
    let data = unsafe { std::slice::from_raw_parts(data, len) };

    let mut shells = local_shells().lock().expect("local_shell mutex poisoned");
    let session = match shells.get_mut(&session_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.write_input(data) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 调整本地 Shell 终端大小
#[no_mangle]
pub extern "C" fn core_local_shell_resize(session_id: u64, cols: u16, rows: u16) -> i32 {
    let mut shells = local_shells().lock().expect("local_shell mutex poisoned");
    let session = match shells.get_mut(&session_id) {
        Some(s) => s,
        None => return -1,
    };

    if session.resize(cols, rows).is_err() {
        return -1;
    }

    let mut terminals = terminals().lock().expect("terminal mutex poisoned");
    if let Some(terminal) = terminals.get_mut(&session_id) {
        terminal.resize(cols as usize, rows as usize);
    }

    0
}

/// 获取本地 Shell 会话状态
#[no_mangle]
pub extern "C" fn core_local_shell_state(session_id: u64) -> *mut c_char {
    let shells = local_shells().lock().expect("local_shell mutex poisoned");
    let session = match shells.get(&session_id) {
        Some(s) => s,
        None => return into_c_string("unknown"),
    };

    let state_str = match session.state() {
        LocalShellState::Created => "created",
        LocalShellState::Running => "running",
        LocalShellState::Exited => "exited",
        LocalShellState::Error(_) => "error",
    };

    into_c_string(state_str)
}

// ── SFTP FFI 函数 ──

/// 打开 SFTP 会话
#[no_mangle]
pub extern "C" fn core_sftp_open(session_id: u64) -> u64 {
    let sftp_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);

    // 从 SSH session 创建 SFTP 会话
    let sftp = {
        let sessions = sessions().lock().expect("session mutex poisoned");
        match sessions.get(&session_id) {
            Some(session) => match session.open_sftp() {
                Ok(sftp) => sftp,
                Err(_) => return 0,
            },
            None => return 0,
        }
    };

    sftp_sessions()
        .lock()
        .expect("sftp mutex poisoned")
        .insert(sftp_id, sftp);

    sftp_id
}

/// 关闭 SFTP 会话
#[no_mangle]
pub extern "C" fn core_sftp_close(sftp_id: u64) {
    sftp_sessions()
        .lock()
        .expect("sftp mutex poisoned")
        .remove(&sftp_id);
}

/// 列出目录内容（返回 JSON）
#[no_mangle]
pub unsafe extern "C" fn core_sftp_list_dir(sftp_id: u64, path: *const c_char) -> *mut c_char {
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };

    match session.list_dir(path) {
        Ok(files) => match serde_json::to_string(&files) {
            Ok(json) => into_c_string(&json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// 获取文件信息（返回 JSON）
#[no_mangle]
pub unsafe extern "C" fn core_sftp_stat(sftp_id: u64, path: *const c_char) -> *mut c_char {
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };

    match session.stat(path) {
        Ok(info) => match serde_json::to_string(&info) {
            Ok(json) => into_c_string(&json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// 创建目录
#[no_mangle]
pub unsafe extern "C" fn core_sftp_mkdir(sftp_id: u64, path: *const c_char, mode: i32) -> i32 {
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.mkdir(path, mode) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 删除文件
#[no_mangle]
pub unsafe extern "C" fn core_sftp_unlink(sftp_id: u64, path: *const c_char) -> i32 {
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.unlink(path) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 删除目录
#[no_mangle]
pub unsafe extern "C" fn core_sftp_rmdir(sftp_id: u64, path: *const c_char) -> i32 {
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.rmdir(path) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 重命名/移动文件
#[no_mangle]
pub unsafe extern "C" fn core_sftp_rename(
    sftp_id: u64,
    src: *const c_char,
    dst: *const c_char,
) -> i32 {
    let src = match unsafe { CStr::from_ptr(src) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let dst = match unsafe { CStr::from_ptr(dst) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.rename(src, dst, 0) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 修改权限
#[no_mangle]
pub unsafe extern "C" fn core_sftp_chmod(sftp_id: u64, path: *const c_char, mode: i32) -> i32 {
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.chmod(path, mode) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 上传文件
#[no_mangle]
pub unsafe extern "C" fn core_sftp_upload(
    sftp_id: u64,
    local_path: *const c_char,
    remote_path: *const c_char,
) -> i32 {
    let local_path = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let remote_path = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.upload_file(local_path, remote_path) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 下载文件
#[no_mangle]
pub unsafe extern "C" fn core_sftp_download(
    sftp_id: u64,
    remote_path: *const c_char,
    local_path: *const c_char,
) -> i32 {
    let remote_path = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let local_path = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let sftp_sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
    let session = match sftp_sessions.get(&sftp_id) {
        Some(s) => s,
        None => return -1,
    };

    match session.download_file(remote_path, local_path) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 启动后台 SFTP 传输任务。
///
/// # Safety
/// 路径参数必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_sftp_transfer_start(
    sftp_id: u64,
    local_path: *const c_char,
    remote_path: *const c_char,
    is_upload: bool,
) -> u64 {
    let local_path = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(path) => path.to_string(),
        Err(_) => return 0,
    };
    let remote_path = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(path) => path.to_string(),
        Err(_) => return 0,
    };
    let session = {
        let sessions = sftp_sessions().lock().expect("sftp mutex poisoned");
        match sessions.get(&sftp_id) {
            Some(session) => session.clone(),
            None => return 0,
        }
    };
    let total_bytes = if is_upload {
        std::fs::metadata(&local_path)
            .map(|metadata| metadata.len())
            .unwrap_or(0)
    } else {
        session
            .stat(&remote_path)
            .map(|info| info.size)
            .unwrap_or(0)
    };
    let transfer_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let task = Arc::new(Mutex::new(SftpTransferTask {
        id: transfer_id,
        local_path: local_path.clone(),
        remote_path: remote_path.clone(),
        is_upload,
        state: SftpTransferState::Queued,
        total_bytes,
        transferred_bytes: 0,
        speed: 0.0,
    }));
    let canceled = Arc::new(AtomicBool::new(false));
    sftp_transfers()
        .lock()
        .expect("sftp transfer mutex poisoned")
        .insert(
            transfer_id,
            SftpTransferRuntime {
                task: Arc::clone(&task),
                canceled: Arc::clone(&canceled),
            },
        );
    std::thread::spawn(move || {
        task.lock().expect("sftp task mutex poisoned").state = SftpTransferState::Running;
        let started = Instant::now();
        let progress_task = Arc::clone(&task);
        let result = if is_upload {
            session.upload_file_with_progress(&local_path, &remote_path, move |transferred| {
                update_transfer_progress(&progress_task, started, transferred, &canceled)
            })
        } else {
            session.download_file_with_progress(&remote_path, &local_path, move |transferred| {
                update_transfer_progress(&progress_task, started, transferred, &canceled)
            })
        };
        let mut task = task.lock().expect("sftp task mutex poisoned");
        task.state = match result {
            Ok(transferred) => {
                task.transferred_bytes = transferred;
                SftpTransferState::Completed
            }
            Err(error) if error == "传输已取消" => SftpTransferState::Canceled,
            Err(error) => SftpTransferState::Failed(error),
        };
    });
    transfer_id
}

fn update_transfer_progress(
    task: &Arc<Mutex<SftpTransferTask>>,
    started: Instant,
    transferred: u64,
    canceled: &Arc<AtomicBool>,
) -> Result<(), String> {
    if canceled.load(Ordering::Relaxed) {
        return Err("传输已取消".to_string());
    }
    let elapsed = started.elapsed().as_secs_f64().max(0.001);
    let mut task = task.lock().expect("sftp task mutex poisoned");
    task.transferred_bytes = transferred;
    task.speed = transferred as f64 / elapsed;
    Ok(())
}

#[no_mangle]
pub extern "C" fn core_sftp_transfer_status(transfer_id: u64) -> *mut c_char {
    let mut transfers = sftp_transfers()
        .lock()
        .expect("sftp transfer mutex poisoned");
    let Some(runtime) = transfers.get(&transfer_id) else {
        return std::ptr::null_mut();
    };
    let (json, finished) = {
        let task = runtime.task.lock().expect("sftp task mutex poisoned");
        (
            serde_json::to_string(&*task).ok(),
            matches!(
                task.state,
                SftpTransferState::Completed
                    | SftpTransferState::Failed(_)
                    | SftpTransferState::Canceled
            ),
        )
    };
    if finished {
        transfers.remove(&transfer_id);
    }
    json.map(|json| into_c_string(&json))
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn core_sftp_transfer_cancel(transfer_id: u64) -> i32 {
    let transfers = sftp_transfers()
        .lock()
        .expect("sftp transfer mutex poisoned");
    let Some(runtime) = transfers.get(&transfer_id) else {
        return -1;
    };
    runtime.canceled.store(true, Ordering::Relaxed);
    0
}

// ── Telnet / Raw TCP / Serial FFI ──

/// 打开通用协议会话。
///
/// # Safety
/// `request_json` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_protocol_open(request_json: *const c_char) -> u64 {
    if request_json.is_null() {
        return 0;
    }
    let request = match unsafe { CStr::from_ptr(request_json) }.to_str() {
        Ok(json) => match serde_json::from_str::<OpenProtocolRequest>(json) {
            Ok(request) => request,
            Err(error) => {
                eprintln!("解析协议配置失败: {error}");
                return 0;
            }
        },
        Err(_) => return 0,
    };
    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let session = match request {
        OpenProtocolRequest::Telnet(config) => {
            let mut session = TelnetSession::new(session_id, config);
            if let Err(error) = session.connect() {
                eprintln!("{error}");
                return 0;
            }
            ProtocolSession::Telnet(session)
        }
        OpenProtocolRequest::RawTcp(config) => {
            let mut session = RawTcpSession::new(session_id, config);
            if let Err(error) = session.connect() {
                eprintln!("{error}");
                return 0;
            }
            ProtocolSession::RawTcp(session)
        }
        OpenProtocolRequest::Serial(config) => {
            let mut session = SerialSession::new(config);
            if let Err(error) = session.connect() {
                eprintln!("{error}");
                return 0;
            }
            ProtocolSession::Serial(session)
        }
    };
    protocol_sessions()
        .lock()
        .expect("protocol session mutex poisoned")
        .insert(session_id, session);
    terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .insert(session_id, Terminal::new(80, 24));
    session_id
}

#[no_mangle]
pub extern "C" fn core_protocol_read(session_id: u64) -> *mut c_char {
    let output = {
        let mut sessions = protocol_sessions()
            .lock()
            .expect("protocol session mutex poisoned");
        match sessions.get_mut(&session_id) {
            Some(ProtocolSession::Telnet(session)) => session.read_output(),
            Some(ProtocolSession::RawTcp(session)) => session.read_output(),
            Some(ProtocolSession::Serial(session)) => session.read_output(),
            None => return std::ptr::null_mut(),
        }
    };
    if output.is_empty() {
        return std::ptr::null_mut();
    }
    let (snapshot, responses) = snapshot_after_output(session_id, &output);
    if !responses.is_empty() {
        let mut sessions = protocol_sessions()
            .lock()
            .expect("protocol session mutex poisoned");
        match sessions.get_mut(&session_id) {
            Some(ProtocolSession::Telnet(session)) => {
                let _ = session.write_input(&responses);
            }
            Some(ProtocolSession::RawTcp(session)) => {
                let _ = session.write_input(&responses);
            }
            Some(ProtocolSession::Serial(session)) => {
                let _ = session.write_input(&responses);
            }
            None => {}
        }
    }
    snapshot
}

/// # Safety
/// `data` 必须指向至少 `len` 字节的有效内存。
#[no_mangle]
pub unsafe extern "C" fn core_protocol_write(session_id: u64, data: *const u8, len: usize) -> i32 {
    if data.is_null() && len != 0 {
        return -1;
    }
    let data = unsafe { std::slice::from_raw_parts(data, len) };
    let mut sessions = protocol_sessions()
        .lock()
        .expect("protocol session mutex poisoned");
    let result = match sessions.get_mut(&session_id) {
        Some(ProtocolSession::Telnet(session)) => session.write_input(data),
        Some(ProtocolSession::RawTcp(session)) => session.write_input(data),
        Some(ProtocolSession::Serial(session)) => session.write_input(data),
        None => return -1,
    };
    if result.is_ok() {
        0
    } else {
        -1
    }
}

#[no_mangle]
pub extern "C" fn core_protocol_resize(session_id: u64, cols: u16, rows: u16) -> i32 {
    let mut sessions = protocol_sessions()
        .lock()
        .expect("protocol session mutex poisoned");
    let result = match sessions.get_mut(&session_id) {
        Some(ProtocolSession::Telnet(session)) => session.resize(cols, rows),
        Some(ProtocolSession::RawTcp(session)) => session.resize(cols, rows),
        Some(ProtocolSession::Serial(session)) => {
            session.resize(cols, rows);
            Ok(())
        }
        None => return -1,
    };
    if result.is_err() {
        return -1;
    }
    if let Some(terminal) = terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .get_mut(&session_id)
    {
        terminal.resize(cols as usize, rows as usize);
    }
    0
}

#[no_mangle]
pub extern "C" fn core_protocol_state(session_id: u64) -> *mut c_char {
    let sessions = protocol_sessions()
        .lock()
        .expect("protocol session mutex poisoned");
    let state = match sessions.get(&session_id) {
        Some(ProtocolSession::Telnet(session)) => match session.state() {
            telnet::TelnetState::Created => "created",
            telnet::TelnetState::Connecting => "connecting",
            telnet::TelnetState::Connected => "connected",
            telnet::TelnetState::Closed => "closed",
            telnet::TelnetState::Error(_) => "error",
        },
        Some(ProtocolSession::RawTcp(session)) => match session.state() {
            raw_tcp::RawTcpState::Created => "created",
            raw_tcp::RawTcpState::Connecting => "connecting",
            raw_tcp::RawTcpState::Connected => "connected",
            raw_tcp::RawTcpState::Closed => "closed",
            raw_tcp::RawTcpState::Error(_) => "error",
        },
        Some(ProtocolSession::Serial(session)) => session.state_name(),
        None => "unknown",
    };
    into_c_string(state)
}

#[no_mangle]
pub extern "C" fn core_protocol_close(session_id: u64) {
    protocol_sessions()
        .lock()
        .expect("protocol session mutex poisoned")
        .remove(&session_id);
    terminals()
        .lock()
        .expect("terminal mutex poisoned")
        .remove(&session_id);
}

#[no_mangle]
pub extern "C" fn core_serial_list_ports() -> *mut c_char {
    match serial::available_ports_json() {
        Ok(json) => into_c_string(&json),
        Err(_) => std::ptr::null_mut(),
    }
}

/// # Safety
/// 所有参数必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_crypto_encrypt(
    plaintext: *const c_char,
    password: *const c_char,
) -> *mut c_char {
    let plaintext = unsafe { CStr::from_ptr(plaintext) }.to_bytes();
    let password = unsafe { CStr::from_ptr(password) }.to_bytes();
    let encryptor = crypto::CredentialEncryptor::new(crypto::CryptoConfig::default());
    match encryptor.encrypt(plaintext, password) {
        Ok(encrypted) => serde_json::to_string(&encrypted)
            .map(|json| into_c_string(&json))
            .unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

/// # Safety
/// 所有参数必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_crypto_decrypt(
    encrypted_json: *const c_char,
    password: *const c_char,
) -> *mut c_char {
    let encrypted_json = match unsafe { CStr::from_ptr(encrypted_json) }.to_str() {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    let password = unsafe { CStr::from_ptr(password) }.to_bytes();
    let encrypted = match serde_json::from_str::<crypto::EncryptedData>(encrypted_json) {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    let encryptor = crypto::CredentialEncryptor::new(crypto::CryptoConfig::default());
    match encryptor.decrypt(&encrypted, password) {
        Ok(mut plaintext) => {
            let result = String::from_utf8(plaintext.clone())
                .ok()
                .map(|value| into_c_string(&value))
                .unwrap_or(std::ptr::null_mut());
            crypto::secure_zero(&mut plaintext);
            result
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// # Safety
/// `credential_id` 和 `secret` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_keychain_set(
    credential_id: *const c_char,
    secret: *const c_char,
) -> i32 {
    let credential_id = match unsafe { CStr::from_ptr(credential_id) }.to_str() {
        Ok(value) => value,
        Err(_) => return -1,
    };
    let secret = match unsafe { CStr::from_ptr(secret) }.to_str() {
        Ok(value) => value,
        Err(_) => return -1,
    };
    match keyring::Entry::new("wind_send", credential_id)
        .and_then(|entry| entry.set_password(secret))
    {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// # Safety
/// `credential_id` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_keychain_get(credential_id: *const c_char) -> *mut c_char {
    let credential_id = match unsafe { CStr::from_ptr(credential_id) }.to_str() {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    keyring::Entry::new("wind_send", credential_id)
        .and_then(|entry| entry.get_password())
        .map(|secret| into_c_string(&secret))
        .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `credential_id` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn core_keychain_delete(credential_id: *const c_char) -> i32 {
    let credential_id = match unsafe { CStr::from_ptr(credential_id) }.to_str() {
        Ok(value) => value,
        Err(_) => return -1,
    };
    match keyring::Entry::new("wind_send", credential_id)
        .and_then(|entry| entry.delete_credential())
    {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn core_update_verify_signature(
    payload: *const u8,
    payload_len: usize,
    signature_b64: *const c_char,
    public_key_b64: *const c_char,
) -> bool {
    if payload.is_null() || signature_b64.is_null() || public_key_b64.is_null() {
        return false;
    }
    let payload = unsafe { std::slice::from_raw_parts(payload, payload_len) };
    let signature = match unsafe { CStr::from_ptr(signature_b64) }.to_str() {
        Ok(value) => value,
        Err(_) => return false,
    };
    let public_key = match unsafe { CStr::from_ptr(public_key_b64) }.to_str() {
        Ok(value) => value,
        Err(_) => return false,
    };
    update::verify_signature(payload, signature, public_key)
}

#[no_mangle]
pub unsafe extern "C" fn core_update_verify_sha256(
    data: *const u8,
    data_len: usize,
    expected_hex: *const c_char,
) -> bool {
    if data.is_null() || expected_hex.is_null() {
        return false;
    }
    let data = unsafe { std::slice::from_raw_parts(data, data_len) };
    let expected = match unsafe { CStr::from_ptr(expected_hex) }.to_str() {
        Ok(value) => value,
        Err(_) => return false,
    };
    update::verify_sha256(data, expected)
}

#[no_mangle]
pub unsafe extern "C" fn core_update_verify_file_sha256(
    path: *const c_char,
    expected_hex: *const c_char,
) -> bool {
    if path.is_null() || expected_hex.is_null() {
        return false;
    }
    let path = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(value) => value,
        Err(_) => return false,
    };
    let expected = match unsafe { CStr::from_ptr(expected_hex) }.to_str() {
        Ok(value) => value,
        Err(_) => return false,
    };
    update::verify_file_sha256(path, expected)
}

fn snapshot_after_output(session_id: u64, output: &[u8]) -> (*mut c_char, Vec<u8>) {
    let mut terminals = terminals().lock().expect("terminal mutex poisoned");
    let Some(terminal) = terminals.get_mut(&session_id) else {
        return (std::ptr::null_mut(), Vec::new());
    };
    terminal.process(output);
    let responses = terminal.take_pending_responses();
    let mut snapshot = terminal.snapshot();
    snapshot.output_text = String::from_utf8_lossy(output).into_owned();
    let pointer = serde_json::to_string(&snapshot)
        .map(|json| into_c_string(&json))
        .unwrap_or(std::ptr::null_mut());
    (pointer, responses)
}
