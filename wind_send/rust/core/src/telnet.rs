use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::protocol::TelnetConfig;

/// Telnet 会话状态
#[derive(Debug, Clone, PartialEq)]
pub enum TelnetState {
    Created,
    Connecting,
    Connected,
    Closed,
    Error(String),
}

/// Telnet 会话
pub struct TelnetSession {
    id: u64,
    config: TelnetConfig,
    state: TelnetState,
    stream: Option<TcpStream>,
    output_buffer: Arc<Mutex<Vec<u8>>>,
    cols: u16,
    rows: u16,
    last_activity: Instant,
}

impl TelnetSession {
    pub fn new(id: u64, config: TelnetConfig) -> Self {
        Self {
            id,
            config,
            state: TelnetState::Created,
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

    pub fn state(&self) -> &TelnetState {
        &self.state
    }

    pub fn cols(&self) -> u16 {
        self.cols
    }

    pub fn rows(&self) -> u16 {
        self.rows
    }

    /// 连接到 Telnet 服务器
    pub fn connect(&mut self) -> Result<(), String> {
        self.state = TelnetState::Connecting;

        let addr = format!("{}:{}", self.config.host, self.config.port);
        let stream = TcpStream::connect(&addr)
            .map_err(|e| format!("TCP 连接失败: {}", e))?;

        stream.set_read_timeout(Some(Duration::from_secs(30)))
            .map_err(|e| format!("设置读超时失败: {}", e))?;
        stream.set_write_timeout(Some(Duration::from_secs(30)))
            .map_err(|e| format!("设置写超时失败: {}", e))?;

        self.stream = Some(stream);
        self.state = TelnetState::Connected;
        self.last_activity = Instant::now();

        // 发送初始协商
        self.send_initial_negotiation()?;

        Ok(())
    }

    /// 发送初始 Telnet 协商
    fn send_initial_negotiation(&mut self) -> Result<(), String> {
        if let Some(stream) = &mut self.stream {
            // 发送 NAWS 协商
            if self.config.naws {
                let naws_cmd = [
                    0xFF, 0xFB, 0x1F, // IAC WILL NAWS
                ];
                stream.write_all(&naws_cmd)
                    .map_err(|e| format!("发送 NAWS 协商失败: {}", e))?;
            }

            // 发送 TTYPE 协商
            if self.config.ttype {
                let ttype_cmd = [
                    0xFF, 0xFB, 0x18, // IAC WILL TTYPE
                ];
                stream.write_all(&ttype_cmd)
                    .map_err(|e| format!("发送 TTYPE 协商失败: {}", e))?;
            }

            // 发送 SGA 协商
            if self.config.sga {
                let sga_cmd = [
                    0xFF, 0xFB, 0x03, // IAC WILL SGA
                ];
                stream.write_all(&sga_cmd)
                    .map_err(|e| format!("发送 SGA 协商失败: {}", e))?;
            }

            stream.flush()
                .map_err(|e| format!("刷新失败: {}", e))?;
        }

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
                        // 处理 Telnet IAC 命令
                        let processed = Self::process_telnet_commands_static(&buf[..n]);
                        output.extend_from_slice(&processed);
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

    /// 处理 Telnet IAC 命令（静态方法）
    fn process_telnet_commands_static(data: &[u8]) -> Vec<u8> {
        let mut result = Vec::new();
        let mut i = 0;

        while i < data.len() {
            if data[i] == 0xFF && i + 1 < data.len() {
                // IAC 命令
                match data[i + 1] {
                    0xFB => {
                        // WILL
                        if i + 2 < data.len() {
                            // 回复 DO
                            result.push(0xFF);
                            result.push(0xFD);
                            result.push(data[i + 2]);
                            i += 3;
                        } else {
                            break;
                        }
                    }
                    0xFC => {
                        // WON'T
                        i += 3;
                    }
                    0xFD => {
                        // DO
                        if i + 2 < data.len() {
                            // 回复 WILL
                            result.push(0xFF);
                            result.push(0xFB);
                            result.push(data[i + 2]);
                            i += 3;
                        } else {
                            break;
                        }
                    }
                    0xFE => {
                        // DON'T
                        i += 3;
                    }
                    0xFA => {
                        // SB (子协商开始)
                        // 跳过到 SE
                        while i < data.len() && data[i] != 0xF0 {
                            i += 1;
                        }
                        if i < data.len() {
                            i += 1; // 跳过 SE
                        }
                    }
                    _ => {
                        i += 2;
                    }
                }
            } else {
                result.push(data[i]);
                i += 1;
            }
        }

        result
    }

    /// 发送输入数据
    pub fn write_input(&mut self, data: &[u8]) -> Result<(), String> {
        if let Some(stream) = &mut self.stream {
            stream.write_all(data)
                .map_err(|e| format!("写入失败: {}", e))?;
            stream.flush()
                .map_err(|e| format!("刷新失败: {}", e))?;
            self.last_activity = Instant::now();
            Ok(())
        } else {
            Err("连接未打开".to_string())
        }
    }

    /// 调整终端大小
    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<(), String> {
        self.cols = cols;
        self.rows = rows;

        // 发送 NAWS 窗口大小
        if self.config.naws {
            if let Some(stream) = &mut self.stream {
                let naws_data = [
                    0xFF, 0xFA, 0x1F, // IAC SB NAWS
                    (cols >> 8) as u8, (cols & 0xFF) as u8,
                    (rows >> 8) as u8, (rows & 0xFF) as u8,
                    0xFF, 0xF0, // IAC SE
                ];
                stream.write_all(&naws_data)
                    .map_err(|e| format!("发送 NAWS 大小失败: {}", e))?;
                stream.flush()
                    .map_err(|e| format!("刷新失败: {}", e))?;
            }
        }

        Ok(())
    }

    /// 关闭会话
    pub fn close(&mut self) {
        self.stream = None;
        self.state = TelnetState::Closed;
    }
}

impl Drop for TelnetSession {
    fn drop(&mut self) {
        self.close();
    }
}
