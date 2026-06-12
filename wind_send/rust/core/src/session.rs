use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use ssh2::{CheckResult, ErrorCode, KnownHostFileKind, Session};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use crate::network::{
    JumpHostConfig, NetworkConfig, PortForwardConfig, PortForwardMetrics, PortForwardStatus,
    PortForwardType, ProxyConfig, ProxyType,
};

/// SSH session 状态
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum SessionState {
    Created,
    Connecting,
    Authenticating,
    Running,
    Closed,
    Error(String),
    Disconnected,
    Reconnecting,
}

/// 连接配置
#[derive(Debug, Clone)]
pub struct ConnectionConfig {
    pub connect_timeout: Duration,
    pub read_timeout: Duration,
    pub max_reconnect_attempts: u32,
    pub reconnect_delay: Duration,
    pub max_reconnect_delay: Duration,
    pub reconnect_backoff_factor: f64,
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        Self {
            connect_timeout: Duration::from_secs(15),
            read_timeout: Duration::from_secs(30),
            max_reconnect_attempts: 3,
            reconnect_delay: Duration::from_secs(1),
            max_reconnect_delay: Duration::from_secs(30),
            reconnect_backoff_factor: 2.0,
        }
    }
}

/// SSH session 配置
#[derive(Debug, Clone)]
pub struct SessionConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
    pub private_key_path: Option<String>,
    pub passphrase: Option<String>,
    pub known_hosts_path: Option<String>,
    pub accept_unknown_host: bool,
    pub connect_timeout_ms: u64,
    pub terminal_type: String,
    pub network: NetworkConfig,
}

/// SSH session 封装
#[allow(dead_code)]
pub struct SshSession {
    id: u64,
    config: SessionConfig,
    state: SessionState,
    session: Option<Session>,
    channel: Option<ssh2::Channel>,
    output_buffer: Arc<Mutex<Vec<u8>>>,
    cols: u16,
    rows: u16,
    connection_config: ConnectionConfig,
    reconnect_attempts: u32,
    last_error: Option<String>,
    last_activity: Instant,
    forwarding_stop: Arc<AtomicBool>,
    forwarding_threads: Vec<JoinHandle<()>>,
    forwarding_metrics: Vec<Arc<PortForwardMetrics>>,
}

impl SshSession {
    pub fn new(id: u64, config: SessionConfig) -> Self {
        let connection_config = ConnectionConfig {
            connect_timeout: Duration::from_millis(config.connect_timeout_ms.max(1000)),
            max_reconnect_attempts: if config.network.reconnect.enabled {
                config.network.reconnect.max_attempts
            } else {
                0
            },
            reconnect_delay: Duration::from_millis(
                config.network.reconnect.initial_delay_ms.into(),
            ),
            max_reconnect_delay: Duration::from_millis(
                config.network.reconnect.max_delay_ms.into(),
            ),
            reconnect_backoff_factor: config.network.reconnect.backoff_factor,
            ..ConnectionConfig::default()
        };
        Self {
            id,
            config,
            state: SessionState::Created,
            session: None,
            channel: None,
            output_buffer: Arc::new(Mutex::new(Vec::new())),
            cols: 80,
            rows: 24,
            connection_config,
            reconnect_attempts: 0,
            last_error: None,
            last_activity: Instant::now(),
            forwarding_stop: Arc::new(AtomicBool::new(false)),
            forwarding_threads: Vec::new(),
            forwarding_metrics: Vec::new(),
        }
    }

    #[allow(dead_code)]
    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn state(&self) -> &SessionState {
        &self.state
    }

    pub fn cols(&self) -> u16 {
        self.cols
    }

    pub fn rows(&self) -> u16 {
        self.rows
    }

    pub fn last_error(&self) -> Option<&str> {
        self.last_error.as_deref()
    }

    pub fn port_forward_status(&self) -> Vec<PortForwardStatus> {
        self.forwarding_metrics
            .iter()
            .map(|metrics| metrics.snapshot())
            .collect()
    }

    pub fn reconnect_attempts(&self) -> u32 {
        self.reconnect_attempts
    }

    pub fn can_reconnect(&self) -> bool {
        self.reconnect_attempts < self.connection_config.max_reconnect_attempts
    }

    /// 检查连接是否超时
    pub fn check_timeout(&mut self) -> bool {
        if self.state == SessionState::Running
            && self.last_activity.elapsed() > self.connection_config.read_timeout
        {
            self.state = SessionState::Disconnected;
            self.last_error = Some("连接超时".to_string());
            return true;
        }
        false
    }

    /// 尝试重新连接
    pub fn reconnect(&mut self) -> Result<(), String> {
        if !self.can_reconnect() {
            return Err("已达到最大重连次数".to_string());
        }

        self.state = SessionState::Reconnecting;
        self.reconnect_attempts += 1;

        // 计算退避延迟
        let delay = self.calculate_reconnect_delay();
        std::thread::sleep(delay);

        // 关闭旧连接
        self.close();

        // 尝试重新连接
        match self.connect() {
            Ok(()) => {
                self.reconnect_attempts = 0;
                Ok(())
            }
            Err(e) => {
                self.last_error = Some(e.clone());
                Err(e)
            }
        }
    }

    /// 计算重连延迟（指数退避）
    fn calculate_reconnect_delay(&self) -> Duration {
        let base_delay = self.connection_config.reconnect_delay.as_secs_f64();
        let backoff = self.connection_config.reconnect_backoff_factor;
        let max_delay = self.connection_config.max_reconnect_delay.as_secs_f64();

        let delay = base_delay * backoff.powi(self.reconnect_attempts as i32 - 1);
        Duration::from_secs_f64(delay.min(max_delay))
    }

    /// 打开 SFTP 会话
    pub fn open_sftp(&self) -> Result<crate::sftp::SftpSession, String> {
        if self.session.is_none() {
            return Err("SSH session 未打开".to_string());
        }
        let session = self.connect_authenticated_session()?;
        crate::sftp::SftpSession::new(&session)
    }

    /// 直接连接
    fn connect_direct(&self) -> Result<TcpStream, String> {
        let tcp = connect_with_timeout(
            &self.config.host,
            self.config.port,
            self.connection_config.connect_timeout,
        )?;

        tcp.set_read_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置读超时失败: {}", e))?;
        tcp.set_write_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置写超时失败: {}", e))?;

        Ok(tcp)
    }

    fn connect_through_proxy_command(&self, template: &str) -> Result<TcpStream, String> {
        let command = expand_proxy_command(template, &self.config.host, self.config.port);
        let mut child = if cfg!(windows) {
            Command::new("cmd")
                .args(["/D", "/S", "/C", &command])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
        } else {
            Command::new("sh")
                .args(["-c", &command])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
        }
        .map_err(|error| format!("启动 ProxyCommand 失败: {error}"))?;
        let child_stdin = child.stdin.take().ok_or("ProxyCommand stdin 不可用")?;
        let child_stdout = child.stdout.take().ok_or("ProxyCommand stdout 不可用")?;

        let listener =
            TcpListener::bind(("127.0.0.1", 0)).map_err(|e| format!("创建代理桥接失败: {e}"))?;
        let address = listener
            .local_addr()
            .map_err(|e| format!("读取代理桥接地址失败: {e}"))?;
        let client = TcpStream::connect(address).map_err(|e| format!("连接代理桥接失败: {e}"))?;
        let (server, _) = listener
            .accept()
            .map_err(|e| format!("接受代理桥接失败: {e}"))?;
        let mut server_writer = server
            .try_clone()
            .map_err(|e| format!("克隆代理桥接失败: {e}"))?;
        std::thread::spawn(move || {
            let mut output = child_stdout;
            let _ = std::io::copy(&mut output, &mut server_writer);
            let _ = server_writer.shutdown(std::net::Shutdown::Write);
        });
        std::thread::spawn(move || {
            let mut input = child_stdin;
            let mut server_reader = server;
            let _ = std::io::copy(&mut server_reader, &mut input);
            let _ = input.flush();
        });
        std::thread::spawn(move || {
            let _ = child.wait();
        });
        Ok(client)
    }

    /// 通过代理连接
    fn connect_through_proxy(&self, proxy: &ProxyConfig) -> Result<TcpStream, String> {
        // 连接到代理服务器
        let tcp = connect_with_timeout(
            &proxy.host,
            proxy.port,
            self.connection_config.connect_timeout,
        )
        .map_err(|e| format!("连接代理服务器失败: {e}"))?;

        tcp.set_read_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置读超时失败: {}", e))?;
        tcp.set_write_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置写超时失败: {}", e))?;

        match proxy.proxy_type {
            ProxyType::Http => {
                // HTTP CONNECT 代理
                self.http_connect_proxy(&tcp, &proxy.host, proxy.port)?;
            }
            ProxyType::Socks5 => {
                // SOCKS5 代理
                self.socks5_connect(&tcp, &self.config.host, self.config.port)?;
            }
            ProxyType::None => {}
        }

        Ok(tcp)
    }

    /// HTTP CONNECT 代理
    fn http_connect_proxy(
        &self,
        tcp: &TcpStream,
        _proxy_host: &str,
        _proxy_port: u16,
    ) -> Result<(), String> {
        use std::io::Write;

        let connect_request = format!(
            "CONNECT {}:{} HTTP/1.1\r\nHost: {}:{}\r\n{}\r\n",
            self.config.host,
            self.config.port,
            self.config.host,
            self.config.port,
            proxy_authorization_header(self.config.network.proxy.as_ref())
        );

        let mut stream = tcp
            .try_clone()
            .map_err(|e| format!("克隆连接失败: {}", e))?;
        stream
            .write_all(connect_request.as_bytes())
            .map_err(|e| format!("发送 CONNECT 请求失败: {}", e))?;

        let mut response = [0u8; 1024];
        let n = stream
            .read(&mut response)
            .map_err(|e| format!("读取代理响应失败: {}", e))?;
        let response_str = String::from_utf8_lossy(&response[..n]);

        if !response_str.contains("200") {
            return Err(format!(
                "HTTP 代理连接失败: {}",
                response_str.lines().next().unwrap_or("")
            ));
        }

        Ok(())
    }

    /// SOCKS5 代理
    fn socks5_connect(
        &self,
        tcp: &TcpStream,
        target_host: &str,
        target_port: u16,
    ) -> Result<(), String> {
        use std::io::Write;

        let mut stream = tcp
            .try_clone()
            .map_err(|e| format!("克隆连接失败: {}", e))?;

        let has_credentials = self
            .config
            .network
            .proxy
            .as_ref()
            .and_then(|proxy| proxy.username.as_ref())
            .is_some();
        let greeting: &[u8] = if has_credentials {
            &[0x05, 0x02, 0x00, 0x02]
        } else {
            &[0x05, 0x01, 0x00]
        };
        stream
            .write_all(greeting)
            .map_err(|e| format!("SOCKS5 握手失败: {}", e))?;

        let mut response = [0u8; 2];
        stream
            .read_exact(&mut response)
            .map_err(|e| format!("读取 SOCKS5 响应失败: {}", e))?;

        if response[0] != 0x05 || response[1] == 0xff {
            return Err("SOCKS5 握手失败".to_string());
        }
        if response[1] == 0x02 {
            let proxy = self.config.network.proxy.as_ref().ok_or("缺少代理配置")?;
            let username = proxy.username.as_deref().unwrap_or("").as_bytes();
            let password = proxy.password.as_deref().unwrap_or("").as_bytes();
            if username.len() > u8::MAX as usize || password.len() > u8::MAX as usize {
                return Err("SOCKS5 用户名或密码过长".to_string());
            }
            let mut auth = vec![0x01, username.len() as u8];
            auth.extend_from_slice(username);
            auth.push(password.len() as u8);
            auth.extend_from_slice(password);
            stream
                .write_all(&auth)
                .map_err(|e| format!("SOCKS5 认证失败: {e}"))?;
            stream
                .read_exact(&mut response)
                .map_err(|e| format!("读取 SOCKS5 认证响应失败: {e}"))?;
            if response[1] != 0x00 {
                return Err("SOCKS5 用户名密码认证失败".to_string());
            }
        } else if response[1] != 0x00 {
            return Err(format!("SOCKS5 不支持的认证方式: {}", response[1]));
        }

        // SOCKS5 连接请求
        let host_bytes = target_host.as_bytes();
        let mut request = vec![0x05, 0x01, 0x00, 0x03];
        request.push(host_bytes.len() as u8);
        request.extend_from_slice(host_bytes);
        request.push((target_port >> 8) as u8);
        request.push((target_port & 0xFF) as u8);

        stream
            .write_all(&request)
            .map_err(|e| format!("发送 SOCKS5 连接请求失败: {}", e))?;

        let mut response = [0u8; 10];
        stream
            .read_exact(&mut response)
            .map_err(|e| format!("读取 SOCKS5 连接响应失败: {}", e))?;

        if response[1] != 0x00 {
            return Err(format!("SOCKS5 连接失败，错误代码: {}", response[1]));
        }

        Ok(())
    }

    /// 通过跳板机连接
    fn connect_through_jump_hosts(&self) -> Result<TcpStream, String> {
        let jump_hosts = &self.config.network.jump_hosts;
        if jump_hosts.is_empty() {
            return self.connect_direct();
        }

        let first_jump = &jump_hosts[0];
        let mut transport = connect_with_timeout(
            &first_jump.host,
            first_jump.port,
            self.connection_config.connect_timeout,
        )
        .map_err(|e| format!("连接跳板机失败: {e}"))?;

        for (index, jump) in jump_hosts.iter().enumerate() {
            let (target_host, target_port) = if let Some(next) = jump_hosts.get(index + 1) {
                (next.host.as_str(), next.port)
            } else {
                (self.config.host.as_str(), self.config.port)
            };
            transport =
                self.connect_through_single_jump(transport, jump, target_host, target_port)?;
        }
        Ok(transport)
    }

    fn connect_through_single_jump(
        &self,
        tcp: TcpStream,
        jump: &JumpHostConfig,
        target_host: &str,
        target_port: u16,
    ) -> Result<TcpStream, String> {
        let mut jump_session =
            Session::new().map_err(|e| format!("创建跳板机 SSH session 失败: {}", e))?;

        jump_session.set_tcp_stream(tcp);
        jump_session
            .handshake()
            .map_err(|e| format!("跳板机 SSH 握手失败: {}", e))?;

        if let Some(private_key_path) = &jump.private_key_path {
            jump_session
                .userauth_pubkey_file(
                    &jump.username,
                    None,
                    Path::new(private_key_path),
                    jump.password.as_deref(),
                )
                .map_err(|e| format!("跳板机私钥认证失败: {e}"))?;
        } else if let Some(ref password) = jump.password {
            jump_session
                .userauth_password(&jump.username, password)
                .map_err(|e| format!("跳板机认证失败: {}", e))?;
        } else {
            authenticate_with_agent(&jump_session, &jump.username)
                .map_err(|e| format!("跳板机 {e}"))?;
        }

        let channel = jump_session
            .channel_direct_tcpip(target_host, target_port, None)
            .map_err(|e| format!("通过跳板机建立转发失败: {}", e))?;
        bridge_channel_to_tcp(channel)
    }

    /// 连接到 SSH 服务器
    pub fn connect(&mut self) -> Result<(), String> {
        self.state = SessionState::Connecting;
        self.last_error = None;
        let session = self.connect_authenticated_session()?;
        self.state = SessionState::Authenticating;

        // 打开 channel
        let mut channel = session
            .channel_session()
            .map_err(|e| format!("打开 channel 失败: {}", e))?;
        if self.config.network.agent_forwarding {
            channel
                .request_auth_agent_forwarding()
                .map_err(|e| format!("启用 agent forwarding 失败: {e}"))?;
        }

        // 请求 PTY
        channel
            .request_pty(
                &self.config.terminal_type,
                None,
                Some((self.cols as u32, self.rows as u32, 0, 0)),
            )
            .map_err(|e| format!("请求 PTY 失败: {}", e))?;

        // 请求 shell
        channel
            .shell()
            .map_err(|e| format!("请求 shell 失败: {}", e))?;

        // 所有阻塞操作完成，设置非阻塞模式用于后续 read_output
        session.set_blocking(false);
        self.forwarding_stop = Arc::new(AtomicBool::new(false));
        let (threads, metrics) = start_port_forwards(
            &session,
            &self.config.network.port_forwards,
            &self.forwarding_stop,
        )?;
        self.forwarding_threads = threads;
        self.forwarding_metrics = metrics;

        self.session = Some(session);
        self.channel = Some(channel);
        self.state = SessionState::Running;
        self.last_activity = Instant::now();

        // 启动读取线程
        self.start_read_thread();

        Ok(())
    }

    fn connect_authenticated_session(&self) -> Result<Session, String> {
        // 根据网络配置建立连接
        let tcp = if let Some(command) = self
            .config
            .network
            .proxy_command
            .as_deref()
            .filter(|command| !command.trim().is_empty())
        {
            self.connect_through_proxy_command(command)?
        } else if !self.config.network.jump_hosts.is_empty() {
            // 通过跳板机连接
            self.connect_through_jump_hosts()?
        } else if let Some(ref proxy) = self.config.network.proxy {
            // 通过代理连接
            self.connect_through_proxy(proxy)?
        } else {
            // 直接连接
            self.connect_direct()?
        };

        // 创建 SSH session
        let mut session = Session::new().map_err(|e| format!("创建 SSH session 失败: {}", e))?;

        session.set_tcp_stream(tcp);
        session
            .handshake()
            .map_err(|e| format!("SSH 握手失败: {}", e))?;

        if self.config.network.keepalive.enabled {
            session.set_keepalive(true, self.config.network.keepalive.interval_seconds.max(1));
        }
        self.verify_host_key(&session)?;

        if let Some(private_key_path) = &self.config.private_key_path {
            session
                .userauth_pubkey_file(
                    &self.config.username,
                    None,
                    Path::new(private_key_path),
                    self.config.passphrase.as_deref(),
                )
                .map_err(|e| format!("私钥认证失败: {e}"))?;
        } else if let Some(password) = &self.config.password {
            session
                .userauth_password(&self.config.username, password)
                .map_err(|e| format!("密码认证失败: {}", e))?;
        } else {
            authenticate_with_agent(&session, &self.config.username)?;
        }

        if !session.authenticated() {
            return Err("认证失败".to_string());
        }
        Ok(session)
    }

    fn verify_host_key(&self, session: &Session) -> Result<(), String> {
        let (host_key, key_type) = session
            .host_key()
            .ok_or_else(|| "服务器未提供 host key".to_string())?;
        let path = self.known_hosts_path();
        let fingerprint = session
            .host_key_hash(ssh2::HashType::Sha256)
            .map(|hash| format!("SHA256:{}", BASE64.encode(hash)))
            .unwrap_or_else(|| "SHA256:unavailable".to_string());
        let mut known_hosts = session
            .known_hosts()
            .map_err(|e| format!("初始化 known_hosts 失败: {e}"))?;

        if path.exists() {
            known_hosts
                .read_file(&path, KnownHostFileKind::OpenSSH)
                .map_err(|e| format!("读取 {} 失败: {e}", path.display()))?;
        }

        match known_hosts.check_port(&self.config.host, self.config.port, host_key) {
            CheckResult::Match => Ok(()),
            CheckResult::Mismatch => Err(format!(
                "HOST_KEY_CHANGED: {}:{} 的主机密钥已变更，连接已拒绝；算法={key_type:?}；指纹={fingerprint}",
                self.config.host, self.config.port,
            )),
            CheckResult::Failure => Err("HOST_KEY_ERROR: 无法校验主机密钥".to_string()),
            CheckResult::NotFound if !self.config.accept_unknown_host => Err(format!(
                "HOST_KEY_UNKNOWN: {}:{} 不在 known_hosts 中；算法={key_type:?}；指纹={fingerprint}",
                self.config.host, self.config.port,
            )),
            CheckResult::NotFound => {
                if let Some(parent) = path.parent() {
                    std::fs::create_dir_all(parent)
                        .map_err(|e| format!("创建 known_hosts 目录失败: {e}"))?;
                }
                let host = if self.config.port == 22 {
                    self.config.host.clone()
                } else {
                    format!("[{}]:{}", self.config.host, self.config.port)
                };
                known_hosts
                    .add(&host, host_key, "WindSend", key_type.into())
                    .map_err(|e| format!("添加 known_hosts 记录失败: {e}"))?;
                known_hosts
                    .write_file(&path, KnownHostFileKind::OpenSSH)
                    .map_err(|e| format!("写入 {} 失败: {e}", path.display()))
            }
        }
    }

    fn known_hosts_path(&self) -> PathBuf {
        if let Some(path) = self
            .config
            .known_hosts_path
            .as_deref()
            .filter(|path| !path.is_empty())
        {
            return PathBuf::from(path);
        }
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("."))
            .join(".ssh")
            .join("known_hosts")
    }

    /// 启动后台读取线程（简化版，实际读取在 read_output 中进行）
    fn start_read_thread(&mut self) {
        // 当前由 Flutter 50ms 轮询驱动非阻塞读取，避免额外线程与回调生命周期。
    }

    /// 读取输出数据
    pub fn read_output(&mut self) -> Vec<u8> {
        let mut output = Vec::new();

        if let Some(channel) = &mut self.channel {
            let mut buf = [0u8; 4096];
            loop {
                match channel.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        output.extend_from_slice(&buf[..n]);
                        self.last_activity = Instant::now();
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(e) => {
                        // 检查是否是连接错误
                        if e.kind() == std::io::ErrorKind::ConnectionAborted
                            || e.kind() == std::io::ErrorKind::ConnectionReset
                            || e.kind() == std::io::ErrorKind::BrokenPipe
                        {
                            self.state = SessionState::Disconnected;
                            self.last_error = Some(format!("连接断开: {}", e));
                        }
                        break;
                    }
                }
            }
        }

        output
    }

    /// 发送输入数据
    pub fn write_input(&mut self, data: &[u8]) -> Result<(), String> {
        if let Some(channel) = &mut self.channel {
            use std::io::Write;
            channel
                .write_all(data)
                .map_err(|e| format!("写入失败: {}", e))?;
            channel.flush().map_err(|e| format!("刷新失败: {}", e))?;
            self.last_activity = Instant::now();
            Ok(())
        } else {
            Err("Channel 未打开".to_string())
        }
    }

    /// 调整终端大小
    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<(), String> {
        self.cols = cols;
        self.rows = rows;

        if let Some(channel) = &mut self.channel {
            channel
                .request_pty_size(cols as u32, rows as u32, None, None)
                .map_err(|e| format!("调整大小失败: {}", e))?;
            Ok(())
        } else {
            Err("Channel 未打开".to_string())
        }
    }

    /// 关闭 session
    pub fn close(&mut self) {
        self.forwarding_stop.store(true, AtomicOrdering::Relaxed);
        if let Some(mut channel) = self.channel.take() {
            let _ = channel.close();
            let _ = channel.wait_close();
        }
        self.session = None;
        for thread in self.forwarding_threads.drain(..) {
            let _ = thread.join();
        }
        for metrics in &self.forwarding_metrics {
            metrics.set_stopped();
        }
        self.state = SessionState::Closed;
    }
}

fn expand_proxy_command(template: &str, host: &str, port: u16) -> String {
    const PERCENT_TOKEN: &str = "__WIND_SEND_PERCENT__";
    template
        .replace("%%", PERCENT_TOKEN)
        .replace("%h", &shell_quote(host))
        .replace("%p", &port.to_string())
        .replace(PERCENT_TOKEN, "%")
}

#[cfg(not(windows))]
fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

#[cfg(windows)]
fn shell_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

fn proxy_authorization_header(proxy: Option<&ProxyConfig>) -> String {
    let Some(proxy) = proxy else {
        return String::new();
    };
    let Some(username) = proxy.username.as_deref() else {
        return String::new();
    };
    let credentials = format!("{}:{}", username, proxy.password.as_deref().unwrap_or(""));
    format!(
        "Proxy-Authorization: Basic {}\r\n",
        BASE64.encode(credentials)
    )
}

fn authenticate_with_agent(session: &Session, username: &str) -> Result<(), String> {
    let mut agent = session
        .agent()
        .map_err(|e| format!("创建 SSH agent 客户端失败: {e}"))?;
    agent
        .connect()
        .map_err(|e| format!("连接 SSH agent 失败: {e}"))?;
    agent
        .list_identities()
        .map_err(|e| format!("读取 SSH agent 密钥失败: {e}"))?;
    for identity in agent.identities().map_err(|e| e.to_string())? {
        if agent.userauth(username, &identity).is_ok() {
            return Ok(());
        }
    }
    Err("SSH agent 中没有可用密钥".to_string())
}

fn bridge_channel_to_tcp(channel: ssh2::Channel) -> Result<TcpStream, String> {
    use std::io::Write;

    let listener =
        TcpListener::bind(("127.0.0.1", 0)).map_err(|e| format!("创建跳板桥接失败: {e}"))?;
    let address = listener
        .local_addr()
        .map_err(|e| format!("读取跳板桥接地址失败: {e}"))?;
    let client = TcpStream::connect(address).map_err(|e| format!("连接跳板桥接失败: {e}"))?;
    let (server, _) = listener
        .accept()
        .map_err(|e| format!("接受跳板桥接失败: {e}"))?;
    let mut server_writer = server
        .try_clone()
        .map_err(|e| format!("克隆跳板桥接失败: {e}"))?;
    let mut channel_reader = channel.clone();
    let mut channel_writer = channel;

    std::thread::spawn(move || {
        let _ = std::io::copy(&mut channel_reader, &mut server_writer);
        let _ = server_writer.shutdown(std::net::Shutdown::Write);
    });
    std::thread::spawn(move || {
        let mut server_reader = server;
        let _ = std::io::copy(&mut server_reader, &mut channel_writer);
        let _ = channel_writer.flush();
        let _ = channel_writer.send_eof();
    });
    Ok(client)
}

type PortForwardWorkers = (Vec<JoinHandle<()>>, Vec<Arc<PortForwardMetrics>>);

fn start_port_forwards(
    session: &Session,
    configs: &[PortForwardConfig],
    stop: &Arc<AtomicBool>,
) -> Result<PortForwardWorkers, String> {
    let mut threads = Vec::new();
    let mut all_metrics = Vec::new();
    for config in configs {
        let metrics = Arc::new(PortForwardMetrics::new(config.clone()));
        all_metrics.push(Arc::clone(&metrics));
        match config.forward_type {
            PortForwardType::Local | PortForwardType::Dynamic => {
                let listener = TcpListener::bind((&*config.bind_address, config.bind_port))
                    .map_err(|e| {
                        let error = format!(
                            "监听 {}:{} 失败: {e}",
                            config.bind_address, config.bind_port
                        );
                        metrics.set_error(error.clone());
                        error
                    })?;
                listener
                    .set_nonblocking(true)
                    .map_err(|e| format!("设置端口转发监听失败: {e}"))?;
                metrics.set_running();
                let session = session.clone();
                let config = config.clone();
                let stop = Arc::clone(stop);
                let listener_metrics = Arc::clone(&metrics);
                threads.push(std::thread::spawn(move || {
                    while !stop.load(AtomicOrdering::Relaxed) {
                        match listener.accept() {
                            Ok((socket, _)) => {
                                let session = session.clone();
                                let config = config.clone();
                                let stop = Arc::clone(&stop);
                                let metrics = Arc::clone(&listener_metrics);
                                std::thread::spawn(move || {
                                    metrics.connection_opened();
                                    let target = if matches!(
                                        config.forward_type,
                                        PortForwardType::Dynamic
                                    ) {
                                        match read_socks5_target(&socket) {
                                            Ok(target) => target,
                                            Err(error) => {
                                                metrics.set_error(error);
                                                metrics.connection_closed();
                                                return;
                                            }
                                        }
                                    } else {
                                        let Some(host) = config.remote_host.clone() else {
                                            metrics.set_error("本地转发缺少目标主机");
                                            metrics.connection_closed();
                                            return;
                                        };
                                        let Some(port) = config.remote_port else {
                                            metrics.set_error("本地转发缺少目标端口");
                                            metrics.connection_closed();
                                            return;
                                        };
                                        (host, port)
                                    };
                                    match open_direct_channel(&session, &target.0, target.1, &stop)
                                    {
                                        Ok(channel) => bridge_forward_connection(
                                            socket,
                                            channel,
                                            stop,
                                            Arc::clone(&metrics),
                                        ),
                                        Err(error) => metrics.set_error(error),
                                    }
                                    metrics.connection_closed();
                                });
                            }
                            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                                std::thread::sleep(Duration::from_millis(25));
                            }
                            Err(error) => {
                                listener_metrics
                                    .set_error(format!("接受端口转发连接失败: {error}"));
                                break;
                            }
                        }
                    }
                    listener_metrics.set_stopped();
                }));
            }
            PortForwardType::Remote => {
                let mut listener =
                    open_remote_listener(session, &config.bind_address, config.bind_port, stop)?;
                metrics.set_running();
                let target_host = config
                    .remote_host
                    .clone()
                    .ok_or("远程转发缺少本地目标主机")?;
                let target_port = config.remote_port.ok_or("远程转发缺少本地目标端口")?;
                let stop = Arc::clone(stop);
                let listener_metrics = Arc::clone(&metrics);
                threads.push(std::thread::spawn(move || {
                    while !stop.load(AtomicOrdering::Relaxed) {
                        match listener.accept() {
                            Ok(channel) => {
                                listener_metrics.connection_opened();
                                match TcpStream::connect((&*target_host, target_port)) {
                                    Ok(socket) => bridge_forward_connection(
                                        socket,
                                        channel,
                                        Arc::clone(&stop),
                                        Arc::clone(&listener_metrics),
                                    ),
                                    Err(error) => listener_metrics
                                        .set_error(format!("连接远程转发目标失败: {error}")),
                                }
                                listener_metrics.connection_closed();
                            }
                            Err(error) if error.code() == ErrorCode::Session(-37) => {
                                std::thread::sleep(Duration::from_millis(25));
                            }
                            Err(error) => {
                                listener_metrics.set_error(format!("接受远程转发失败: {error}"));
                                break;
                            }
                        }
                    }
                    listener_metrics.set_stopped();
                }));
            }
        }
    }
    Ok((threads, all_metrics))
}

fn open_remote_listener(
    session: &Session,
    bind_address: &str,
    bind_port: u16,
    stop: &Arc<AtomicBool>,
) -> Result<ssh2::Listener, String> {
    while !stop.load(AtomicOrdering::Relaxed) {
        match session.channel_forward_listen(bind_port, Some(bind_address), Some(32)) {
            Ok((listener, _)) => return Ok(listener),
            Err(error) if error.code() == ErrorCode::Session(-37) => {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(error) => return Err(format!("创建远程端口转发失败: {error}")),
        }
    }
    Err("端口转发已停止".to_string())
}

fn open_direct_channel(
    session: &Session,
    host: &str,
    port: u16,
    stop: &Arc<AtomicBool>,
) -> Result<ssh2::Channel, String> {
    while !stop.load(AtomicOrdering::Relaxed) {
        match session.channel_direct_tcpip(host, port, None) {
            Ok(channel) => return Ok(channel),
            Err(error) if error.code() == ErrorCode::Session(-37) => {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(error) => return Err(format!("建立转发 channel 失败: {error}")),
        }
    }
    Err("端口转发已停止".to_string())
}

fn bridge_forward_connection(
    socket: TcpStream,
    channel: ssh2::Channel,
    stop: Arc<AtomicBool>,
    metrics: Arc<PortForwardMetrics>,
) {
    let _ = socket.set_read_timeout(Some(Duration::from_millis(100)));
    let _ = socket.set_write_timeout(Some(Duration::from_millis(100)));
    let Ok(mut socket_writer) = socket.try_clone() else {
        return;
    };
    let mut socket_reader = socket;
    let mut channel_reader = channel.clone();
    let mut channel_writer = channel;
    let read_stop = Arc::clone(&stop);
    let read_metrics = Arc::clone(&metrics);
    let reader = std::thread::spawn(move || {
        copy_nonblocking(
            &mut channel_reader,
            &mut socket_writer,
            &read_stop,
            |bytes| read_metrics.add_downloaded(bytes),
        );
    });
    copy_nonblocking(&mut socket_reader, &mut channel_writer, &stop, |bytes| {
        metrics.add_uploaded(bytes)
    });
    let _ = channel_writer.send_eof();
    let _ = reader.join();
}

fn copy_nonblocking<R: std::io::Read, W: std::io::Write, F: Fn(u64)>(
    reader: &mut R,
    writer: &mut W,
    stop: &Arc<AtomicBool>,
    on_progress: F,
) {
    let mut buffer = [0u8; 32 * 1024];
    while !stop.load(AtomicOrdering::Relaxed) {
        match reader.read(&mut buffer) {
            Ok(0) => break,
            Ok(read) => {
                if writer.write_all(&buffer[..read]).is_err() {
                    break;
                }
                on_progress(read as u64);
                let _ = writer.flush();
            }
            Err(error)
                if error.kind() == std::io::ErrorKind::WouldBlock
                    || error.kind() == std::io::ErrorKind::TimedOut =>
            {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(_) => break,
        }
    }
}

fn read_socks5_target(socket: &TcpStream) -> Result<(String, u16), String> {
    use std::io::Write;
    let mut stream = socket
        .try_clone()
        .map_err(|e| format!("克隆 SOCKS5 客户端失败: {e}"))?;
    stream
        .set_nonblocking(false)
        .map_err(|e| format!("设置 SOCKS5 握手模式失败: {e}"))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .map_err(|e| e.to_string())?;
    let mut greeting = [0u8; 2];
    stream
        .read_exact(&mut greeting)
        .map_err(|e| format!("读取 SOCKS5 握手失败: {e}"))?;
    if greeting[0] != 5 {
        return Err("不是 SOCKS5 请求".to_string());
    }
    let mut methods = vec![0u8; greeting[1] as usize];
    stream.read_exact(&mut methods).map_err(|e| e.to_string())?;
    if !methods.contains(&0) {
        let _ = stream.write_all(&[5, 0xff]);
        return Err("SOCKS5 客户端不支持无认证模式".to_string());
    }
    stream.write_all(&[5, 0]).map_err(|e| e.to_string())?;
    let mut header = [0u8; 4];
    stream.read_exact(&mut header).map_err(|e| e.to_string())?;
    if header[0] != 5 || header[1] != 1 {
        return Err("仅支持 SOCKS5 CONNECT".to_string());
    }
    let host = match header[3] {
        1 => {
            let mut address = [0u8; 4];
            stream.read_exact(&mut address).map_err(|e| e.to_string())?;
            std::net::Ipv4Addr::from(address).to_string()
        }
        3 => {
            let mut length = [0u8; 1];
            stream.read_exact(&mut length).map_err(|e| e.to_string())?;
            let mut host = vec![0u8; length[0] as usize];
            stream.read_exact(&mut host).map_err(|e| e.to_string())?;
            String::from_utf8(host).map_err(|_| "无效的 SOCKS5 主机名".to_string())?
        }
        4 => {
            let mut address = [0u8; 16];
            stream.read_exact(&mut address).map_err(|e| e.to_string())?;
            std::net::Ipv6Addr::from(address).to_string()
        }
        _ => return Err("不支持的 SOCKS5 地址类型".to_string()),
    };
    let mut port = [0u8; 2];
    stream.read_exact(&mut port).map_err(|e| e.to_string())?;
    stream
        .write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        .map_err(|e| e.to_string())?;
    Ok((host, u16::from_be_bytes(port)))
}

impl Drop for SshSession {
    fn drop(&mut self) {
        self.close();
    }
}

fn connect_with_timeout(host: &str, port: u16, timeout: Duration) -> Result<TcpStream, String> {
    let addresses = (host, port)
        .to_socket_addrs()
        .map_err(|e| format!("解析地址 {host}:{port} 失败: {e}"))?;
    let mut last_error = None;

    for address in addresses {
        match TcpStream::connect_timeout(&address, timeout) {
            Ok(stream) => return Ok(stream),
            Err(error) => last_error = Some(error),
        }
    }

    Err(match last_error {
        Some(error) => format!("TCP 连接 {host}:{port} 失败: {error}"),
        None => format!("主机 {host} 没有可用地址"),
    })
}

#[cfg(test)]
mod proxy_command_tests {
    use super::expand_proxy_command;

    #[test]
    fn expands_and_quotes_proxy_command_tokens() {
        let command = expand_proxy_command(
            "proxy --host %h --port %p --literal %%",
            "host; echo unsafe",
            2222,
        );
        assert!(command.contains("--port 2222"));
        assert!(command.contains("--literal %"));
        assert!(!command.contains("--host host; echo unsafe"));
    }
}
