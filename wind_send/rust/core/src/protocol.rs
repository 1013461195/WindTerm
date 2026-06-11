#![allow(dead_code)]

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
    #[serde(default = "default_newline")]
    pub newline: String,
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
            newline: default_newline(),
        }
    }
}

/// 串口数据位
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SerialDataBits {
    Five,
    Six,
    Seven,
    Eight,
}

/// 串口校验位
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SerialParity {
    None,
    Odd,
    Even,
    Mark,
    Space,
}

/// 串口停止位
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SerialStopBits {
    One,
    OnePointFive,
    Two,
}

/// 串口流控
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
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
    #[serde(default = "default_encoding")]
    pub encoding: String,
    #[serde(default = "default_newline")]
    pub newline: String,
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
            encoding: default_encoding(),
            newline: default_newline(),
        }
    }
}

pub fn decode_to_utf8(data: &[u8], label: &str) -> Vec<u8> {
    let Some(encoding) = encoding_rs::Encoding::for_label(label.as_bytes()) else {
        return data.to_vec();
    };
    let (decoded, _, _) = encoding.decode(data);
    decoded.into_owned().into_bytes()
}

pub fn encode_from_utf8(data: &[u8], label: &str) -> Vec<u8> {
    if label.eq_ignore_ascii_case("utf-8") || label.eq_ignore_ascii_case("utf8") {
        return data.to_vec();
    }
    let Some(encoding) = encoding_rs::Encoding::for_label(label.as_bytes()) else {
        return data.to_vec();
    };
    let text = String::from_utf8_lossy(data);
    let (encoded, _, _) = encoding.encode(&text);
    encoded.into_owned()
}

pub fn apply_newline(data: &[u8], newline: &str) -> Vec<u8> {
    if !data.contains(&b'\n') {
        return data.to_vec();
    }
    let replacement: &[u8] = match newline.to_ascii_uppercase().as_str() {
        "CR" => b"\r",
        "LF" => b"\n",
        _ => b"\r\n",
    };
    let mut output = Vec::with_capacity(data.len() + 8);
    for &byte in data {
        if byte == b'\n' {
            if output.last() == Some(&b'\r') {
                output.pop();
            }
            output.extend_from_slice(replacement);
        } else {
            output.push(byte);
        }
    }
    output
}

fn default_encoding() -> String {
    "utf-8".to_string()
}

fn default_newline() -> String {
    "CRLF".to_string()
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
