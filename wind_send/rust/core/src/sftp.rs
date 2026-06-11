use serde::{Deserialize, Serialize};
use ssh2::Sftp;
use std::path::Path;
use std::sync::Arc;

/// SFTP 文件类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SftpFileType {
    File,
    Directory,
    Symlink,
    Other,
}

/// SFTP 文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SftpFileInfo {
    pub name: String,
    pub path: String,
    pub file_type: SftpFileType,
    pub size: u64,
    pub permissions: i32,
    pub modified: Option<i64>,
    pub accessed: Option<i64>,
    pub is_dir: bool,
    pub is_file: bool,
    pub is_symlink: bool,
}

/// SFTP 传输任务状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SftpTransferState {
    Queued,
    Running,
    Completed,
    Failed(String),
    Canceled,
}

/// SFTP 传输任务
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SftpTransferTask {
    pub id: u64,
    pub local_path: String,
    pub remote_path: String,
    pub is_upload: bool,
    pub state: SftpTransferState,
    pub total_bytes: u64,
    pub transferred_bytes: u64,
    pub speed: f64, // bytes per second
}

/// SFTP 会话
#[derive(Clone)]
pub struct SftpSession {
    sftp: Arc<Sftp>,
}

impl SftpSession {
    /// 创建新的 SFTP 会话
    pub fn new(session: &ssh2::Session) -> Result<Self, String> {
        let sftp = session
            .sftp()
            .map_err(|e| format!("创建 SFTP 会话失败: {}", e))?;
        Ok(Self {
            sftp: Arc::new(sftp),
        })
    }

    /// 列出目录内容
    pub fn list_dir(&self, path: &str) -> Result<Vec<SftpFileInfo>, String> {
        let dir_path = Path::new(path);
        let entries = self
            .sftp
            .readdir(dir_path)
            .map_err(|e| format!("读取目录失败: {}", e))?;

        let mut files = Vec::new();
        for (path, stat) in entries {
            let name = path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();

            // 跳过 . 和 ..
            if name == "." || name == ".." {
                continue;
            }

            let file_type = if stat.is_dir() {
                SftpFileType::Directory
            } else if stat.is_file() {
                SftpFileType::File
            } else {
                SftpFileType::Other
            };

            let perm = stat.perm.unwrap_or(0) as i32;
            let is_symlink = (perm & 0o120000) == 0o120000;

            files.push(SftpFileInfo {
                name,
                path: path.to_string_lossy().to_string(),
                file_type: if is_symlink {
                    SftpFileType::Symlink
                } else {
                    file_type
                },
                size: stat.size.unwrap_or(0),
                permissions: perm,
                modified: stat.mtime.map(|t| t as i64),
                accessed: stat.atime.map(|t| t as i64),
                is_dir: stat.is_dir(),
                is_file: stat.is_file(),
                is_symlink,
            });
        }

        // 排序：目录在前，文件在后
        files.sort_by(|a, b| {
            if a.is_dir && !b.is_dir {
                std::cmp::Ordering::Less
            } else if !a.is_dir && b.is_dir {
                std::cmp::Ordering::Greater
            } else {
                a.name.cmp(&b.name)
            }
        });

        Ok(files)
    }

    /// 获取文件/目录信息
    pub fn stat(&self, path: &str) -> Result<SftpFileInfo, String> {
        let file_path = Path::new(path);
        let stat = self
            .sftp
            .stat(file_path)
            .map_err(|e| format!("获取文件信息失败: {}", e))?;

        let name = file_path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();

        let file_type = if stat.is_dir() {
            SftpFileType::Directory
        } else if stat.is_file() {
            SftpFileType::File
        } else {
            SftpFileType::Other
        };

        let perm = stat.perm.unwrap_or(0) as i32;
        let is_symlink = (perm & 0o120000) == 0o120000;

        Ok(SftpFileInfo {
            name,
            path: path.to_string(),
            file_type: if is_symlink {
                SftpFileType::Symlink
            } else {
                file_type
            },
            size: stat.size.unwrap_or(0),
            permissions: perm,
            modified: stat.mtime.map(|t| t as i64),
            accessed: stat.atime.map(|t| t as i64),
            is_dir: stat.is_dir(),
            is_file: stat.is_file(),
            is_symlink,
        })
    }

    /// 创建目录
    pub fn mkdir(&self, path: &str, mode: i32) -> Result<(), String> {
        let dir_path = Path::new(path);
        self.sftp
            .mkdir(dir_path, mode)
            .map_err(|e| format!("创建目录失败: {}", e))?;
        Ok(())
    }

    /// 删除文件
    pub fn unlink(&self, path: &str) -> Result<(), String> {
        let file_path = Path::new(path);
        self.sftp
            .unlink(file_path)
            .map_err(|e| format!("删除文件失败: {}", e))?;
        Ok(())
    }

    /// 删除目录
    pub fn rmdir(&self, path: &str) -> Result<(), String> {
        let dir_path = Path::new(path);
        self.sftp
            .rmdir(dir_path)
            .map_err(|e| format!("删除目录失败: {}", e))?;
        Ok(())
    }

    /// 重命名/移动文件
    pub fn rename(&self, src: &str, dst: &str, _flags: u32) -> Result<(), String> {
        let src_path = Path::new(src);
        let dst_path = Path::new(dst);
        self.sftp
            .rename(src_path, dst_path, None)
            .map_err(|e| format!("重命名失败: {}", e))?;
        Ok(())
    }

    /// 修改权限
    pub fn chmod(&self, path: &str, mode: i32) -> Result<(), String> {
        let file_path = Path::new(path);
        let mut stat = self
            .sftp
            .stat(file_path)
            .map_err(|e| format!("获取文件信息失败: {}", e))?;
        stat.perm = Some(mode as u32);
        self.sftp
            .setstat(file_path, stat)
            .map_err(|e| format!("修改权限失败: {}", e))?;
        Ok(())
    }

    /// 上传文件
    pub fn upload_file(&self, local_path: &str, remote_path: &str) -> Result<(), String> {
        use std::fs::File;

        let mut local_file =
            File::open(local_path).map_err(|e| format!("打开本地文件失败: {}", e))?;
        let remote = Path::new(remote_path);
        let mut remote_file = self
            .sftp
            .create(remote)
            .map_err(|e| format!("创建远程文件失败: {}", e))?;
        copy_stream(&mut local_file, &mut remote_file)?;
        Ok(())
    }

    /// 下载文件
    pub fn download_file(&self, remote_path: &str, local_path: &str) -> Result<(), String> {
        use std::fs::File;

        let remote = Path::new(remote_path);
        let mut remote_file = self
            .sftp
            .open(remote)
            .map_err(|e| format!("打开远程文件失败: {}", e))?;
        let mut local_file =
            File::create(local_path).map_err(|e| format!("创建本地文件失败: {}", e))?;
        copy_stream(&mut remote_file, &mut local_file)?;
        Ok(())
    }

    pub fn upload_file_with_progress<F>(
        &self,
        local_path: &str,
        remote_path: &str,
        progress: F,
    ) -> Result<u64, String>
    where
        F: FnMut(u64) -> Result<(), String>,
    {
        let mut local_file =
            std::fs::File::open(local_path).map_err(|e| format!("打开本地文件失败: {e}"))?;
        let mut remote_file = self
            .sftp
            .create(Path::new(remote_path))
            .map_err(|e| format!("创建远程文件失败: {e}"))?;
        copy_stream_with_progress(&mut local_file, &mut remote_file, progress)
    }

    pub fn download_file_with_progress<F>(
        &self,
        remote_path: &str,
        local_path: &str,
        progress: F,
    ) -> Result<u64, String>
    where
        F: FnMut(u64) -> Result<(), String>,
    {
        let mut remote_file = self
            .sftp
            .open(Path::new(remote_path))
            .map_err(|e| format!("打开远程文件失败: {e}"))?;
        let mut local_file =
            std::fs::File::create(local_path).map_err(|e| format!("创建本地文件失败: {e}"))?;
        copy_stream_with_progress(&mut remote_file, &mut local_file, progress)
    }
}

fn copy_stream<R: std::io::Read, W: std::io::Write>(
    reader: &mut R,
    writer: &mut W,
) -> Result<u64, String> {
    copy_stream_with_progress(reader, writer, |_| Ok(()))
}

fn copy_stream_with_progress<R, W, F>(
    reader: &mut R,
    writer: &mut W,
    mut progress: F,
) -> Result<u64, String>
where
    R: std::io::Read,
    W: std::io::Write,
    F: FnMut(u64) -> Result<(), String>,
{
    let mut total = 0u64;
    let mut buffer = vec![0u8; 256 * 1024];
    loop {
        let read = reader
            .read(&mut buffer)
            .map_err(|e| format!("读取传输数据失败: {e}"))?;
        if read == 0 {
            break;
        }
        writer
            .write_all(&buffer[..read])
            .map_err(|e| format!("写入传输数据失败: {e}"))?;
        total += read as u64;
        progress(total)?;
    }
    writer
        .flush()
        .map_err(|e| format!("刷新传输数据失败: {e}"))?;
    Ok(total)
}

#[cfg(test)]
mod tests {
    use super::copy_stream;

    #[test]
    fn streams_without_loading_entire_input() {
        let input = vec![7u8; 1024 * 1024 + 37];
        let mut reader = std::io::Cursor::new(input.clone());
        let mut output = Vec::new();
        let copied = copy_stream(&mut reader, &mut output).unwrap();
        assert_eq!(copied, input.len() as u64);
        assert_eq!(output, input);
    }
}
