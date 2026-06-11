use ssh2::Session;
use std::io::Read;
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::network::{NetworkConfig, ProxyConfig, ProxyType, JumpHostConfig};

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
    pub auth_timeout: Duration,
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
            auth_timeout: Duration::from_secs(10),
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
}

impl SshSession {
    pub fn new(id: u64, config: SessionConfig) -> Self {
        Self {
            id,
            config,
            state: SessionState::Created,
            session: None,
            channel: None,
            output_buffer: Arc::new(Mutex::new(Vec::new())),
            cols: 80,
            rows: 24,
            connection_config: ConnectionConfig::default(),
            reconnect_attempts: 0,
            last_error: None,
            last_activity: Instant::now(),
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

    pub fn reconnect_attempts(&self) -> u32 {
        self.reconnect_attempts
    }

    pub fn is_connected(&self) -> bool {
        self.state == SessionState::Running
    }

    pub fn can_reconnect(&self) -> bool {
        self.reconnect_attempts < self.connection_config.max_reconnect_attempts
    }

    /// 设置连接配置
    pub fn set_connection_config(&mut self, config: ConnectionConfig) {
        self.connection_config = config;
    }

    /// 检查连接是否超时
    pub fn check_timeout(&mut self) -> bool {
        if self.state == SessionState::Running {
            if self.last_activity.elapsed() > self.connection_config.read_timeout {
                self.state = SessionState::Disconnected;
                self.last_error = Some("连接超时".to_string());
                return true;
            }
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

    /// 重置重连状态
    pub fn reset_reconnect(&mut self) {
        self.reconnect_attempts = 0;
        self.last_error = None;
    }

    /// 打开 SFTP 会话
    pub fn open_sftp(&self) -> Result<crate::sftp::SftpSession, String> {
        let session = self.session.as_ref().ok_or("SSH session 未打开")?;
        crate::sftp::SftpSession::new(session)
    }

    /// 直接连接
    fn connect_direct(&self) -> Result<TcpStream, String> {
        let addr = format!("{}:{}", self.config.host, self.config.port);
        let tcp = TcpStream::connect_timeout(
            &addr.parse().map_err(|e| format!("地址解析失败: {}", e))?,
            self.connection_config.connect_timeout,
        )
        .map_err(|e| format!("TCP 连接失败: {}", e))?;

        tcp.set_read_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置读超时失败: {}", e))?;
        tcp.set_write_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置写超时失败: {}", e))?;

        Ok(tcp)
    }

    /// 通过代理连接
    fn connect_through_proxy(&self, proxy: &ProxyConfig) -> Result<TcpStream, String> {
        // 连接到代理服务器
        let proxy_addr = format!("{}:{}", proxy.host, proxy.port);
        let tcp = TcpStream::connect_timeout(
            &proxy_addr.parse().map_err(|e| format!("代理地址解析失败: {}", e))?,
            self.connection_config.connect_timeout,
        )
        .map_err(|e| format!("连接代理服务器失败: {}", e))?;

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
    fn http_connect_proxy(&self, tcp: &TcpStream, _proxy_host: &str, _proxy_port: u16) -> Result<(), String> {
        use std::io::Write;

        let connect_request = format!(
            "CONNECT {}:{} HTTP/1.1\r\nHost: {}:{}\r\n\r\n",
            self.config.host, self.config.port, self.config.host, self.config.port
        );

        let mut stream = tcp.try_clone().map_err(|e| format!("克隆连接失败: {}", e))?;
        stream.write_all(connect_request.as_bytes()).map_err(|e| format!("发送 CONNECT 请求失败: {}", e))?;

        let mut response = [0u8; 1024];
        let n = stream.read(&mut response).map_err(|e| format!("读取代理响应失败: {}", e))?;
        let response_str = String::from_utf8_lossy(&response[..n]);

        if !response_str.contains("200") {
            return Err(format!("HTTP 代理连接失败: {}", response_str.lines().next().unwrap_or("")));
        }

        Ok(())
    }

    /// SOCKS5 代理
    fn socks5_connect(&self, tcp: &TcpStream, target_host: &str, target_port: u16) -> Result<(), String> {
        use std::io::Write;

        let mut stream = tcp.try_clone().map_err(|e| format!("克隆连接失败: {}", e))?;

        // SOCKS5 握手
        stream.write_all(&[0x05, 0x01, 0x00]).map_err(|e| format!("SOCKS5 握手失败: {}", e))?;

        let mut response = [0u8; 2];
        stream.read_exact(&mut response).map_err(|e| format!("读取 SOCKS5 响应失败: {}", e))?;

        if response[0] != 0x05 || response[1] != 0x00 {
            return Err("SOCKS5 握手失败".to_string());
        }

        // SOCKS5 连接请求
        let host_bytes = target_host.as_bytes();
        let mut request = vec![0x05, 0x01, 0x00, 0x03];
        request.push(host_bytes.len() as u8);
        request.extend_from_slice(host_bytes);
        request.push((target_port >> 8) as u8);
        request.push((target_port & 0xFF) as u8);

        stream.write_all(&request).map_err(|e| format!("发送 SOCKS5 连接请求失败: {}", e))?;

        let mut response = [0u8; 10];
        stream.read_exact(&mut response).map_err(|e| format!("读取 SOCKS5 连接响应失败: {}", e))?;

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

        // 连接到第一个跳板机
        let first_jump = &jump_hosts[0];
        let jump_addr = format!("{}:{}", first_jump.host, first_jump.port);
        let tcp = TcpStream::connect_timeout(
            &jump_addr.parse().map_err(|e| format!("跳板机地址解析失败: {}", e))?,
            self.connection_config.connect_timeout,
        )
        .map_err(|e| format!("连接跳板机失败: {}", e))?;

        tcp.set_read_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置读超时失败: {}", e))?;
        tcp.set_write_timeout(Some(self.connection_config.read_timeout))
            .map_err(|e| format!("设置写超时失败: {}", e))?;

        // 如果只有一个跳板机，通过它连接到目标
        if jump_hosts.len() == 1 {
            return self.connect_through_single_jump(tcp, first_jump);
        }

        // 多个跳板机的情况（简化处理，实际应该递归连接）
        self.connect_through_single_jump(tcp, first_jump)
    }

    /// 通过单个跳板机连接
    fn connect_through_single_jump(&self, tcp: TcpStream, jump: &JumpHostConfig) -> Result<TcpStream, String> {
        // 创建 SSH session 连接到跳板机
        let mut jump_session = Session::new()
            .map_err(|e| format!("创建跳板机 SSH session 失败: {}", e))?;

        jump_session.set_tcp_stream(tcp);
        jump_session
            .handshake()
            .map_err(|e| format!("跳板机 SSH 握手失败: {}", e))?;

        // 认证跳板机
        if let Some(ref password) = jump.password {
            jump_session
                .userauth_password(&jump.username, password)
                .map_err(|e| format!("跳板机认证失败: {}", e))?;
        } else {
            return Err("跳板机未提供密码".to_string());
        }

        // 通过跳板机建立 TCP 转发
        let target_addr = format!("{}:{}", self.config.host, self.config.port);
        let channel = jump_session
            .channel_direct_tcpip(&self.config.host, self.config.port, None)
            .map_err(|e| format!("通过跳板机建立转发失败: {}", e))?;

        // 使用 channel 作为 TCP 流
        // 注意：这里需要将 channel 包装为 TcpStream，但 ssh2 库不直接支持
        // 实际实现中可能需要使用其他方式
        Err("跳板机转发功能需要进一步实现".to_string())
    }

    /// 连接到 SSH 服务器
    pub fn connect(&mut self) -> Result<(), String> {
        self.state = SessionState::Connecting;
        self.last_error = None;

        // 根据网络配置建立连接
        let tcp = if !self.config.network.jump_hosts.is_empty() {
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
        let mut session = Session::new()
            .map_err(|e| format!("创建 SSH session 失败: {}", e))?;

        session.set_tcp_stream(tcp);
        session
            .handshake()
            .map_err(|e| format!("SSH 握手失败: {}", e))?;

        self.state = SessionState::Authenticating;

        // 密码认证
        if let Some(password) = &self.config.password {
            session
                .userauth_password(&self.config.username, password)
                .map_err(|e| format!("密码认证失败: {}", e))?;
        } else {
            return Err("未提供密码".to_string());
        }

        if !session.authenticated() {
            return Err("认证失败".to_string());
        }

        // 打开 channel
        let mut channel = session
            .channel_session()
            .map_err(|e| format!("打开 channel 失败: {}", e))?;

        // 请求 PTY
        channel
            .request_pty(
                "xterm-256color",
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

        self.session = Some(session);
        self.channel = Some(channel);
        self.state = SessionState::Running;
        self.last_activity = Instant::now();

        // 启动读取线程
        self.start_read_thread();

        Ok(())
    }

    /// 启动后台读取线程（简化版，实际读取在 read_output 中进行）
    fn start_read_thread(&mut self) {
        // TODO: 后续可实现异步读取线程
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
            channel
                .flush()
                .map_err(|e| format!("刷新失败: {}", e))?;
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
        if let Some(mut channel) = self.channel.take() {
            let _ = channel.close();
            let _ = channel.wait_close();
        }
        self.session = None;
        self.state = SessionState::Closed;
    }
}

impl Drop for SshSession {
    fn drop(&mut self) {
        self.close();
    }
}
