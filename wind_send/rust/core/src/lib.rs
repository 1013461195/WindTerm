mod session;
mod terminal;
mod local_shell;
mod sftp;
mod network;
mod protocol;
mod security;
mod telnet;
mod raw_tcp;
mod crypto;

use session::{SshSession, SessionConfig, SessionState};
use terminal::{Terminal, MouseEvent, MouseEventType, MouseButton};
use local_shell::{LocalShellSession, LocalShellConfig, LocalShellState};
use sftp::{SftpSession, SftpFileInfo, SftpFileType};
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<u64, SshSession>>> = OnceLock::new();
static LOCAL_SHELLS: OnceLock<Mutex<HashMap<u64, LocalShellSession>>> = OnceLock::new();
static SFTP_SESSIONS: OnceLock<Mutex<HashMap<u64, SftpSession>>> = OnceLock::new();
static TERMINALS: OnceLock<Mutex<HashMap<u64, Terminal>>> = OnceLock::new();

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

    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);

    let config = SessionConfig {
        host,
        port,
        username,
        password: Some(password),
        network: network::NetworkConfig::default(),
    };

    let mut session = SshSession::new(session_id, config);

    // 连接
    if let Err(e) = session.connect() {
        eprintln!("连接失败: {}", e);
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
    let mut terminals = terminals().lock().expect("terminal mutex poisoned");
    if let Some(terminal) = terminals.get_mut(&session_id) {
        terminal.process(&output);
        let snapshot = terminal.snapshot();

        match serde_json::to_string(&snapshot) {
            Ok(json) => into_c_string(&json),
            Err(_) => std::ptr::null_mut(),
        }
    } else {
        std::ptr::null_mut()
    }
}

/// 发送输入
#[no_mangle]
pub unsafe extern "C" fn core_session_write(
    session_id: u64,
    data: *const u8,
    len: usize,
) -> i32 {
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

    if let Err(_) = session.resize(cols, rows) {
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

    // 发送编码后的鼠标事件到 session
    let mut sessions = sessions().lock().expect("session mutex poisoned");
    match sessions.get_mut(&session_id) {
        Some(session) => match session.write_input(&encoded) {
            Ok(_) => 0,
            Err(_) => -1,
        },
        None => -1,
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
pub extern "C" fn core_string_free(ptr: *mut c_char) {
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
    let mut terminals = terminals().lock().expect("terminal mutex poisoned");
    if let Some(terminal) = terminals.get_mut(&session_id) {
        terminal.process(&output);
        let snapshot = terminal.snapshot();

        match serde_json::to_string(&snapshot) {
            Ok(json) => into_c_string(&json),
            Err(_) => std::ptr::null_mut(),
        }
    } else {
        std::ptr::null_mut()
    }
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

    if let Err(_) = session.resize(cols, rows) {
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
pub extern "C" fn core_sftp_list_dir(sftp_id: u64, path: *const c_char) -> *mut c_char {
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
pub extern "C" fn core_sftp_stat(sftp_id: u64, path: *const c_char) -> *mut c_char {
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
pub extern "C" fn core_sftp_mkdir(sftp_id: u64, path: *const c_char, mode: i32) -> i32 {
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
pub extern "C" fn core_sftp_unlink(sftp_id: u64, path: *const c_char) -> i32 {
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
pub extern "C" fn core_sftp_rmdir(sftp_id: u64, path: *const c_char) -> i32 {
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
pub extern "C" fn core_sftp_rename(
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
pub extern "C" fn core_sftp_chmod(sftp_id: u64, path: *const c_char, mode: i32) -> i32 {
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
pub extern "C" fn core_sftp_upload(
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
pub extern "C" fn core_sftp_download(
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
