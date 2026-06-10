use vte::{Parser, Perform};
use serde::{Deserialize, Serialize};

/// 终端颜色
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Color {
    Default,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    BrightBlack,
    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    BrightWhite,
    Rgb(u8, u8, u8),
    Indexed(u8),
}

/// 终端单元格属性
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CellAttr {
    pub fg: Color,
    pub bg: Color,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub inverse: bool,
}

impl Default for CellAttr {
    fn default() -> Self {
        Self {
            fg: Color::Default,
            bg: Color::Default,
            bold: false,
            italic: false,
            underline: false,
            inverse: false,
        }
    }
}

/// 终端单元格
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cell {
    pub ch: char,
    pub attr: CellAttr,
}

impl Default for Cell {
    fn default() -> Self {
        Self {
            ch: ' ',
            attr: CellAttr::default(),
        }
    }
}

/// 终端行
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalLine {
    pub cells: Vec<Cell>,
}

impl TerminalLine {
    pub fn new(width: usize) -> Self {
        Self {
            cells: vec![Cell::default(); width],
        }
    }
}

/// 终端快照（传给 Flutter）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalSnapshot {
    pub cols: usize,
    pub rows: usize,
    pub cursor_row: usize,
    pub cursor_col: usize,
    pub cursor_visible: bool,
    pub lines: Vec<TerminalLine>,
}

/// 辅助函数：从 Params 中提取第一个参数
fn first_param(params: &vte::Params, default: u16) -> u16 {
    params.iter().next().and_then(|p| p.first().copied()).unwrap_or(default)
}

/// 辅助函数：从 Params 中提取第二个参数
fn second_param(params: &vte::Params, default: u16) -> u16 {
    params.iter().nth(1).and_then(|p| p.first().copied()).unwrap_or(default)
}

/// 终端解析器
pub struct Terminal {
    cols: usize,
    rows: usize,
    cursor_row: usize,
    cursor_col: usize,
    cursor_visible: bool,
    lines: Vec<TerminalLine>,
    current_attr: CellAttr,
    parser: Parser,
}

impl Terminal {
    pub fn new(cols: usize, rows: usize) -> Self {
        let lines = vec![TerminalLine::new(cols); rows];
        Self {
            cols,
            rows,
            cursor_row: 0,
            cursor_col: 0,
            cursor_visible: true,
            lines,
            current_attr: CellAttr::default(),
            parser: Parser::new(),
        }
    }

    /// 处理输入数据
    pub fn process(&mut self, data: &[u8]) {
        // 使用临时缓冲区避免借用问题
        let mut parser = std::mem::take(&mut self.parser);
        for &byte in data {
            let mut performer = TerminalPerformer {
                terminal: self,
            };
            parser.advance(&mut performer, byte);
        }
        self.parser = parser;
    }

    /// 获取当前快照
    pub fn snapshot(&self) -> TerminalSnapshot {
        TerminalSnapshot {
            cols: self.cols,
            rows: self.rows,
            cursor_row: self.cursor_row,
            cursor_col: self.cursor_col,
            cursor_visible: self.cursor_visible,
            lines: self.lines.clone(),
        }
    }

    /// 调整大小
    pub fn resize(&mut self, cols: usize, rows: usize) {
        self.cols = cols;
        self.rows = rows;

        // 调整行数
        while self.lines.len() < rows {
            self.lines.push(TerminalLine::new(cols));
        }
        self.lines.truncate(rows);

        // 调整每行宽度
        for line in &mut self.lines {
            while line.cells.len() < cols {
                line.cells.push(Cell::default());
            }
            line.cells.truncate(cols);
        }

        // 确保光标在范围内
        self.cursor_row = self.cursor_row.min(rows.saturating_sub(1));
        self.cursor_col = self.cursor_col.min(cols.saturating_sub(1));
    }

    /// 换行
    fn newline(&mut self) {
        self.cursor_col = 0;
        if self.cursor_row < self.rows - 1 {
            self.cursor_row += 1;
        } else {
            // 滚动
            self.lines.remove(0);
            self.lines.push(TerminalLine::new(self.cols));
        }
    }

    /// 回车
    fn carriage_return(&mut self) {
        self.cursor_col = 0;
    }

    /// 退格
    fn backspace(&mut self) {
        if self.cursor_col > 0 {
            self.cursor_col -= 1;
        }
    }

    /// 水平制表符
    fn tab(&mut self) {
        let next_tab = (self.cursor_col / 8 + 1) * 8;
        self.cursor_col = next_tab.min(self.cols.saturating_sub(1));
    }

    /// 清除屏幕
    fn clear_screen(&mut self) {
        for line in &mut self.lines {
            for cell in &mut line.cells {
                *cell = Cell::default();
            }
        }
        self.cursor_row = 0;
        self.cursor_col = 0;
    }

    /// 清除行
    fn clear_line(&mut self) {
        if let Some(line) = self.lines.get_mut(self.cursor_row) {
            for cell in &mut line.cells {
                *cell = Cell::default();
            }
        }
    }

    /// 设置 SGR 属性
    fn set_sgr(&mut self, params: &vte::Params) {
        for param_group in params.iter() {
            for &param in param_group {
                match param {
                    0 => self.current_attr = CellAttr::default(),
                    1 => self.current_attr.bold = true,
                    3 => self.current_attr.italic = true,
                    4 => self.current_attr.underline = true,
                    7 => self.current_attr.inverse = true,
                    22 => self.current_attr.bold = false,
                    23 => self.current_attr.italic = false,
                    24 => self.current_attr.underline = false,
                    27 => self.current_attr.inverse = false,
                    30..=37 => {
                        self.current_attr.fg = match param - 30 {
                            0 => Color::Black,
                            1 => Color::Red,
                            2 => Color::Green,
                            3 => Color::Yellow,
                            4 => Color::Blue,
                            5 => Color::Magenta,
                            6 => Color::Cyan,
                            7 => Color::White,
                            _ => Color::Default,
                        };
                    }
                    40..=47 => {
                        self.current_attr.bg = match param - 40 {
                            0 => Color::Black,
                            1 => Color::Red,
                            2 => Color::Green,
                            3 => Color::Yellow,
                            4 => Color::Blue,
                            5 => Color::Magenta,
                            6 => Color::Cyan,
                            7 => Color::White,
                            _ => Color::Default,
                        };
                    }
                    90..=97 => {
                        self.current_attr.fg = match param - 90 {
                            0 => Color::BrightBlack,
                            1 => Color::BrightRed,
                            2 => Color::BrightGreen,
                            3 => Color::BrightYellow,
                            4 => Color::BrightBlue,
                            5 => Color::BrightMagenta,
                            6 => Color::BrightCyan,
                            7 => Color::BrightWhite,
                            _ => Color::Default,
                        };
                    }
                    100..=107 => {
                        self.current_attr.bg = match param - 100 {
                            0 => Color::BrightBlack,
                            1 => Color::BrightRed,
                            2 => Color::BrightGreen,
                            3 => Color::BrightYellow,
                            4 => Color::BrightBlue,
                            5 => Color::BrightMagenta,
                            6 => Color::BrightCyan,
                            7 => Color::BrightWhite,
                            _ => Color::Default,
                        };
                    }
                    _ => {}
                }
            }
        }
    }
}

/// VTE Perform trait 实现
struct TerminalPerformer<'a> {
    terminal: &'a mut Terminal,
}

impl<'a> Perform for TerminalPerformer<'a> {
    fn print(&mut self, c: char) {
        if self.terminal.cursor_col < self.terminal.cols {
            if let Some(line) = self.terminal.lines.get_mut(self.terminal.cursor_row) {
                if let Some(cell) = line.cells.get_mut(self.terminal.cursor_col) {
                    cell.ch = c;
                    cell.attr = self.terminal.current_attr.clone();
                }
            }
            self.terminal.cursor_col += 1;
        }
    }

    fn execute(&mut self, byte: u8) {
        match byte {
            b'\n' | b'\x0b' | b'\x0c' => self.terminal.newline(),
            b'\r' => self.terminal.carriage_return(),
            b'\x08' => self.terminal.backspace(),
            b'\t' => self.terminal.tab(),
            b'\x07' => {} // BEL - 忽略
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &vte::Params, _intermediates: &[u8], ignore: bool, c: char) {
        if ignore {
            return;
        }

        match c {
            'm' => self.terminal.set_sgr(params),
            'H' | 'f' => {
                // 光标位置
                let row = first_param(params, 1).saturating_sub(1) as usize;
                let col = second_param(params, 1).saturating_sub(1) as usize;
                self.terminal.cursor_row = row.min(self.terminal.rows.saturating_sub(1));
                self.terminal.cursor_col = col.min(self.terminal.cols.saturating_sub(1));
            }
            'A' => {
                // 光标上移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_row = self.terminal.cursor_row.saturating_sub(n);
            }
            'B' => {
                // 光标下移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_row = (self.terminal.cursor_row + n).min(self.terminal.rows.saturating_sub(1));
            }
            'C' => {
                // 光标右移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_col = (self.terminal.cursor_col + n).min(self.terminal.cols.saturating_sub(1));
            }
            'D' => {
                // 光标左移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_col = self.terminal.cursor_col.saturating_sub(n);
            }
            'J' => {
                // 擦除显示
                let mode = first_param(params, 0);
                match mode {
                    0 => {
                        // 从光标到屏幕末尾
                        for col in self.terminal.cursor_col..self.terminal.cols {
                            if let Some(line) = self.terminal.lines.get_mut(self.terminal.cursor_row) {
                                line.cells[col] = Cell::default();
                            }
                        }
                        for row in (self.terminal.cursor_row + 1)..self.terminal.rows {
                            for col in 0..self.terminal.cols {
                                self.terminal.lines[row].cells[col] = Cell::default();
                            }
                        }
                    }
                    1 => {
                        // 从屏幕开头到光标
                        for row in 0..self.terminal.cursor_row {
                            for col in 0..self.terminal.cols {
                                self.terminal.lines[row].cells[col] = Cell::default();
                            }
                        }
                        for col in 0..=self.terminal.cursor_col {
                            if let Some(line) = self.terminal.lines.get_mut(self.terminal.cursor_row) {
                                line.cells[col] = Cell::default();
                            }
                        }
                    }
                    2 => self.terminal.clear_screen(),
                    _ => {}
                }
            }
            'K' => {
                // 擦除行
                let mode = first_param(params, 0);
                match mode {
                    0 => {
                        // 从光标到行尾
                        for col in self.terminal.cursor_col..self.terminal.cols {
                            if let Some(line) = self.terminal.lines.get_mut(self.terminal.cursor_row) {
                                line.cells[col] = Cell::default();
                            }
                        }
                    }
                    1 => {
                        // 从行开头到光标
                        for col in 0..=self.terminal.cursor_col {
                            if let Some(line) = self.terminal.lines.get_mut(self.terminal.cursor_row) {
                                line.cells[col] = Cell::default();
                            }
                        }
                    }
                    2 => self.terminal.clear_line(),
                    _ => {}
                }
            }
            'h' => {
                // 设置模式
                for param_group in params.iter() {
                    for &param in param_group {
                        if param == 25 {
                            self.terminal.cursor_visible = true;
                        }
                    }
                }
            }
            'l' => {
                // 重置模式
                for param_group in params.iter() {
                    for &param in param_group {
                        if param == 25 {
                            self.terminal.cursor_visible = false;
                        }
                    }
                }
            }
            _ => {}
        }
    }

    fn esc_dispatch(&mut self, _intermediates: &[u8], _ignore: bool, byte: u8) {
        match byte {
            b'7' => {} // 保存光标位置 - TODO
            b'8' => {} // 恢复光标位置 - TODO
            b'c' => self.terminal.clear_screen(), // RIS - 重置
            _ => {}
        }
    }
}
