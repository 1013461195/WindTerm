use serde::{Deserialize, Serialize};

/// 协议类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProtocolType {
    Ssh,
    Telnet,
    Serial,
    RawTcp,
    LocalShell,
}

/// Telnet 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TelnetConfig {
    pub host: String,
    pub port: u16,
    pub naws: bool,
    pub ttype: bool,
    pub echo: bool,
    pub sga: bool,
    pub binary: bool,
    pub encoding: String,
}

impl Default for TelnetConfig {
    fn default() -> Self {
        Self {
            host: String::new(),
            port: 23,
            naws: true,
            ttype: true,
            echo: false,
            sga: true,
            binary: false,
            encoding: "utf-8".to_string(),
        }
    }
}

/// 串口数据位
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SerialDataBits {
    Five,
    Six,
    Seven,
    Eight,
}

/// 串口校验位
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SerialParity {
    None,
    Odd,
    Even,
    Mark,
    Space,
}

/// 串口停止位
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SerialStopBits {
    One,
    OnePointFive,
    Two,
}

/// 串口流控
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SerialFlowControl {
    None,
    Hardware,
    Software,
}

/// Serial 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialConfig {
    pub port: String,
    pub baud_rate: u32,
    pub data_bits: SerialDataBits,
    pub parity: SerialParity,
    pub stop_bits: SerialStopBits,
    pub flow_control: SerialFlowControl,
    pub dtr: bool,
    pub rts: bool,
}

impl Default for SerialConfig {
    fn default() -> Self {
        Self {
            port: String::new(),
            baud_rate: 9600,
            data_bits: SerialDataBits::Eight,
            parity: SerialParity::None,
            stop_bits: SerialStopBits::One,
            flow_control: SerialFlowControl::None,
            dtr: true,
            rts: true,
        }
    }
}

/// Raw TCP 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawTcpConfig {
    pub host: String,
    pub port: u16,
    pub encoding: String,
    pub newline: String,
}

impl Default for RawTcpConfig {
    fn default() -> Self {
        Self {
            host: String::new(),
            port: 0,
            encoding: "utf-8".to_string(),
            newline: "CRLF".to_string(),
        }
    }
}
