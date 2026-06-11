use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

/// 代理类型
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProxyType {
    None,
    Http,
    Socks5,
}

/// 代理配置
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProxyConfig {
    #[serde(rename = "type")]
    pub proxy_type: ProxyType,
    pub host: String,
    pub port: u16,
    pub username: Option<String>,
    pub password: Option<String>,
}

/// 跳板机配置
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JumpHostConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
    pub private_key_path: Option<String>,
}

/// 端口转发类型
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PortForwardType {
    Local,
    Remote,
    Dynamic,
}

/// 端口转发配置
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PortForwardConfig {
    #[serde(rename = "type")]
    pub forward_type: PortForwardType,
    pub bind_address: String,
    pub bind_port: u16,
    pub remote_host: Option<String>,
    pub remote_port: Option<u16>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortForwardStatus {
    pub forward_type: PortForwardType,
    pub bind_address: String,
    pub bind_port: u16,
    pub remote_host: Option<String>,
    pub remote_port: Option<u16>,
    pub state: String,
    pub active_connections: u64,
    pub total_connections: u64,
    pub uploaded_bytes: u64,
    pub downloaded_bytes: u64,
    pub last_error: Option<String>,
}

pub struct PortForwardMetrics {
    pub config: PortForwardConfig,
    active_connections: AtomicU64,
    total_connections: AtomicU64,
    uploaded_bytes: AtomicU64,
    downloaded_bytes: AtomicU64,
    state: Mutex<String>,
    last_error: Mutex<Option<String>>,
}

impl PortForwardMetrics {
    pub fn new(config: PortForwardConfig) -> Self {
        Self {
            config,
            active_connections: AtomicU64::new(0),
            total_connections: AtomicU64::new(0),
            uploaded_bytes: AtomicU64::new(0),
            downloaded_bytes: AtomicU64::new(0),
            state: Mutex::new("starting".to_string()),
            last_error: Mutex::new(None),
        }
    }

    pub fn set_running(&self) {
        *self.state.lock().expect("forward state mutex poisoned") = "running".to_string();
    }

    pub fn set_stopped(&self) {
        let mut state = self.state.lock().expect("forward state mutex poisoned");
        if *state != "error" {
            *state = "stopped".to_string();
        }
    }

    pub fn set_error(&self, error: impl Into<String>) {
        let error = error.into();
        *self.state.lock().expect("forward state mutex poisoned") = "error".to_string();
        *self
            .last_error
            .lock()
            .expect("forward error mutex poisoned") = Some(error);
    }

    pub fn connection_opened(&self) {
        self.active_connections.fetch_add(1, Ordering::Relaxed);
        self.total_connections.fetch_add(1, Ordering::Relaxed);
    }

    pub fn connection_closed(&self) {
        self.active_connections.fetch_sub(1, Ordering::Relaxed);
    }

    pub fn add_uploaded(&self, bytes: u64) {
        self.uploaded_bytes.fetch_add(bytes, Ordering::Relaxed);
    }

    pub fn add_downloaded(&self, bytes: u64) {
        self.downloaded_bytes.fetch_add(bytes, Ordering::Relaxed);
    }

    pub fn snapshot(&self) -> PortForwardStatus {
        PortForwardStatus {
            forward_type: self.config.forward_type.clone(),
            bind_address: self.config.bind_address.clone(),
            bind_port: self.config.bind_port,
            remote_host: self.config.remote_host.clone(),
            remote_port: self.config.remote_port,
            state: self
                .state
                .lock()
                .expect("forward state mutex poisoned")
                .clone(),
            active_connections: self.active_connections.load(Ordering::Relaxed),
            total_connections: self.total_connections.load(Ordering::Relaxed),
            uploaded_bytes: self.uploaded_bytes.load(Ordering::Relaxed),
            downloaded_bytes: self.downloaded_bytes.load(Ordering::Relaxed),
            last_error: self
                .last_error
                .lock()
                .expect("forward error mutex poisoned")
                .clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{PortForwardConfig, PortForwardMetrics, PortForwardType};

    #[test]
    fn records_port_forward_traffic_and_connections() {
        let metrics = PortForwardMetrics::new(PortForwardConfig {
            forward_type: PortForwardType::Local,
            bind_address: "127.0.0.1".to_string(),
            bind_port: 8080,
            remote_host: Some("example.com".to_string()),
            remote_port: Some(80),
        });
        metrics.set_running();
        metrics.connection_opened();
        metrics.add_uploaded(12);
        metrics.add_downloaded(34);
        metrics.connection_closed();
        let status = metrics.snapshot();
        assert_eq!(status.state, "running");
        assert_eq!(status.active_connections, 0);
        assert_eq!(status.total_connections, 1);
        assert_eq!(status.uploaded_bytes, 12);
        assert_eq!(status.downloaded_bytes, 34);
    }
}

/// Keepalive 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeepaliveConfig {
    pub enabled: bool,
    pub interval_seconds: u32,
    pub max_misses: u32,
}

impl Default for KeepaliveConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            interval_seconds: 30,
            max_misses: 3,
        }
    }
}

/// 重连策略
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReconnectPolicy {
    pub enabled: bool,
    pub max_attempts: u32,
    pub initial_delay_ms: u32,
    pub max_delay_ms: u32,
    pub backoff_factor: f64,
    pub jitter: bool,
}

impl Default for ReconnectPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            max_attempts: 3,
            initial_delay_ms: 1000,
            max_delay_ms: 30000,
            backoff_factor: 2.0,
            jitter: true,
        }
    }
}

/// 网络配置
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NetworkConfig {
    pub proxy: Option<ProxyConfig>,
    pub proxy_command: Option<String>,
    pub jump_hosts: Vec<JumpHostConfig>,
    pub port_forwards: Vec<PortForwardConfig>,
    pub keepalive: KeepaliveConfig,
    pub reconnect: ReconnectPolicy,
    pub agent_forwarding: bool,
}
