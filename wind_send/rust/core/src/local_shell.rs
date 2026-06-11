use std::io::{Read, Write};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// 本地 Shell 会话配置
#[derive(Debug, Clone)]
pub struct LocalShellConfig {
    pub shell: String,
    pub working_dir: Option<String>,
    pub env_vars: Vec<(String, String)>,
    pub cols: u16,
    pub rows: u16,
}

impl Default for LocalShellConfig {
    fn default() -> Self {
        Self {
            shell: if cfg!(target_os = "windows") {
                "cmd.exe".to_string()
            } else {
                "/bin/bash".to_string()
            },
            working_dir: None,
            env_vars: Vec::new(),
            cols: 80,
            rows: 24,
        }
    }
}

/// 本地 Shell 会话状态
#[derive(Debug, Clone, PartialEq)]
pub enum LocalShellState {
    Created,
    Running,
    Exited,
    Error(String),
}

/// 本地 Shell 会话
pub struct LocalShellSession {
    id: u64,
    config: LocalShellConfig,
    state: LocalShellState,
    process: Option<Child>,
    stdin: Option<Arc<Mutex<Box<dyn Write + Send>>>>,
    stdout: Option<Arc<Mutex<Box<dyn Read + Send>>>>,
    last_activity: Instant,
}

impl LocalShellSession {
    pub fn new(id: u64, config: LocalShellConfig) -> Self {
        Self {
            id,
            config,
            state: LocalShellState::Created,
            process: None,
            stdin: None,
            stdout: None,
            last_activity: Instant::now(),
        }
    }

    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn state(&self) -> &LocalShellState {
        &self.state
    }

    pub fn cols(&self) -> u16 {
        self.config.cols
    }

    pub fn rows(&self) -> u16 {
        self.config.rows
    }

    /// 启动本地 Shell
    pub fn start(&mut self) -> Result<(), String> {
        let mut cmd = Command::new(&self.config.shell);

        // 设置工作目录
        if let Some(ref dir) = self.config.working_dir {
            cmd.current_dir(dir);
        }

        // 设置环境变量
        for (key, value) in &self.config.env_vars {
            cmd.env(key, value);
        }

        // 设置标准输入/输出/错误
        cmd.stdin(Stdio::piped());
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        // 启动进程
        let mut process = cmd
            .spawn()
            .map_err(|e| format!("启动 Shell 失败: {}", e))?;

        // 获取 stdin 和 stdout
        let stdin = process.stdin.take()
            .ok_or_else(|| "无法获取 stdin".to_string())?;
        let stdout = process.stdout.take()
            .ok_or_else(|| "无法获取 stdout".to_string())?;

        self.stdin = Some(Arc::new(Mutex::new(Box::new(stdin))));
        self.stdout = Some(Arc::new(Mutex::new(Box::new(stdout))));
        self.process = Some(process);
        self.state = LocalShellState::Running;
        self.last_activity = Instant::now();

        Ok(())
    }

    /// 读取输出
    pub fn read_output(&mut self) -> Vec<u8> {
        let mut output = Vec::new();

        if let Some(stdout) = &self.stdout {
            let mut stdout = stdout.lock().unwrap();
            let mut buf = [0u8; 4096];
            loop {
                match stdout.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        output.extend_from_slice(&buf[..n]);
                        self.last_activity = Instant::now();
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(_) => break,
                }
            }
        }

        // 检查进程是否退出
        if let Some(process) = &mut self.process {
            match process.try_wait() {
                Ok(Some(status)) => {
                    self.state = LocalShellState::Exited;
                    // 读取剩余输出
                    if let Some(stdout) = &self.stdout {
                        let mut stdout = stdout.lock().unwrap();
                        let mut buf = [0u8; 4096];
                        loop {
                            match stdout.read(&mut buf) {
                                Ok(0) => break,
                                Ok(n) => output.extend_from_slice(&buf[..n]),
                                Err(_) => break,
                            }
                        }
                    }
                }
                Ok(None) => {}
                Err(e) => {
                    self.state = LocalShellState::Error(format!("检查进程状态失败: {}", e));
                }
            }
        }

        output
    }

    /// 发送输入
    pub fn write_input(&mut self, data: &[u8]) -> Result<(), String> {
        if let Some(stdin) = &self.stdin {
            let mut stdin = stdin.lock().unwrap();
            stdin
                .write_all(data)
                .map_err(|e| format!("写入失败: {}", e))?;
            stdin
                .flush()
                .map_err(|e| format!("刷新失败: {}", e))?;
            self.last_activity = Instant::now();
            Ok(())
        } else {
            Err("stdin 未打开".to_string())
        }
    }

    /// 调整终端大小
    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<(), String> {
        self.config.cols = cols;
        self.config.rows = rows;

        // 在 Unix 系统上，可以通过 ioctl 调整 PTY 大小
        // 这里暂时只更新配置，实际调整需要 PTY 支持
        Ok(())
    }

    /// 关闭会话
    pub fn close(&mut self) {
        if let Some(mut process) = self.process.take() {
            let _ = process.kill();
            let _ = process.wait();
        }
        self.stdin = None;
        self.stdout = None;
        self.state = LocalShellState::Exited;
    }
}

impl Drop for LocalShellSession {
    fn drop(&mut self) {
        self.close();
    }
}
