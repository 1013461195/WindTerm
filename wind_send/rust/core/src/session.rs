use ssh2::Session;
use std::io::Read;
use std::net::TcpStream;
use std::sync::{Arc, Mutex};

/// SSH session 状态
#[derive(Debug, Clone, PartialEq)]
pub enum SessionState {
    Created,
    Connecting,
    Authenticating,
    Running,
    Closed,
    Error(String),
}

/// SSH session 配置
#[derive(Debug, Clone)]
pub struct SessionConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
}

/// SSH session 封装
pub struct SshSession {
    id: u64,
    config: SessionConfig,
    state: SessionState,
    session: Option<Session>,
    channel: Option<ssh2::Channel>,
    output_buffer: Arc<Mutex<Vec<u8>>>,
    cols: u16,
    rows: u16,
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
        }
    }

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

    /// 连接到 SSH 服务器
    pub fn connect(&mut self) -> Result<(), String> {
        self.state = SessionState::Connecting;

        // 建立 TCP 连接
        let addr = format!("{}:{}", self.config.host, self.config.port);
        let tcp = TcpStream::connect(&addr)
            .map_err(|e| format!("TCP 连接失败: {}", e))?;

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

        // 设置非阻塞模式，避免 read_output 阻塞 UI 线程
        channel.set_blocking(false);

        self.session = Some(session);
        self.channel = Some(channel);
        self.state = SessionState::Running;

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
                    Ok(n) => output.extend_from_slice(&buf[..n]),
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(_) => break,
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
