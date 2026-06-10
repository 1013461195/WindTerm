mod session;
mod terminal;

use session::{SshSession, SessionConfig, SessionState};
use terminal::Terminal;
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<u64, SshSession>>> = OnceLock::new();
static TERMINALS: OnceLock<Mutex<HashMap<u64, Terminal>>> = OnceLock::new();

fn sessions() -> &'static Mutex<HashMap<u64, SshSession>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
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
    let mut sessions = sessions().lock().expect("session mutex poisoned");
    let session = match sessions.get_mut(&session_id) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };

    let output = session.read_output();
    if output.is_empty() {
        return std::ptr::null_mut();
    }

    // 更新终端
    let mut terminals = terminals().lock().expect("terminal mutex poisoned");
    if let Some(terminal) = terminals.get_mut(&session_id) {
        terminal.process(&output);
        let snapshot = terminal.snapshot();

        // 序列化为 JSON
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
    };

    into_c_string(state_str)
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
