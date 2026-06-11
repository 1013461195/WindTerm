use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use std::io::Write;
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Instant;

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
                std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".to_string())
            },
            working_dir: None,
            env_vars: Vec::new(),
            cols: 80,
            rows: 24,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum LocalShellState {
    Created,
    Running,
    Exited,
    Error(String),
}

pub struct LocalShellSession {
    config: LocalShellConfig,
    state: LocalShellState,
    child: Option<Box<dyn Child + Send + Sync>>,
    master: Option<Box<dyn MasterPty + Send>>,
    writer: Option<Box<dyn Write + Send>>,
    output: Arc<Mutex<Vec<u8>>>,
    reader_thread: Option<JoinHandle<()>>,
    last_activity: Instant,
}

impl LocalShellSession {
    pub fn new(_id: u64, config: LocalShellConfig) -> Self {
        Self {
            config,
            state: LocalShellState::Created,
            child: None,
            master: None,
            writer: None,
            output: Arc::new(Mutex::new(Vec::new())),
            reader_thread: None,
            last_activity: Instant::now(),
        }
    }

    pub fn state(&self) -> &LocalShellState {
        &self.state
    }

    pub fn start(&mut self) -> Result<(), String> {
        let pair = native_pty_system()
            .openpty(PtySize {
                rows: self.config.rows,
                cols: self.config.cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| format!("创建 PTY 失败: {e}"))?;

        let mut command = CommandBuilder::new(&self.config.shell);
        if let Some(directory) = &self.config.working_dir {
            command.cwd(directory);
        }
        for (key, value) in &self.config.env_vars {
            command.env(key, value);
        }
        command.env("TERM", "xterm-256color");

        let child = pair
            .slave
            .spawn_command(command)
            .map_err(|e| format!("启动 Shell 失败: {e}"))?;
        drop(pair.slave);

        let mut reader = pair
            .master
            .try_clone_reader()
            .map_err(|e| format!("克隆 PTY reader 失败: {e}"))?;
        let writer = pair
            .master
            .take_writer()
            .map_err(|e| format!("获取 PTY writer 失败: {e}"))?;
        let output = Arc::clone(&self.output);
        let reader_thread = std::thread::spawn(move || {
            let mut buffer = [0u8; 16 * 1024];
            loop {
                match std::io::Read::read(&mut reader, &mut buffer) {
                    Ok(0) => break,
                    Ok(read) => output
                        .lock()
                        .expect("local shell output mutex poisoned")
                        .extend_from_slice(&buffer[..read]),
                    Err(_) => break,
                }
            }
        });

        self.child = Some(child);
        self.master = Some(pair.master);
        self.writer = Some(writer);
        self.reader_thread = Some(reader_thread);
        self.state = LocalShellState::Running;
        self.last_activity = Instant::now();
        Ok(())
    }

    pub fn read_output(&mut self) -> Vec<u8> {
        let output = {
            let mut buffer = self
                .output
                .lock()
                .expect("local shell output mutex poisoned");
            std::mem::take(&mut *buffer)
        };
        if !output.is_empty() {
            self.last_activity = Instant::now();
        }
        if let Some(child) = &mut self.child {
            if matches!(child.try_wait(), Ok(Some(_))) {
                self.state = LocalShellState::Exited;
            }
        }
        output
    }

    pub fn write_input(&mut self, data: &[u8]) -> Result<(), String> {
        let writer = self.writer.as_mut().ok_or("PTY writer 未打开")?;
        writer
            .write_all(data)
            .and_then(|_| writer.flush())
            .map_err(|e| format!("写入 PTY 失败: {e}"))?;
        self.last_activity = Instant::now();
        Ok(())
    }

    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<(), String> {
        self.config.cols = cols;
        self.config.rows = rows;
        self.master
            .as_ref()
            .ok_or("PTY 未打开")?
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| format!("调整 PTY 大小失败: {e}"))
    }

    pub fn close(&mut self) {
        self.writer.take();
        self.master.take();
        if let Some(child) = &mut self.child {
            let _ = child.kill();
            let _ = child.wait();
        }
        self.child.take();
        if let Some(thread) = self.reader_thread.take() {
            let _ = thread.join();
        }
        self.state = LocalShellState::Exited;
    }
}

impl Drop for LocalShellSession {
    fn drop(&mut self) {
        self.close();
    }
}
