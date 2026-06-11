#![allow(dead_code)]

use serde::{Deserialize, Serialize};

/// 安全级别
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SecurityLevel {
    Low,
    Medium,
    High,
    Maximum,
}

/// 凭据存储方式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CredentialStorage {
    None,
    Platform,
    Vault,
}

/// 安全配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    pub credential_storage: CredentialStorage,
    pub master_password_enabled: bool,
    pub host_key_pinning: bool,
    pub audit_log_enabled: bool,
    pub audit_log_path: Option<String>,
    pub level: SecurityLevel,
    pub clipboard_auto_clear: bool,
    pub clipboard_auto_clear_seconds: u32,
    pub osc52_disabled: bool,
    pub paste_confirmation: bool,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            credential_storage: CredentialStorage::None,
            master_password_enabled: false,
            host_key_pinning: true,
            audit_log_enabled: false,
            audit_log_path: None,
            level: SecurityLevel::Medium,
            clipboard_auto_clear: false,
            clipboard_auto_clear_seconds: 30,
            osc52_disabled: true,
            paste_confirmation: true,
        }
    }
}

/// Host Key 状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum HostKeyStatus {
    Ok,
    Unknown,
    Changed,
    OtherAlgorithm,
    NotFound,
    Error,
}

/// Host Key 信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostKeyInfo {
    pub host: String,
    pub port: u16,
    pub algorithm: String,
    pub fingerprint_sha256: String,
    pub fingerprint_md5: Option<String>,
    pub status: HostKeyStatus,
    pub last_seen: Option<String>,
}

/// 审计日志条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditLogEntry {
    pub timestamp: String,
    pub session_id: String,
    pub action: String,
    pub detail: Option<String>,
    pub user: Option<String>,
    pub host: Option<String>,
}
