use vte::{Parser, Perform};
use serde::{Deserialize, Serialize};

/// 鼠标跟踪模式
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum MouseTrackingMode {
    /// 无跟踪
    None,
    /// 普通模式（X10）
    Normal,
    /// 按钮事件模式
    Button,
    /// 任意事件模式
    Any,
}

/// 鼠标事件编码格式
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum MouseEncoding {
    /// X10 编码（默认）
    X10,
    /// SGR 编码（扩展）
    SGR,
}

/// 鼠标事件类型
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum MouseEventType {
    Press,
    Release,
    Motion,
}

/// 鼠标按键
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum MouseButton {
    Left,
    Middle,
    Right,
    None,
}

/// 鼠标事件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MouseEvent {
    pub event_type: MouseEventType,
    pub button: MouseButton,
    pub col: usize,
    pub row: usize,
    pub shift: bool,
    pub meta: bool,
    pub ctrl: bool,
}

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
    /// 宽字符占位标记：0=正常，1=宽字符首字符，2=宽字符续字符（占位）
    pub wide: u8,
}

impl Default for Cell {
    fn default() -> Self {
        Self {
            ch: ' ',
            attr: CellAttr::default(),
            wide: 0,
        }
    }
}

/// 判断字符是否为宽字符（CJK 等全角字符）
fn is_wide_char(c: char) -> bool {
    matches!(c,
        '\u{1100}'..='\u{115f}' |
        '\u{2e80}'..='\u{303e}' |
        '\u{3040}'..='\u{33bf}' |
        '\u{3400}'..='\u{4dbf}' |
        '\u{4e00}'..='\u{9fff}' |
        '\u{a000}'..='\u{a4cf}' |
        '\u{ac00}'..='\u{d7a3}' |
        '\u{f900}'..='\u{faff}' |
        '\u{fe30}'..='\u{fe6f}' |
        '\u{ff01}'..='\u{ff60}' |
        '\u{ffe0}'..='\u{ffe6}' |
        '\u{20000}'..='\u{2fffd}' |
        '\u{30000}'..='\u{3fffd}'
    )
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
    pub scrollback: Vec<TerminalLine>,
    pub scroll_offset: usize,
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
    scrollback: Vec<TerminalLine>,
    scrollback_limit: usize,
    scroll_offset: usize,
    /// 保存的光标位置（ESC 7）
    saved_cursor_row: usize,
    saved_cursor_col: usize,
    saved_attr: CellAttr,
    /// 滚动区域 (top, bottom)，行号从 0 开始
    scroll_top: usize,
    scroll_bottom: usize,
    /// 插入模式
    insert_mode: bool,
    /// 鼠标跟踪模式
    mouse_tracking_mode: MouseTrackingMode,
    /// 鼠标按键跟踪模式（SGR 扩展）
    mouse_button_tracking: bool,
    /// 鼠标运动跟踪模式
    mouse_motion_tracking: bool,
    /// 鼠标所有事件跟踪模式
    mouse_any_event_tracking: bool,
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
            scrollback: Vec::new(),
            scrollback_limit: 10000,
            scroll_offset: 0,
            saved_cursor_row: 0,
            saved_cursor_col: 0,
            saved_attr: CellAttr::default(),
            scroll_top: 0,
            scroll_bottom: rows.saturating_sub(1),
            insert_mode: false,
            mouse_tracking_mode: MouseTrackingMode::None,
            mouse_button_tracking: false,
            mouse_motion_tracking: false,
            mouse_any_event_tracking: false,
        }
    }

    /// 处理输入数据
    pub fn process(&mut self, data: &[u8]) {
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
            scrollback: self.scrollback.clone(),
            scroll_offset: self.scroll_offset,
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

        // 重置滚动区域
        self.scroll_top = 0;
        self.scroll_bottom = rows.saturating_sub(1);

        // 确保光标在范围内
        self.cursor_row = self.cursor_row.min(rows.saturating_sub(1));
        self.cursor_col = self.cursor_col.min(cols.saturating_sub(1));
    }

    /// 在滚动区域范围内滚动（将行推入 scrollback 或删除）
    fn scroll_up(&mut self) {
        // 将顶部行推入 scrollback
        if self.scroll_top == 0 {
            let line = self.lines.remove(0);
            if self.scrollback.len() >= self.scrollback_limit {
                self.scrollback.remove(0);
            }
            self.scrollback.push(line);
        } else {
            self.lines.remove(self.scroll_top);
        }
        // 在滚动区域底部插入空行
        self.lines.insert(self.scroll_bottom, TerminalLine::new(self.cols));
    }

    /// 在滚动区域范围内向下滚动
    fn scroll_down(&mut self) {
        self.lines.remove(self.scroll_bottom);
        self.lines.insert(self.scroll_top, TerminalLine::new(self.cols));
    }

    /// 换行
    fn newline(&mut self) {
        self.cursor_col = 0;
        if self.cursor_row < self.scroll_bottom {
            self.cursor_row += 1;
        } else if self.cursor_row == self.scroll_bottom {
            self.scroll_up();
        } else {
            // 光标在滚动区域之外，直接下移
            if self.cursor_row < self.rows - 1 {
                self.cursor_row += 1;
            }
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

    /// 在当前位置写入一个字符（支持宽字符）
    fn put_char(&mut self, c: char) {
        let wide = is_wide_char(c);
        if wide && self.cursor_col + 1 >= self.cols {
            // 宽字符放不下，换到下一行开头
            self.newline();
        }
        if self.insert_mode {
            // 插入模式：先腾出空间
            if let Some(line) = self.lines.get_mut(self.cursor_row) {
                let width = if wide { 2 } else { 1 };
                for _ in 0..width {
                    if line.cells.len() < self.cols {
                        line.cells.push(Cell::default());
                    }
                }
                let _ = line.cells.drain(self.cols..);
            }
        }
        if self.cursor_col < self.cols {
            if let Some(line) = self.lines.get_mut(self.cursor_row) {
                if let Some(cell) = line.cells.get_mut(self.cursor_col) {
                    cell.ch = c;
                    cell.attr = self.current_attr.clone();
                    cell.wide = if wide { 1 } else { 0 };
                }
                // 宽字符占两个格子
                if wide && self.cursor_col + 1 < self.cols {
                    if let Some(next_cell) = line.cells.get_mut(self.cursor_col + 1) {
                        next_cell.ch = '\0'; // 占位符，渲染时跳过
                        next_cell.attr = self.current_attr.clone();
                        next_cell.wide = 2;
                    }
                }
            }
            self.cursor_col += if wide { 2 } else { 1 };
        }
    }

    /// 保存光标位置（ESC 7）
    fn save_cursor(&mut self) {
        self.saved_cursor_row = self.cursor_row;
        self.saved_cursor_col = self.cursor_col;
        self.saved_attr = self.current_attr.clone();
    }

    /// 恢复光标位置（ESC 8）
    fn restore_cursor(&mut self) {
        self.cursor_row = self.saved_cursor_row;
        self.cursor_col = self.saved_cursor_col;
        self.current_attr = self.saved_attr.clone();
    }

    /// 插入 N 行
    fn insert_lines(&mut self, n: usize) {
        if self.cursor_row >= self.scroll_top && self.cursor_row <= self.scroll_bottom {
            for _ in 0..n {
                if self.lines.len() > self.scroll_bottom {
                    self.lines.remove(self.scroll_bottom);
                }
                self.lines.insert(self.cursor_row, TerminalLine::new(self.cols));
            }
        }
    }

    /// 删除 N 行
    fn delete_lines(&mut self, n: usize) {
        if self.cursor_row >= self.scroll_top && self.cursor_row <= self.scroll_bottom {
            for _ in 0..n {
                self.lines.remove(self.cursor_row);
                self.lines.insert(self.scroll_bottom, TerminalLine::new(self.cols));
            }
        }
    }

    /// 插入 N 个字符
    fn insert_chars(&mut self, n: usize) {
        if let Some(line) = self.lines.get_mut(self.cursor_row) {
            for _ in 0..n {
                if line.cells.len() < self.cols {
                    line.cells.push(Cell::default());
                }
                let _ = line.cells.drain(self.cols..);
                line.cells.insert(self.cursor_col, Cell::default());
                if line.cells.len() > self.cols {
                    let _ = line.cells.drain(self.cols..);
                }
            }
        }
    }

    /// 删除 N 个字符
    fn delete_chars(&mut self, n: usize) {
        if let Some(line) = self.lines.get_mut(self.cursor_row) {
            let end = (self.cursor_col + n).min(self.cols);
            let _ = line.cells.drain(self.cursor_col..end);
            while line.cells.len() < self.cols {
                line.cells.push(Cell::default());
            }
        }
    }

    /// 向上滚动 N 行（CSI S）
    fn scroll_up_n(&mut self, n: usize) {
        for _ in 0..n {
            self.scroll_up();
        }
    }

    /// 向下滚动 N 行（CSI T）
    fn scroll_down_n(&mut self, n: usize) {
        for _ in 0..n {
            self.scroll_down();
        }
    }

    /// 编码鼠标事件为终端转义序列
    pub fn encode_mouse_event(&self, event: &MouseEvent) -> Vec<u8> {
        if self.mouse_tracking_mode == MouseTrackingMode::None {
            return Vec::new();
        }

        // 检查事件类型是否需要发送
        match event.event_type {
            MouseEventType::Press | MouseEventType::Release => {
                if self.mouse_tracking_mode == MouseTrackingMode::None {
                    return Vec::new();
                }
            }
            MouseEventType::Motion => {
                if !self.mouse_motion_tracking && !self.mouse_any_event_tracking {
                    return Vec::new();
                }
            }
        }

        // 使用 SGR 编码（支持扩展）
        let button = match event.button {
            MouseButton::Left => 0,
            MouseButton::Middle => 1,
            MouseButton::Right => 2,
            MouseButton::None => 3,
        };

        let mut cb = button;
        if event.event_type == MouseEventType::Press {
            cb |= 0; // 按下
        } else if event.event_type == MouseEventType::Release {
            cb |= 0x40; // 释放（SGR 扩展）
        }

        if event.shift {
            cb |= 4;
        }
        if event.meta {
            cb |= 8;
        }
        if event.ctrl {
            cb |= 16;
        }

        // SGR 编码格式: CSI < Cb ; Cx ; Cy M/m
        let mut seq = Vec::new();
        seq.extend_from_slice(b"\x1b[<");
        seq.extend_from_slice(cb.to_string().as_bytes());
        seq.push(b';');
        seq.extend_from_slice((event.col + 1).to_string().as_bytes());
        seq.push(b';');
        seq.extend_from_slice((event.row + 1).to_string().as_bytes());
        if event.event_type == MouseEventType::Release {
            seq.push(b'm'); // SGR 释放
        } else {
            seq.push(b'M'); // SGR 按下
        }
        seq
    }

    /// 设置鼠标跟踪模式
    pub fn set_mouse_tracking(&mut self, mode: MouseTrackingMode) {
        self.mouse_tracking_mode = mode;
    }

    /// 设置鼠标按键跟踪
    pub fn set_mouse_button_tracking(&mut self, enabled: bool) {
        self.mouse_button_tracking = enabled;
        if enabled {
            self.mouse_tracking_mode = MouseTrackingMode::Button;
        } else if self.mouse_tracking_mode == MouseTrackingMode::Button {
            self.mouse_tracking_mode = MouseTrackingMode::None;
        }
    }

    /// 设置鼠标运动跟踪
    pub fn set_mouse_motion_tracking(&mut self, enabled: bool) {
        self.mouse_motion_tracking = enabled;
        if enabled {
            self.mouse_tracking_mode = MouseTrackingMode::Any;
        } else if self.mouse_tracking_mode == MouseTrackingMode::Any {
            self.mouse_tracking_mode = MouseTrackingMode::None;
        }
    }

    /// 设置鼠标所有事件跟踪
    pub fn set_mouse_any_event_tracking(&mut self, enabled: bool) {
        self.mouse_any_event_tracking = enabled;
        if enabled {
            self.mouse_tracking_mode = MouseTrackingMode::Any;
        } else if self.mouse_tracking_mode == MouseTrackingMode::Any {
            self.mouse_tracking_mode = MouseTrackingMode::None;
        }
    }

    /// 设置 SGR 属性
    fn set_sgr(&mut self, params: &vte::Params) {
        // 收集所有参数为 Vec<u16>
        let mut p: Vec<u16> = Vec::new();
        for param_group in params.iter() {
            for &param in param_group {
                p.push(param);
            }
        }
        if p.is_empty() {
            self.current_attr = CellAttr::default();
            return;
        }

        let mut i = 0;
        while i < p.len() {
            match p[i] {
                0 => self.current_attr = CellAttr::default(),
                1 => self.current_attr.bold = true,
                2 => self.current_attr.bold = false, // dim/faint 实际映射
                3 => self.current_attr.italic = true,
                4 => self.current_attr.underline = true,
                5 | 6 => {} // blink - 忽略
                7 => self.current_attr.inverse = true,
                8 => {} // hidden - 忽略
                9 => {} // strikethrough - 忽略
                22 => self.current_attr.bold = false,
                23 => self.current_attr.italic = false,
                24 => self.current_attr.underline = false,
                25 => {} // blink off
                27 => self.current_attr.inverse = false,
                28 => {} // hidden off
                29 => {} // strikethrough off
                30..=37 => {
                    self.current_attr.fg = match p[i] - 30 {
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
                38 => {
                    // 扩展前景色
                    if i + 1 < p.len() {
                        match p[i + 1] {
                            5 if i + 2 < p.len() => {
                                // 38;5;N - 256色
                                self.current_attr.fg = Color::Indexed(p[i + 2] as u8);
                                i += 2;
                            }
                            2 if i + 4 < p.len() => {
                                // 38;2;R;G;B - RGB 色
                                self.current_attr.fg = Color::Rgb(
                                    p[i + 2] as u8,
                                    p[i + 3] as u8,
                                    p[i + 4] as u8,
                                );
                                i += 4;
                            }
                            _ => {}
                        }
                    }
                }
                39 => self.current_attr.fg = Color::Default,
                40..=47 => {
                    self.current_attr.bg = match p[i] - 40 {
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
                48 => {
                    // 扩展背景色
                    if i + 1 < p.len() {
                        match p[i + 1] {
                            5 if i + 2 < p.len() => {
                                // 48;5;N - 256色
                                self.current_attr.bg = Color::Indexed(p[i + 2] as u8);
                                i += 2;
                            }
                            2 if i + 4 < p.len() => {
                                // 48;2;R;G;B - RGB 色
                                self.current_attr.bg = Color::Rgb(
                                    p[i + 2] as u8,
                                    p[i + 3] as u8,
                                    p[i + 4] as u8,
                                );
                                i += 4;
                            }
                            _ => {}
                        }
                    }
                }
                49 => self.current_attr.bg = Color::Default,
                90..=97 => {
                    self.current_attr.fg = match p[i] - 90 {
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
                    self.current_attr.bg = match p[i] - 100 {
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
            i += 1;
        }
    }
}

/// VTE Perform trait 实现
struct TerminalPerformer<'a> {
    terminal: &'a mut Terminal,
}

impl<'a> Perform for TerminalPerformer<'a> {
    fn print(&mut self, c: char) {
        self.terminal.put_char(c);
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

    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], ignore: bool, c: char) {
        if ignore {
            return;
        }

        // 检查是否有 '?' 前缀（DEC 私有模式）
        let is_dec = intermediates.first() == Some(&b'?');

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
            'B' | 'e' => {
                // 光标下移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_row = (self.terminal.cursor_row + n).min(self.terminal.rows.saturating_sub(1));
            }
            'C' | 'a' => {
                // 光标右移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_col = (self.terminal.cursor_col + n).min(self.terminal.cols.saturating_sub(1));
            }
            'D' => {
                // 光标左移
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_col = self.terminal.cursor_col.saturating_sub(n);
            }
            'E' => {
                // 光标下移 N 行到行首
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_row = (self.terminal.cursor_row + n).min(self.terminal.rows.saturating_sub(1));
                self.terminal.cursor_col = 0;
            }
            'F' => {
                // 光标上移 N 行到行首
                let n = first_param(params, 1) as usize;
                self.terminal.cursor_row = self.terminal.cursor_row.saturating_sub(n);
                self.terminal.cursor_col = 0;
            }
            'G' | '`' => {
                // 光标水平绝对位置
                let col = first_param(params, 1).saturating_sub(1) as usize;
                self.terminal.cursor_col = col.min(self.terminal.cols.saturating_sub(1));
            }
            'd' => {
                // 光标垂直绝对位置
                let row = first_param(params, 1).saturating_sub(1) as usize;
                self.terminal.cursor_row = row.min(self.terminal.rows.saturating_sub(1));
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
                    3 => {
                        // 清除屏幕和 scrollback
                        self.terminal.clear_screen();
                        self.terminal.scrollback.clear();
                    }
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
            'L' => {
                // 插入 N 行
                let n = first_param(params, 1) as usize;
                self.terminal.insert_lines(n);
            }
            'M' => {
                // 删除 N 行
                let n = first_param(params, 1) as usize;
                self.terminal.delete_lines(n);
            }
            'P' => {
                // 删除 N 个字符
                let n = first_param(params, 1) as usize;
                self.terminal.delete_chars(n);
            }
            '@' => {
                // 插入 N 个字符
                let n = first_param(params, 1) as usize;
                self.terminal.insert_chars(n);
            }
            'S' => {
                // 向上滚动 N 行
                let n = first_param(params, 1) as usize;
                self.terminal.scroll_up_n(n);
            }
            'T' => {
                // 向下滚动 N 行
                let n = first_param(params, 1) as usize;
                self.terminal.scroll_down_n(n);
            }
            'X' => {
                // 擦除 N 个字符（ECH）
                let n = first_param(params, 1) as usize;
                for i in 0..n {
                    let col = self.terminal.cursor_col + i;
                    if col >= self.terminal.cols { break; }
                    if let Some(line) = self.terminal.lines.get_mut(self.terminal.cursor_row) {
                        line.cells[col] = Cell::default();
                    }
                }
            }
            'r' => {
                // 设置滚动区域（DECSTBM）
                let top = first_param(params, 1).saturating_sub(1) as usize;
                let bottom = second_param(params, self.terminal.rows as u16).saturating_sub(1) as usize;
                if top < bottom && bottom < self.terminal.rows {
                    self.terminal.scroll_top = top;
                    self.terminal.scroll_bottom = bottom;
                    // 光标移到 home
                    self.terminal.cursor_row = 0;
                    self.terminal.cursor_col = 0;
                }
            }
            's' => {
                // 保存光标位置
                self.terminal.save_cursor();
            }
            'u' => {
                // 恢复光标位置
                self.terminal.restore_cursor();
            }
            'h' => {
                if is_dec {
                    for param_group in params.iter() {
                        for &param in param_group {
                            match param {
                                25 => self.terminal.cursor_visible = true,
                                7 => {} // 自动换行模式 (DECAWM) - 默认开启
                                1 => {} // 应用光标键模式
                                12 => {} // 光标闪烁
                                1000 => {
                                    // 启用鼠标按键跟踪（X10 模式）
                                    self.terminal.set_mouse_tracking(MouseTrackingMode::Normal);
                                }
                                1002 => {
                                    // 启用鼠标按键事件跟踪
                                    self.terminal.set_mouse_button_tracking(true);
                                }
                                1003 => {
                                    // 启用鼠标所有事件跟踪
                                    self.terminal.set_mouse_any_event_tracking(true);
                                }
                                1006 => {
                                    // 启用 SGR 鼠标编码
                                    // 暂不实现，使用默认编码
                                }
                                1049 => {
                                    // 切换到备用屏幕缓冲区
                                    self.terminal.save_cursor();
                                    self.terminal.clear_screen();
                                }
                                2004 => {} // bracketed paste mode
                                _ => {}
                            }
                        }
                    }
                } else {
                    for param_group in params.iter() {
                        for &param in param_group {
                            match param {
                                4 => self.terminal.insert_mode = true,
                                25 => self.terminal.cursor_visible = true,
                                _ => {}
                            }
                        }
                    }
                }
            }
            'l' => {
                if is_dec {
                    for param_group in params.iter() {
                        for &param in param_group {
                            match param {
                                25 => self.terminal.cursor_visible = false,
                                7 => {} // 关闭自动换行
                                1 => {} // 关闭应用光标键模式
                                1000 => {
                                    // 禁用鼠标跟踪
                                    self.terminal.set_mouse_tracking(MouseTrackingMode::None);
                                }
                                1002 => {
                                    // 禁用鼠标按键事件跟踪
                                    self.terminal.set_mouse_button_tracking(false);
                                }
                                1003 => {
                                    // 禁用鼠标所有事件跟踪
                                    self.terminal.set_mouse_any_event_tracking(false);
                                }
                                1006 => {
                                    // 禁用 SGR 鼠标编码
                                }
                                1049 => {
                                    // 从备用屏幕缓冲区切回
                                    self.terminal.restore_cursor();
                                }
                                2004 => {}
                                _ => {}
                            }
                        }
                    }
                } else {
                    for param_group in params.iter() {
                        for &param in param_group {
                            match param {
                                4 => self.terminal.insert_mode = false,
                                25 => self.terminal.cursor_visible = false,
                                _ => {}
                            }
                        }
                    }
                }
            }
            'n' => {
                // 设备状态报告 (DSR)
                // 暂不实现回复（需要双向通道）
            }
            'c' => {
                // 设备属性查询 (DA)
                // 暂不实现回复
            }
            _ => {}
        }
    }

    fn esc_dispatch(&mut self, _intermediates: &[u8], _ignore: bool, byte: u8) {
        match byte {
            b'7' => self.terminal.save_cursor(),
            b'8' => self.terminal.restore_cursor(),
            b'c' => {
                // RIS - 完全重置
                self.terminal.clear_screen();
                self.terminal.scrollback.clear();
                self.terminal.current_attr = CellAttr::default();
                self.terminal.cursor_visible = true;
                self.terminal.insert_mode = false;
                self.terminal.scroll_top = 0;
                self.terminal.scroll_bottom = self.terminal.rows.saturating_sub(1);
                self.terminal.cursor_row = 0;
                self.terminal.cursor_col = 0;
            }
            b'D' => {
                // IND - 光标下移（相当于 \n 但不回车）
                if self.terminal.cursor_row == self.terminal.scroll_bottom {
                    self.terminal.scroll_up();
                } else if self.terminal.cursor_row < self.terminal.rows - 1 {
                    self.terminal.cursor_row += 1;
                }
            }
            b'M' => {
                // RI - 光标上移（反向换行）
                if self.terminal.cursor_row == self.terminal.scroll_top {
                    self.terminal.scroll_down();
                } else if self.terminal.cursor_row > 0 {
                    self.terminal.cursor_row -= 1;
                }
            }
            b'E' => {
                // NEL - 光标下移到行首
                self.terminal.newline();
            }
            b'H' => {
                // HTS - 设置水平制表位（暂不实现）
            }
            b'=' => {} // DECKPAM - 应用键盘模式
            b'>' => {} // DECKPNM - 普通键盘模式
            _ => {}
        }
    }
}
