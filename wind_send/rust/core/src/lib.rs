use std::collections::HashMap;
use std::ffi::{c_char, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<u64, MockSession>>> = OnceLock::new();

struct MockSession {
    cols: u16,
    rows: u16,
    tick: u64,
}

#[no_mangle]
pub extern "C" fn core_version() -> *mut c_char {
    into_c_string("rust core phase 0")
}

#[no_mangle]
pub extern "C" fn core_open_mock_session(cols: u16, rows: u16) -> u64 {
    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let session = MockSession {
        cols,
        rows,
        tick: 0,
    };
    sessions().lock().expect("session mutex poisoned").insert(session_id, session);
    session_id
}

#[no_mangle]
pub extern "C" fn core_poll_event(session_id: u64) -> *mut c_char {
    let mut sessions = sessions().lock().expect("session mutex poisoned");
    let Some(session) = sessions.get_mut(&session_id) else {
        return std::ptr::null_mut();
    };

    session.tick += 1;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or_default();
    let line = format!(
        "[rust] tick={} session={} size={}x{} unix={}",
        session.tick, session_id, session.cols, session.rows, now
    );
    let json = format!(
        "{{\"type\":\"terminal_line\",\"session_id\":{},\"line\":\"{}\"}}",
        session_id,
        escape_json(&line)
    );
    into_c_string(&json)
}

#[no_mangle]
pub extern "C" fn core_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

fn sessions() -> &'static Mutex<HashMap<u64, MockSession>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn into_c_string(value: &str) -> *mut c_char {
    CString::new(value)
        .expect("string contains interior nul")
        .into_raw()
}

fn escape_json(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            _ => escaped.push(ch),
        }
    }
    escaped
}
