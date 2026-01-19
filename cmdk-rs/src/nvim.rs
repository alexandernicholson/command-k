use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

use crate::app::{App, AppState};
use crate::context;
use crate::events::{key_to_action, AppEvent, EventHandler, KeyAction};
use crate::provider;
use crate::session;

use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io::{self, Stdout};

/// Neovim context parsed from the context file
#[derive(Debug, Default)]
pub struct NvimContext {
    pub filepath: Option<String>,
    pub filename: Option<String>,
    pub filetype: Option<String>,
    pub cursor_line: Option<u32>,
    pub cursor_col: Option<u32>,
    pub current_line: Option<String>,
    pub visual_selection: Option<String>,
    pub lsp_diagnostics: Option<String>,
    pub buffer_content: Option<String>,
}

impl NvimContext {
    /// Parse context from the file written by the Neovim plugin
    pub fn from_file(path: &str) -> Result<Self> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read nvim context file: {}", path))?;

        let mut ctx = NvimContext::default();
        let mut env_map: HashMap<String, String> = HashMap::new();

        for line in content.lines() {
            if let Some((key, value)) = line.split_once('=') {
                env_map.insert(key.to_string(), value.replace("\\n", "\n"));
            }
        }

        ctx.filepath = env_map.get("CMDK_NVIM_FILEPATH").cloned().filter(|s| !s.is_empty());
        ctx.filename = env_map.get("CMDK_NVIM_FILENAME").cloned().filter(|s| !s.is_empty());
        ctx.filetype = env_map.get("CMDK_NVIM_FILETYPE").cloned().filter(|s| !s.is_empty());
        ctx.current_line = env_map.get("CMDK_NVIM_CURRENT_LINE").cloned().filter(|s| !s.is_empty());
        ctx.visual_selection = env_map.get("CMDK_NVIM_VISUAL_SELECTION").cloned().filter(|s| !s.is_empty());
        ctx.lsp_diagnostics = env_map.get("CMDK_NVIM_LSP_DIAGNOSTICS").cloned().filter(|s| !s.is_empty());

        if let Some(line) = env_map.get("CMDK_NVIM_CURSOR_LINE") {
            ctx.cursor_line = line.parse().ok();
        }
        if let Some(col) = env_map.get("CMDK_NVIM_CURSOR_COL") {
            ctx.cursor_col = col.parse().ok();
        }

        // Read buffer content from separate file if specified
        if let Some(buffer_file) = env_map.get("CMDK_NVIM_BUFFER_FILE") {
            if Path::new(buffer_file).exists() {
                ctx.buffer_content = fs::read_to_string(buffer_file).ok();
            }
        }

        Ok(ctx)
    }

    /// Format as markdown context for the AI prompt
    pub fn to_markdown(&self) -> String {
        let mut ctx = String::new();
        ctx.push_str("## Neovim Context\n\n");

        if let Some(ref filepath) = self.filepath {
            ctx.push_str(&format!("**File:** {}\n", filepath));
        }

        if let Some(ref filetype) = self.filetype {
            ctx.push_str(&format!("**Filetype:** {}\n", filetype));
        }

        if let (Some(line), Some(col)) = (self.cursor_line, self.cursor_col) {
            ctx.push_str(&format!("**Cursor Position:** Line {}, Column {}\n", line, col));
        }

        if let Some(ref current_line) = self.current_line {
            ctx.push_str(&format!("\n**Current Line:**\n```\n{}\n```\n", current_line));
        }

        if let Some(ref selection) = self.visual_selection {
            ctx.push_str(&format!("\n**Selected Text:**\n```\n{}\n```\n", selection));
        }

        if let Some(ref diagnostics) = self.lsp_diagnostics {
            ctx.push_str(&format!("\n**LSP Diagnostics:**\n```\n{}\n```\n", diagnostics));
        }

        if let Some(ref content) = self.buffer_content {
            // Truncate if too long
            let truncated = if content.len() > 5000 {
                format!("{}...\n(truncated)", &content[..5000])
            } else {
                content.clone()
            };
            
            let lang = self.filetype.as_deref().unwrap_or("");
            ctx.push_str(&format!("\n**Buffer Content:**\n```{}\n{}\n```\n", lang, truncated));
        }

        ctx
    }
}

/// Neovim-specific result actions
#[derive(Debug, Clone, PartialEq)]
pub enum NvimResultAction {
    Insert,      // Insert at cursor
    Replace,     // Replace current line or selection
    Run,         // Execute as keystrokes/command
    Copy,        // Copy to clipboard
    Cancel,      // Cancel/go back
}

/// Write the result and action to files for the Neovim plugin to read
fn write_result(context_file: &str, action: &str, result: &str) -> Result<()> {
    let result_path = format!("{}.result", context_file);
    let action_path = format!("{}.action", context_file);

    fs::write(&result_path, result)?;
    fs::write(&action_path, action)?;

    Ok(())
}

/// Neovim-specific app that extends the base app
pub struct NvimApp {
    pub base: App,
    pub nvim_context: NvimContext,
    pub context_file: String,
    pub nvim_actions: Vec<NvimResultAction>,
    pub nvim_selected: usize,
}

impl NvimApp {
    pub fn new(context_file: &str) -> Result<Self> {
        let nvim_context = NvimContext::from_file(context_file)?;
        let base = App::new()?;

        Ok(Self {
            base,
            nvim_context,
            context_file: context_file.to_string(),
            nvim_actions: vec![
                NvimResultAction::Insert,
                NvimResultAction::Replace,
                NvimResultAction::Run,
                NvimResultAction::Copy,
                NvimResultAction::Cancel,
            ],
            nvim_selected: 0,
        })
    }

    /// Gather combined context (terminal + neovim)
    pub fn gather_full_context(&self) -> Result<String> {
        let mut ctx = String::new();

        // Terminal context (respects privacy settings)
        ctx.push_str(&context::gather_context()?);

        // Neovim-specific context
        ctx.push('\n');
        ctx.push_str(&self.nvim_context.to_markdown());

        Ok(ctx)
    }

    /// Get display-friendly context for the context view
    pub fn get_context_display(&self) -> String {
        let mut lines = Vec::new();

        lines.push("=== Neovim Context ===".to_string());
        lines.push(String::new());

        if let Some(ref filepath) = self.nvim_context.filepath {
            lines.push(format!("File: {}", filepath));
        }

        if let Some(ref filetype) = self.nvim_context.filetype {
            lines.push(format!("Filetype: {}", filetype));
        }

        if let (Some(line), Some(col)) = (self.nvim_context.cursor_line, self.nvim_context.cursor_col) {
            lines.push(format!("Cursor: Line {}, Column {}", line, col));
        }

        if let Some(ref current_line) = self.nvim_context.current_line {
            lines.push(String::new());
            lines.push("Current Line:".to_string());
            lines.push(format!("  {}", current_line));
        }

        if let Some(ref selection) = self.nvim_context.visual_selection {
            lines.push(String::new());
            lines.push("Visual Selection:".to_string());
            for line in selection.lines().take(10) {
                lines.push(format!("  {}", line));
            }
            if selection.lines().count() > 10 {
                lines.push("  ... (truncated)".to_string());
            }
        }

        if let Some(ref diagnostics) = self.nvim_context.lsp_diagnostics {
            lines.push(String::new());
            lines.push("LSP Diagnostics:".to_string());
            for line in diagnostics.lines().take(5) {
                lines.push(format!("  {}", line));
            }
        }

        if let Some(ref content) = self.nvim_context.buffer_content {
            lines.push(String::new());
            lines.push(format!("Buffer Content: {} chars", content.len()));
            lines.push("  (first 500 chars)".to_string());
            let preview: String = content.chars().take(500).collect();
            for line in preview.lines().take(10) {
                lines.push(format!("  {}", line));
            }
            if content.lines().count() > 10 {
                lines.push("  ...".to_string());
            }
        }

        lines.push(String::new());
        lines.push("=== Terminal Context ===".to_string());
        lines.push(String::new());

        if let Ok(terminal_ctx) = context::gather_context_display() {
            lines.push(terminal_ctx);
        }

        lines.join("\n")
    }

    /// Start an async query with Neovim context
    pub fn start_nvim_query(&mut self, query: &str) -> Result<()> {
        use std::sync::mpsc;
        use std::thread;

        // Save to prompt history
        session::add_to_prompt_history(query)?;

        // Get combined context
        let ctx = self.gather_full_context()?;

        // Get session history
        let history = session::get_session_history()?;

        // Build full prompt
        let full_prompt = provider::build_full_prompt(query, &ctx, history.as_deref());

        // Store the query for session saving later
        self.base.pending_query = Some(query.to_string());

        // Create channel for result
        let (tx, rx) = mpsc::channel();
        self.base.query_receiver = Some(rx);

        // Run query in background thread
        thread::spawn(move || {
            let result = provider::run_query(&full_prompt);
            let _ = tx.send(result.map_err(|e| e.to_string()));
        });

        // Set loading state
        self.base.state = AppState::Loading;

        Ok(())
    }
}

/// Setup terminal for TUI
fn setup_terminal() -> Result<Terminal<CrosstermBackend<Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let terminal = Terminal::new(backend)?;
    Ok(terminal)
}

/// Restore terminal state
fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<Stdout>>) -> Result<()> {
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    Ok(())
}

/// Render function for Neovim mode (reuses base UI with modifications)
fn render_nvim(frame: &mut ratatui::Frame, app: &NvimApp) {
    use ratatui::{
        layout::{Alignment, Constraint, Direction, Layout},
        style::{Color, Modifier, Style},
        text::{Line, Span},
        widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    };

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(5),  // Header
            Constraint::Min(10),    // Content
            Constraint::Length(3),  // Status bar
        ])
        .split(frame.area());

    // Header with Neovim info
    let mut header_lines = vec![
        Line::from(vec![
            Span::styled(
                "⌘K ",
                Style::default()
                    .fg(Color::Magenta)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                "Command K",
                Style::default()
                    .fg(Color::Magenta)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                " (Neovim)",
                Style::default().fg(Color::Cyan),
            ),
        ]),
        Line::from(""),
    ];

    // Show file info
    if let Some(ref filename) = app.nvim_context.filename {
        let filetype = app.nvim_context.filetype.as_deref().unwrap_or("unknown");
        header_lines.push(Line::from(Span::styled(
            format!("File: {} [{}]", filename, filetype),
            Style::default().fg(Color::Gray),
        )));
    }

    if app.base.session_turns > 0 {
        header_lines.push(Line::from(Span::styled(
            format!("↪ Continuing conversation ({} previous turns)", app.base.session_turns),
            Style::default().fg(Color::Green),
        )));
    }

    let header = Paragraph::new(header_lines)
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Magenta))
                .title(" cmdk-rs ")
                .title_style(Style::default().fg(Color::Magenta)),
        );

    frame.render_widget(header, chunks[0]);

    // Content area - reuse base rendering for most states
    // Render content based on state
    match &app.base.state {
        AppState::ShowingResult { response } => {
            // Custom result view with Neovim-specific actions
            let content_chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Min(5), Constraint::Length(8)])
                .split(chunks[1]);

            let response_text = Paragraph::new(response.as_str())
                .style(Style::default().fg(Color::Green))
                .wrap(Wrap { trim: false })
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title(" Response ")
                        .border_style(Style::default().fg(Color::Green)),
                );

            frame.render_widget(response_text, content_chunks[0]);

            // Neovim-specific actions
            let actions: Vec<ListItem> = app
                .nvim_actions
                .iter()
                .enumerate()
                .map(|(i, action)| {
                    let style = if i == app.nvim_selected {
                        Style::default()
                            .fg(Color::Magenta)
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };

                    let prefix = if i == app.nvim_selected { "▶ " } else { "  " };
                    let text = match action {
                        NvimResultAction::Insert => "Insert at cursor",
                        NvimResultAction::Replace => "Replace line/selection",
                        NvimResultAction::Run => "Run/execute keys",
                        NvimResultAction::Copy => "Copy to clipboard",
                        NvimResultAction::Cancel => "Cancel",
                    };

                    ListItem::new(Line::from(format!("{}{}", prefix, text))).style(style)
                })
                .collect();

            let action_list = List::new(actions).block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(" Actions ")
                    .border_style(Style::default().fg(Color::White)),
            );

            frame.render_widget(action_list, content_chunks[1]);
        }
        AppState::MainMenu => {
            // Render menu
            let items: Vec<ListItem> = app.base.menu_items
                .iter()
                .enumerate()
                .map(|(i, item)| {
                    let style = if i == app.base.selected_index {
                        Style::default().fg(Color::Magenta).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    let prefix = if i == app.base.selected_index { "▶ " } else { "  " };
                    let text = match item {
                        crate::app::MenuItem::AskQuestion => "Ask a question",
                        crate::app::MenuItem::RecentPrompts => "Recent prompts",
                        crate::app::MenuItem::ViewContext => "View context",
                        crate::app::MenuItem::PrivacySettings => "Privacy settings",
                        crate::app::MenuItem::ClearConversation => "Clear conversation",
                        crate::app::MenuItem::Exit => "Exit",
                    };
                    ListItem::new(Line::from(format!("{}{}", prefix, text))).style(style)
                })
                .collect();

            let list = List::new(items).block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(" Menu ")
                    .border_style(Style::default().fg(Color::White)),
            );
            frame.render_widget(list, chunks[1]);
        }
        AppState::PromptInput => {
            // Render input
            let input_chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Length(3), Constraint::Min(1)])
                .split(chunks[1]);

            let input = Paragraph::new(app.base.input.as_str())
                .style(Style::default().fg(Color::White))
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title(" What do you need? ")
                        .border_style(Style::default().fg(Color::Magenta)),
                );
            frame.render_widget(input, input_chunks[0]);

            // Show cursor
            frame.set_cursor_position((
                input_chunks[0].x + app.base.cursor_position as u16 + 1,
                input_chunks[0].y + 1,
            ));

            let help = Paragraph::new("Press Enter to submit, Esc to cancel")
                .style(Style::default().fg(Color::Gray))
                .alignment(Alignment::Center);
            frame.render_widget(help, input_chunks[1]);
        }
        AppState::Loading => {
            // Render loading with spinner
            const SPINNER_FRAMES: &[&str] = &["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
            let spinner = SPINNER_FRAMES[app.base.spinner_frame % SPINNER_FRAMES.len()];

            let loading_text = vec![
                Line::from(""),
                Line::from(vec![
                    Span::styled(format!("{} ", spinner), Style::default().fg(Color::Cyan)),
                    Span::styled("Thinking...", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
                ]),
                Line::from(""),
                Line::from(Span::styled(
                    format!("Using {}", app.base.current_provider),
                    Style::default().fg(Color::DarkGray),
                )),
            ];

            let loading = Paragraph::new(loading_text)
                .alignment(Alignment::Center)
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .border_style(Style::default().fg(Color::Yellow)),
                );
            frame.render_widget(loading, chunks[1]);
        }
        AppState::Error { message } => {
            let error = Paragraph::new(message.as_str())
                .style(Style::default().fg(Color::Red))
                .wrap(Wrap { trim: false })
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title(" Error ")
                        .border_style(Style::default().fg(Color::Red)),
                );
            frame.render_widget(error, chunks[1]);
        }
        AppState::ContextView => {
            // Show Neovim-specific context
            let context_text = app.get_context_display();
            let context = Paragraph::new(context_text)
                .style(Style::default().fg(Color::Cyan))
                .wrap(Wrap { trim: false })
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title(" Current Context (Neovim) ")
                        .border_style(Style::default().fg(Color::Cyan)),
                );
            frame.render_widget(context, chunks[1]);
        }
        _ => {
            // Fallback for other states
            let msg = Paragraph::new("...")
                .alignment(Alignment::Center)
                .block(Block::default().borders(Borders::ALL));
            frame.render_widget(msg, chunks[1]);
        }
    }

    // Status bar - split into three sections
    let status_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(50),
            Constraint::Percentage(25),
        ])
        .split(chunks[2]);

    // Left: Provider info
    let provider_text = Line::from(vec![
        Span::styled("AI: ", Style::default().fg(Color::DarkGray)),
        Span::styled(
            &app.base.current_provider,
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        ),
    ]);
    let provider = Paragraph::new(provider_text)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
    frame.render_widget(provider, status_chunks[0]);

    // Center: Help text
    let help_text = match &app.base.state {
        AppState::ShowingResult { .. } => "↑↓: Navigate | Enter: Select | Esc: Cancel",
        _ => "↑↓: Navigate | Enter: Select | q: Quit",
    };
    let help = Paragraph::new(help_text)
        .style(Style::default().fg(Color::Gray))
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
    frame.render_widget(help, status_chunks[1]);

    // Right: File info
    let file_info = app.nvim_context.filename.as_deref().unwrap_or("untitled");
    let file_text = Line::from(vec![
        Span::styled("📄 ", Style::default()),
        Span::styled(file_info, Style::default().fg(Color::DarkGray)),
    ]);
    let file_widget = Paragraph::new(file_text)
        .alignment(Alignment::Right)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
    frame.render_widget(file_widget, status_chunks[2]);
}

/// Run Neovim interactive mode
pub fn run_nvim_mode(context_file: &str) -> Result<()> {
    let mut terminal = setup_terminal()?;
    let mut app = NvimApp::new(context_file)?;
    let event_handler = EventHandler::new(100);

    // Clean up stale sessions
    session::cleanup_stale_session()?;

    let mut result_action: Option<NvimResultAction> = None;

    while app.base.running {
        // Check if async query is complete
        if matches!(app.base.state, AppState::Loading) {
            if app.base.check_query_complete()? {
                app.nvim_selected = 0;  // Reset action selection when result comes in
            }
            app.base.tick_spinner();
        }

        // Draw UI
        terminal.draw(|f| render_nvim(f, &app))?;

        // Handle events (but not during loading - just animate)
        if let Some(event) = event_handler.next()? {
            if matches!(app.base.state, AppState::Loading) {
                continue;  // Skip input during loading
            }

            let AppEvent::Key(key) = event;
            match &app.base.state {
                AppState::ShowingResult { .. } => {
                    // Handle Neovim-specific result actions
                    let action = key_to_action(key);
                    match action {
                        KeyAction::Up => {
                            if app.nvim_selected > 0 {
                                app.nvim_selected -= 1;
                            }
                        }
                        KeyAction::Down => {
                            if app.nvim_selected < app.nvim_actions.len() - 1 {
                                app.nvim_selected += 1;
                            }
                        }
                        KeyAction::Select => {
                            result_action = Some(app.nvim_actions[app.nvim_selected].clone());
                            app.base.running = false;
                        }
                        KeyAction::Back | KeyAction::Quit => {
                            result_action = Some(NvimResultAction::Cancel);
                            app.base.running = false;
                        }
                        _ => {}
                    }
                }
                AppState::PromptInput => {
                    // Override submit to use Neovim context
                    use crate::events::key_to_input_action;
                    let action = key_to_input_action(key);
                    
                    match action {
                        KeyAction::Select => {
                            if !app.base.input.trim().is_empty() {
                                let query = app.base.input.clone();
                                app.start_nvim_query(&query)?;
                            }
                        }
                        _ => {
                            // Use base handling for other input actions
                            app.base.handle_key(AppEvent::Key(key))?;
                        }
                    }
                }
                _ => {
                    // Use base app handling for other states
                    app.base.handle_key(AppEvent::Key(key))?;
                }
            }
        }
    }

    // Restore terminal
    restore_terminal(&mut terminal)?;

    // Write result for Neovim plugin
    if let Some(action) = result_action {
        if let Some(ref response) = app.base.last_response {
            let action_str = match action {
                NvimResultAction::Insert => "insert",
                NvimResultAction::Replace => "replace",
                NvimResultAction::Run => "run",
                NvimResultAction::Copy => "copy",
                NvimResultAction::Cancel => "cancel",
            };
            write_result(&app.context_file, action_str, response)?;
        }
    }

    Ok(())
}

/// Run Neovim quick query mode (non-interactive)
pub fn run_nvim_query_mode(context_file: &str, query: &str) -> Result<()> {
    let nvim_context = NvimContext::from_file(context_file)?;

    // Get terminal context
    let terminal_ctx = context::gather_context()?;

    // Combine contexts
    let mut full_ctx = terminal_ctx;
    full_ctx.push('\n');
    full_ctx.push_str(&nvim_context.to_markdown());

    // Build prompt
    let full_prompt = provider::build_full_prompt(query, &full_ctx, None);

    // Run query
    let response = provider::run_query(&full_prompt)?;

    // Print response
    println!("{}", response);

    Ok(())
}
