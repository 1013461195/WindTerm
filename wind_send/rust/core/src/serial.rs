use crate::protocol::{
    apply_newline, decode_to_utf8, encode_from_utf8, SerialConfig, SerialDataBits,
    SerialFlowControl, SerialParity, SerialStopBits,
};
use serialport::{DataBits, FlowControl, Parity, SerialPort, StopBits};
use std::io::{Read, Write};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq)]
pub enum SerialState {
    Created,
    Connected,
    Closed,
    Error(String),
}

pub struct SerialSession {
    config: SerialConfig,
    state: SerialState,
    port: Option<Box<dyn SerialPort>>,
    cols: u16,
    rows: u16,
}

impl SerialSession {
    pub fn new(config: SerialConfig) -> Self {
        Self {
            config,
            state: SerialState::Created,
            port: None,
            cols: 80,
            rows: 24,
        }
    }

    pub fn connect(&mut self) -> Result<(), String> {
        let mut port = serialport::new(&self.config.port, self.config.baud_rate)
            .data_bits(map_data_bits(&self.config.data_bits))
            .parity(map_parity(&self.config.parity)?)
            .stop_bits(map_stop_bits(&self.config.stop_bits)?)
            .flow_control(map_flow_control(&self.config.flow_control))
            .timeout(Duration::from_millis(5))
            .open()
            .map_err(|e| format!("打开串口 {} 失败: {e}", self.config.port))?;
        port.write_data_terminal_ready(self.config.dtr)
            .map_err(|e| format!("设置串口 DTR 失败: {e}"))?;
        port.write_request_to_send(self.config.rts)
            .map_err(|e| format!("设置串口 RTS 失败: {e}"))?;
        self.port = Some(port);
        self.state = SerialState::Connected;
        Ok(())
    }

    pub fn read_output(&mut self) -> Vec<u8> {
        let mut output = Vec::new();
        let Some(port) = &mut self.port else {
            return output;
        };
        let mut buffer = [0u8; 4096];
        loop {
            match port.read(&mut buffer) {
                Ok(0) => break,
                Ok(read) => output
                    .extend_from_slice(&decode_to_utf8(&buffer[..read], &self.config.encoding)),
                Err(error)
                    if error.kind() == std::io::ErrorKind::TimedOut
                        || error.kind() == std::io::ErrorKind::WouldBlock =>
                {
                    break;
                }
                Err(error) => {
                    self.state = SerialState::Error(error.to_string());
                    break;
                }
            }
        }
        output
    }

    pub fn write_input(&mut self, data: &[u8]) -> Result<(), String> {
        let port = self.port.as_mut().ok_or("串口未打开")?;
        let encoded = encode_from_utf8(
            &apply_newline(data, &self.config.newline),
            &self.config.encoding,
        );
        port.write_all(&encoded)
            .and_then(|_| port.flush())
            .map_err(|e| format!("串口写入失败: {e}"))
    }

    pub fn resize(&mut self, cols: u16, rows: u16) {
        self.cols = cols;
        self.rows = rows;
    }

    pub fn state_name(&self) -> &'static str {
        match self.state {
            SerialState::Created => "created",
            SerialState::Connected => "connected",
            SerialState::Closed => "closed",
            SerialState::Error(_) => "error",
        }
    }

    pub fn close(&mut self) {
        self.port.take();
        self.state = SerialState::Closed;
    }
}

impl Drop for SerialSession {
    fn drop(&mut self) {
        self.close();
    }
}

pub fn available_ports_json() -> Result<String, String> {
    let ports = serialport::available_ports().map_err(|e| format!("枚举串口失败: {e}"))?;
    let names: Vec<String> = ports.into_iter().map(|port| port.port_name).collect();
    serde_json::to_string(&names).map_err(|e| e.to_string())
}

fn map_data_bits(value: &SerialDataBits) -> DataBits {
    match value {
        SerialDataBits::Five => DataBits::Five,
        SerialDataBits::Six => DataBits::Six,
        SerialDataBits::Seven => DataBits::Seven,
        SerialDataBits::Eight => DataBits::Eight,
    }
}

fn map_parity(value: &SerialParity) -> Result<Parity, String> {
    match value {
        SerialParity::None => Ok(Parity::None),
        SerialParity::Odd => Ok(Parity::Odd),
        SerialParity::Even => Ok(Parity::Even),
        SerialParity::Mark | SerialParity::Space => {
            Err("当前串口后端不支持 Mark/Space 校验".to_string())
        }
    }
}

fn map_stop_bits(value: &SerialStopBits) -> Result<StopBits, String> {
    match value {
        SerialStopBits::One => Ok(StopBits::One),
        SerialStopBits::Two => Ok(StopBits::Two),
        SerialStopBits::OnePointFive => Err("当前串口后端不支持 1.5 停止位".to_string()),
    }
}

fn map_flow_control(value: &SerialFlowControl) -> FlowControl {
    match value {
        SerialFlowControl::None => FlowControl::None,
        SerialFlowControl::Hardware => FlowControl::Hardware,
        SerialFlowControl::Software => FlowControl::Software,
    }
}
