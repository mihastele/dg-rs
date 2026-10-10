//! Application state and event loop for the TUI.

use crate::db::Database;
use crate::model::{ConnectionConfig, ResultSet, Schema, Table};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{
        Block, Borders, Cell, Clear, List, ListItem, ListState, Paragraph, Row, Table as TuiTable,
        TableState, Wrap,
    },
    Frame,
};
use std::sync::Arc;
use tokio::sync::Mutex;

/// Which pane has keyboard focus.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Focus {
    SchemaTree,
    SqlEditor,
    Results,
}

/// View mode for the right pane.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RightPane {
    SqlEditor,
    Results,
}

pub struct App {
    pub db: Arc<Mutex<Box<dyn Database>>>,
    pub config: ConnectionConfig,
    pub schemas: Vec<Schema>,
    pub selected_schema: usize,
    pub selected_table: usize,
    pub focus: Focus,

    // SQL editor
    pub sql_input: String,
    pub cursor_pos: usize,

    // Results
    pub result: Option<ResultSet>,
    pub result_scroll: (u16, u16), // (row, col) scroll offset
    pub table_state: TableState,

    // UI state
    pub should_quit: bool,
    pub status_message: String,
    pub show_help: bool,
    pub expanded_schemas: Vec<bool>,
}

impl App {
    pub fn new(db: Box<dyn Database>, config: ConnectionConfig) -> Self {
        Self {
            db: Arc::new(Mutex::new(db)),
            config,
            schemas: Vec::new(),
            selected_schema: 0,
            selected_table: 0,
            focus: Focus::SchemaTree,
            sql_input: String::new(),
            cursor_pos: 0,
            result: None,
            result_scroll: (0, 0),
            table_state: TableState::default(),
            should_quit: false,
            status_message: String::new(),
            show_help: false,
            expanded_schemas: Vec::new(),
        }
    }

    pub async fn load_schemas(&mut self) {
        let db = self.db.lock().await;
        match db.introspect().await {
            Ok(schemas) => {
                let count: usize = schemas.iter().map(|s| s.tables.len()).sum();
                self.expanded_schemas = vec![true; schemas.len()];
                self.status_message = format!("Loaded {} schemas, {} tables", schemas.len(), count);
                self.schemas = schemas;
            }
            Err(e) => {
                self.status_message = format!("Introspection error: {}", e);
            }
        }
    }

    pub async fn run_query(&mut self) {
        if self.sql_input.trim().is_empty() {
            self.status_message = "No SQL to execute".to_string();
            return;
        }

        let sql = self.sql_input.clone();
        let db = self.db.lock().await;

        // Try as a query first, fall back to execute
        match db.query(&sql).await {
            Ok(result) => {
                self.status_message = format!(
                    "{} rows in {}ms",
                    result.row_count, result.execution_time_ms
                );
                self.result = Some(result);
                self.result_scroll = (0, 0);
            }
            Err(_) => {
                // Try as execute (DDL/DML without result set)
                match db.execute(&sql).await {
                    Ok(affected) => {
                        self.status_message = format!("OK, {} rows affected", affected);
                        self.result = None;
                    }
                    Err(e) => {
                        self.status_message = format!("Error: {}", e);
                    }
                }
            }
        }
    }

    pub fn render(&mut self, frame: &mut Frame) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1), // status bar
                Constraint::Min(10),   // main area
                Constraint::Length(3), // input bar
            ])
            .split(frame.area());

        // Status bar
        self.render_status_bar(frame, chunks[0]);

        // Main area: split into left (schema tree) and right (editor/results)
        let main_chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Length(30), // schema tree
                Constraint::Min(20),    // right pane
            ])
            .split(chunks[1]);

        self.render_schema_tree(frame, main_chunks[0]);

        // Right pane: split vertically into editor (top) and results (bottom)
        let right_chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(8), // SQL editor
                Constraint::Min(5),    // results
            ])
            .split(main_chunks[1]);

        self.render_sql_editor(frame, right_chunks[0]);
        self.render_results(frame, right_chunks[1]);

        // Input bar at bottom (for quick SQL entry)
        self.render_input_bar(frame, chunks[2]);

        // Help overlay
        if self.show_help {
            self.render_help_overlay(frame);
        }
    }

    fn render_status_bar(&self, frame: &mut Frame, area: Rect) {
        let version = format!("{}", self.config.db_type);
        let conn = &self.config.name;
        let status = &self.status_message;

        let spans = vec![
            Span::styled(" ◆ datagrip-rs ", Style::default().fg(Color::Black).bg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Span::raw(" │ "),
            Span::styled(format!(" {} ", conn), Style::default().fg(Color::Green)),
            Span::raw(" │ "),
            Span::styled(format!(" {} ", version), Style::default().fg(Color::Yellow)),
            Span::raw(" │ "),
            Span::styled(format!(" {} schemas ", self.schemas.len()), Style::default().fg(Color::White)),
            Span::raw(" │ "),
            Span::styled(status.clone(), Style::default().fg(Color::Gray)),
            Span::raw(" │ "),
            Span::styled(" [F1: Help] [F5: Run] [Tab: Focus] [q: Quit] ", Style::default().fg(Color::DarkGray)),
        ];

        let line = Line::from(spans);
        frame.render_widget(Paragraph::new(line).style(Style::default().bg(Color::Black)), area);
    }

    fn render_schema_tree(&mut self, frame: &mut Frame, area: Rect) {
        let is_focused = self.focus == Focus::SchemaTree;
        let border_style = if is_focused {
            Style::default().fg(Color::Cyan)
        } else {
            Style::default().fg(Color::DarkGray)
        };

        let mut items = Vec::new();
        let mut flat_index = 0usize;

        for (si, schema) in self.schemas.iter().enumerate() {
            let expanded = self.expanded_schemas.get(si).copied().unwrap_or(true);
            let arrow = if expanded { "▼" } else { "▶" };
            let schema_style = if si == self.selected_schema && is_focused {
                Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::Yellow)
            };

            items.push(ListItem::new(Line::from(Span::styled(
                format!("{} 📁 {}", arrow, schema.name),
                schema_style,
            ))));
            flat_index += 1;

            if expanded {
                for table in &schema.tables {
                    let table_style = if si == self.selected_schema
                        && flat_index - 1 == self.selected_table
                        && is_focused
                    {
                        Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(Color::White)
                    };

                    let col_count = table.columns.len();
                    items.push(ListItem::new(Line::from(vec![
                        Span::raw("    "),
                        Span::styled(
                            format!("{} {}", table.kind.icon(), table.name),
                            table_style,
                        ),
                        Span::styled(
                            format!(" ({} cols)", col_count),
                            Style::default().fg(Color::DarkGray),
                        ),
                    ])));
                    flat_index += 1;
                }
            }
        }

        if items.is_empty() {
            items.push(ListItem::new(Line::from(Span::styled(
                "  Loading schemas...",
                Style::default().fg(Color::DarkGray),
            ))));
        }

        let list = List::new(items)
            .block(
                Block::default()
                    .title(" Schema Explorer ")
                    .borders(Borders::ALL)
                    .border_style(border_style),
            );

        let mut state = ListState::default();
        state.select(Some(self.selected_schema));
        frame.render_stateful_widget(list, area, &mut state);
    }

    fn render_sql_editor(&self, frame: &mut Frame, area: Rect) {
        let is_focused = self.focus == Focus::SqlEditor;
        let border_style = if is_focused {
            Style::default().fg(Color::Green)
        } else {
            Style::default().fg(Color::DarkGray)
        };

        let sql_display = if self.sql_input.is_empty() {
            "-- Write SQL here, press F5 or Ctrl+Enter to run".to_string()
        } else {
            self.sql_input.clone()
        };

        let editor = Paragraph::new(sql_display)
            .style(Style::default().fg(Color::White))
            .block(
                Block::default()
                    .title(" SQL Editor ")
                    .borders(Borders::ALL)
                    .border_style(border_style),
            )
            .wrap(Wrap { trim: false });

        frame.render_widget(editor, area);
    }

    fn render_results(&mut self, frame: &mut Frame, area: Rect) {
        let is_focused = self.focus == Focus::Results;
        let border_style = if is_focused {
            Style::default().fg(Color::Magenta)
        } else {
            Style::default().fg(Color::DarkGray)
        };

        let block = Block::default()
            .title(" Results ")
            .borders(Borders::ALL)
            .border_style(border_style);

        match &self.result {
            Some(result) => {
                // Build table rows
                let header_cells: Vec<Cell> = result
                    .columns
                    .iter()
                    .map(|c| Cell::from(c.clone()).style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)))
                    .collect();

                let header = Row::new(header_cells).height(1);

                let rows: Vec<Row> = result
                    .rows
                    .iter()
                    .take(1000) // Limit rendering for performance
                    .map(|row| {
                        let cells: Vec<Cell> = row
                            .iter()
                            .map(|cell| {
                                let text = cell.as_deref().unwrap_or("NULL");
                                let style = if cell.is_none() {
                                    Style::default().fg(Color::DarkGray)
                                } else {
                                    Style::default().fg(Color::White)
                                };
                                Cell::from(text).style(style)
                            })
                            .collect();
                        Row::new(cells).height(1)
                    })
                    .collect();

                // Calculate column widths
                let col_count = result.columns.len();
                let widths: Vec<Constraint> = (0..col_count)
                    .map(|_| Constraint::Min(10))
                    .collect();

                let table = TuiTable::new(rows, widths)
                    .header(header)
                    .block(block)
                    .row_highlight_style(
                        Style::default()
                            .bg(Color::DarkGray)
                            .add_modifier(Modifier::BOLD),
                    );

                // Update selection
                if !result.rows.is_empty() {
                    let selected = self.result_scroll.0 as usize;
                    self.table_state.select(Some(selected.min(result.rows.len() - 1)));
                }

                frame.render_stateful_widget(table, area, &mut self.table_state);
            }
            None => {
                let msg = if self.status_message.is_empty() {
                    "No results yet. Write SQL and press F5 to run."
                } else {
                    &self.status_message
                };
                let para = Paragraph::new(msg.to_string())
                    .style(Style::default().fg(Color::DarkGray))
                    .block(block);
                frame.render_widget(para, area);
            }
        }
    }

    fn render_input_bar(&self, frame: &mut Frame, area: Rect) {
        let input_display = if self.sql_input.is_empty() {
            Line::from(Span::styled(
                "> _",
                Style::default().fg(Color::Green),
            ))
        } else {
            Line::from(vec![
                Span::styled("> ", Style::default().fg(Color::Green)),
                Span::raw(&self.sql_input),
                Span::styled("_", Style::default().fg(Color::Green)),
            ])
        };

        let input = Paragraph::new(input_display).block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray))
                .title(" Quick SQL (Enter to execute) "),
        );
        frame.render_widget(input, area);
    }

    fn render_help_overlay(&self, frame: &mut Frame) {
        let area = centered_rect(50, 60, frame.area());

        let help_text = vec![
            Line::from(Span::styled(" Keyboard Shortcuts", Style::default().add_modifier(Modifier::BOLD))),
            Line::from(""),
            Line::from("  Tab          Switch focus (Tree → Editor → Results)"),
            Line::from("  F1           Toggle this help"),
            Line::from("  F5 / Ctrl+E  Run SQL query"),
            Line::from("  Ctrl+C       Copy selected cell"),
            Line::from("  Ctrl+E       Export results to CSV"),
            Line::from("  ↑/↓          Navigate schema tree / scroll results"),
            Line::from("  ←/→          Collapse/expand schema"),
            Line::from("  Enter        Execute SQL from input bar"),
            Line::from("  Esc          Clear input / close overlay"),
            Line::from("  q            Quit (when not typing)"),
            Line::from(""),
            Line::from(Span::styled("  Press F1 or Esc to close", Style::default().fg(Color::DarkGray))),
        ];

        let para = Paragraph::new(help_text)
            .block(
                Block::default()
                    .title(" Help ")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Cyan)),
            )
            .style(Style::default().bg(Color::Black));

        frame.render_widget(Clear, area);
        frame.render_widget(para, area);
    }

    // === Navigation ===

    pub fn next_schema(&mut self) {
        if !self.schemas.is_empty() {
            self.selected_schema = (self.selected_schema + 1) % self.schemas.len();
            self.selected_table = 0;
        }
    }

    pub fn prev_schema(&mut self) {
        if !self.schemas.is_empty() {
            self.selected_schema = if self.selected_schema == 0 {
                self.schemas.len() - 1
            } else {
                self.selected_schema - 1
            };
            self.selected_table = 0;
        }
    }

    pub fn toggle_schema(&mut self) {
        if let Some(expanded) = self.expanded_schemas.get_mut(self.selected_schema) {
            *expanded = !*expanded;
        }
    }

    pub fn scroll_results_up(&mut self) {
        if self.result_scroll.0 > 0 {
            self.result_scroll.0 -= 1;
        }
    }

    pub fn scroll_results_down(&mut self) {
        if let Some(result) = &self.result {
            if (self.result_scroll.0 as usize) < result.rows.len().saturating_sub(1) {
                self.result_scroll.0 += 1;
            }
        }
    }

    pub fn input_char(&mut self, c: char) {
        self.sql_input.insert(self.cursor_pos, c);
        self.cursor_pos += 1;
    }

    pub fn input_backspace(&mut self) {
        if self.cursor_pos > 0 {
            self.cursor_pos -= 1;
            self.sql_input.remove(self.cursor_pos);
        }
    }

    pub fn input_newline(&mut self) {
        self.sql_input.insert(self.cursor_pos, '\n');
        self.cursor_pos += 1;
    }
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}
