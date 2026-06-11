use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::protocol::{apply_newline, decode_to_utf8, encode_from_utf8, RawTcpConfig};

/// Raw TCP 会话状态
#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum RawTcpState {
    Created,
    Connecting,
    Connected,
    Closed,
    Error(String),
}

/// Raw TCP 会话
#[allow(dead_code)]
pub struct RawTcpSession {
    id: u64,
    config: RawTcpConfig,
    state: RawTcpState,
    stream: Option<TcpStream>,
    output_buffer: Arc<Mutex<Vec<u8>>>,
    cols: u16,
    rows: u16,
    last_activity: Instant,
}

#[allow(dead_code)]
impl RawTcpSession {
    pub fn new(id: u64, config: RawTcpConfig) -> Self {
        Self {
            id,
            config,
            state: RawTcpState::Created,
            stream: None,
            output_buffer: Arc::new(Mutex::new(Vec::new())),
            cols: 80,
            rows: 24,
            last_activity: Instant::now(),
        }
    }

    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn state(&self) -> &RawTcpState {
        &self.state
    }

    pub fn cols(&self) -> u16 {
        self.cols
    }

    pub fn rows(&self) -> u16 {
        self.rows
    }

    /// 连接到 Raw TCP 服务器
    pub fn connect(&mut self) -> Result<(), String> {
        self.state = RawTcpState::Connecting;

        let addr = format!("{}:{}", self.config.host, self.config.port);
        let stream = TcpStream::connect(&addr).map_err(|e| format!("TCP 连接失败: {}", e))?;

        stream
            .set_nonblocking(true)
            .map_err(|e| format!("设置非阻塞模式失败: {}", e))?;
        stream
            .set_write_timeout(Some(Duration::from_secs(30)))
            .map_err(|e| format!("设置写超时失败: {}", e))?;

        self.stream = Some(stream);
        self.state = RawTcpState::Connected;
        self.last_activity = Instant::now();

        Ok(())
    }

    /// 读取输出数据
    pub fn read_output(&mut self) -> Vec<u8> {
        let mut output = Vec::new();

        if let Some(stream) = &mut self.stream {
            let mut buf = [0u8; 4096];
            loop {
                match stream.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        output.extend_from_slice(&decode_to_utf8(&buf[..n], &self.config.encoding));
                        self.last_activity = Instant::now();
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut => break,
                    Err(_) => break,
                }
            }
        }

        output
    }

    /// 发送输入数据
    pub fn write_input(&mut self, data: &[u8]) -> Result<(), String> {
        if let Some(stream) = &mut self.stream {
            let encoded = encode_from_utf8(
                &apply_newline(data, &self.config.newline),
                &self.config.encoding,
            );
            stream
                .write_all(&encoded)
                .map_err(|e| format!("写入失败: {}", e))?;
            stream.flush().map_err(|e| format!("刷新失败: {}", e))?;
            self.last_activity = Instant::now();
            Ok(())
        } else {
            Err("连接未打开".to_string())
        }
    }

    /// 调整终端大小（Raw TCP 不需要实际调整，只更新本地状态）
    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<(), String> {
        self.cols = cols;
        self.rows = rows;
        Ok(())
    }

    /// 关闭会话
    pub fn close(&mut self) {
        self.stream = None;
        self.state = RawTcpState::Closed;
    }
}

impl Drop for RawTcpSession {
    fn drop(&mut self) {
        self.close();
    }
}
