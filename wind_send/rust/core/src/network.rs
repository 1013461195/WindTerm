use serde::{Deserialize, Serialize};

/// 代理类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProxyType {
    None,
    Http,
    Socks5,
}

/// 代理配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyConfig {
    pub proxy_type: ProxyType,
    pub host: String,
    pub port: u16,
    pub username: Option<String>,
    pub password: Option<String>,
}

/// 跳板机配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JumpHostConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
    pub private_key_path: Option<String>,
}

/// 端口转发类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PortForwardType {
    Local,
    Remote,
    Dynamic,
}

/// 端口转发配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortForwardConfig {
    pub forward_type: PortForwardType,
    pub bind_address: String,
    pub bind_port: u16,
    pub remote_host: Option<String>,
    pub remote_port: Option<u16>,
}

/// Keepalive 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
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
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkConfig {
    pub proxy: Option<ProxyConfig>,
    pub jump_hosts: Vec<JumpHostConfig>,
    pub port_forwards: Vec<PortForwardConfig>,
    pub keepalive: KeepaliveConfig,
    pub reconnect: ReconnectPolicy,
    pub agent_forwarding: bool,
}

impl Default for NetworkConfig {
    fn default() -> Self {
        Self {
            proxy: None,
            jump_hosts: Vec::new(),
            port_forwards: Vec::new(),
            keepalive: KeepaliveConfig::default(),
            reconnect: ReconnectPolicy::default(),
            agent_forwarding: false,
        }
    }
}
