use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::app::{App, AppState, MenuItem, ResultAction, SettingsMenuItem};

/// Main UI rendering function
pub fn render(frame: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(5),  // Header
            Constraint::Min(10),    // Content
            Constraint::Length(3),  // Status bar
        ])
        .split(frame.area());

    render_header(frame, app, chunks[0]);
    render_content(frame, app, chunks[1]);
    render_status_bar(frame, app, chunks[2]);
}

/// Render the header
fn render_header(frame: &mut Frame, app: &App, area: Rect) {
    let title = vec![
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
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "AI-powered command assistance",
            Style::default().fg(Color::Gray),
        )),
    ];

    // Add session info if available
    let mut lines = title;
    if app.session_turns > 0 {
        lines.push(Line::from(Span::styled(
            format!("↪ Continuing conversation ({} previous turns)", app.session_turns),
            Style::default().fg(Color::Green),
        )));
    }

    let header = Paragraph::new(lines)
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Magenta))
                .title(" cmdk-rs ")
                .title_style(Style::default().fg(Color::Magenta)),
        );

    frame.render_widget(header, area);
}

/// Render the main content area based on app state
fn render_content(frame: &mut Frame, app: &App, area: Rect) {
    match &app.state {
        AppState::MainMenu => render_main_menu(frame, app, area),
        AppState::PromptInput => render_prompt_input(frame, app, area),
        AppState::Loading => render_loading(frame, app, area),
        AppState::ShowingResult { response } => render_result(frame, app, response, area),
        AppState::ContextView => render_context_view(frame, app, area),
        AppState::SettingsMenu => render_settings_menu(frame, app, area),
        AppState::RecentPrompts => render_recent_prompts(frame, app, area),
        AppState::Error { message } => render_error(frame, message, area),
    }
}

/// Render the main menu
fn render_main_menu(frame: &mut Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = app
        .menu_items
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let style = if i == app.selected_index {
                Style::default()
                    .fg(Color::Magenta)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let prefix = if i == app.selected_index { "▶ " } else { "  " };
            let text = match item {
                MenuItem::AskQuestion => "Ask a question",
                MenuItem::RecentPrompts => "Recent prompts",
                MenuItem::ViewContext => "View context",
                MenuItem::PrivacySettings => "Privacy settings",
                MenuItem::ClearConversation => "Clear conversation",
                MenuItem::Exit => "Exit",
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

    frame.render_widget(list, area);
}

/// Render the prompt input
fn render_prompt_input(frame: &mut Frame, app: &App, area: Rect) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(1)])
        .split(area);

    let input = Paragraph::new(app.input.as_str())
        .style(Style::default().fg(Color::White))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" What do you need? ")
                .border_style(Style::default().fg(Color::Magenta)),
        );

    frame.render_widget(input, chunks[0]);

    // Show cursor position
    frame.set_cursor_position((
        chunks[0].x + app.cursor_position as u16 + 1,
        chunks[0].y + 1,
    ));

    let help = Paragraph::new("Press Enter to submit, Esc to cancel")
        .style(Style::default().fg(Color::Gray))
        .alignment(Alignment::Center);

    frame.render_widget(help, chunks[1]);
}

/// Spinner frames for animation
const SPINNER_FRAMES: &[&str] = &["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

/// Render loading state
fn render_loading(frame: &mut Frame, app: &App, area: Rect) {
    let spinner = SPINNER_FRAMES[app.spinner_frame % SPINNER_FRAMES.len()];
    
    let loading_text = vec![
        Line::from(""),
        Line::from(vec![
            Span::styled(
                format!("{} ", spinner),
                Style::default().fg(Color::Cyan),
            ),
            Span::styled(
                "Thinking...",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled(
                format!("Using {}", app.current_provider),
                Style::default().fg(Color::DarkGray),
            ),
        ]),
    ];

    let loading = Paragraph::new(loading_text)
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow)),
        );

    frame.render_widget(loading, area);
}

/// Render the result view
fn render_result(frame: &mut Frame, app: &App, response: &str, area: Rect) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(5), Constraint::Length(8)])
        .split(area);

    // Response display
    let response_text = Paragraph::new(response)
        .style(Style::default().fg(Color::Green))
        .wrap(Wrap { trim: false })
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Response ")
                .border_style(Style::default().fg(Color::Green)),
        );

    frame.render_widget(response_text, chunks[0]);

    // Action menu
    let actions: Vec<ListItem> = app
        .result_actions
        .iter()
        .enumerate()
        .map(|(i, action)| {
            let style = if i == app.result_selected {
                Style::default()
                    .fg(Color::Magenta)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let prefix = if i == app.result_selected {
                "▶ "
            } else {
                "  "
            };
            let text = match action {
                ResultAction::RunCommand => "Run command",
                ResultAction::CopyToClipboard => "Copy to clipboard",
                ResultAction::AskFollowUp => "Ask follow-up",
                ResultAction::BackToMenu => "Back to menu",
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

    frame.render_widget(action_list, chunks[1]);
}

/// Render context view
fn render_context_view(frame: &mut Frame, app: &App, area: Rect) {
    let context = Paragraph::new(app.context_display.as_str())
        .style(Style::default().fg(Color::Cyan))
        .wrap(Wrap { trim: false })
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Current Context ")
                .border_style(Style::default().fg(Color::Cyan)),
        );

    frame.render_widget(context, area);
}

/// Render settings menu
fn render_settings_menu(frame: &mut Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = app
        .settings_items
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let style = if i == app.settings_selected {
                Style::default()
                    .fg(Color::Magenta)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let prefix = if i == app.settings_selected {
                "▶ "
            } else {
                "  "
            };

            let text = match item {
                SettingsMenuItem::ChangeProvider => {
                    format!("🤖 Change AI provider (current: {})", app.current_provider)
                }
                SettingsMenuItem::Separator => "─────────────".to_string(),
                SettingsMenuItem::Toggle { key: _, label, enabled } => {
                    let check = if *enabled { "✓" } else { "✗" };
                    format!("{} {}", check, label)
                }
                SettingsMenuItem::Separator2 => "─────────────".to_string(),
                SettingsMenuItem::EnableAll => "Enable all".to_string(),
                SettingsMenuItem::DisableAll => "Disable all".to_string(),
                SettingsMenuItem::Back => "← Back".to_string(),
            };

            ListItem::new(Line::from(format!("{}{}", prefix, text))).style(style)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Settings ")
            .border_style(Style::default().fg(Color::Magenta)),
    );

    frame.render_widget(list, area);
}

/// Render recent prompts
fn render_recent_prompts(frame: &mut Frame, app: &App, area: Rect) {
    if app.recent_prompts.is_empty() {
        let msg = Paragraph::new("No prompt history yet")
            .style(Style::default().fg(Color::Yellow))
            .alignment(Alignment::Center)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(" Recent Prompts "),
            );
        frame.render_widget(msg, area);
        return;
    }

    let items: Vec<ListItem> = app
        .recent_prompts
        .iter()
        .enumerate()
        .map(|(i, prompt)| {
            let style = if i == app.prompts_selected {
                Style::default()
                    .fg(Color::Magenta)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let prefix = if i == app.prompts_selected {
                "▶ "
            } else {
                "  "
            };

            // Truncate long prompts
            let display = if prompt.len() > 60 {
                format!("{}...", &prompt[..57])
            } else {
                prompt.clone()
            };

            ListItem::new(Line::from(format!("{}{}", prefix, display))).style(style)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Recent Prompts (Enter to select, Esc to go back) ")
            .border_style(Style::default().fg(Color::Cyan)),
    );

    frame.render_widget(list, area);
}

/// Render error message
fn render_error(frame: &mut Frame, message: &str, area: Rect) {
    let error = Paragraph::new(message)
        .style(Style::default().fg(Color::Red))
        .wrap(Wrap { trim: false })
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Error ")
                .border_style(Style::default().fg(Color::Red)),
        );

    frame.render_widget(error, area);
}

/// Render the status bar
fn render_status_bar(frame: &mut Frame, app: &App, area: Rect) {
    let help_text = match &app.state {
        AppState::MainMenu => "↑↓: Navigate | Enter: Select | q: Quit",
        AppState::PromptInput => "Enter: Submit | Esc: Cancel",
        AppState::Loading => "Please wait...",
        AppState::ShowingResult { .. } => "↑↓: Navigate | Enter: Select | Esc: Back",
        AppState::ContextView => "Esc: Back | q: Quit",
        AppState::SettingsMenu => "↑↓: Navigate | Enter: Toggle | Esc: Back",
        AppState::RecentPrompts => "↑↓: Navigate | Enter: Select | Esc: Back",
        AppState::Error { .. } => "Enter/Esc: Continue",
    };

    // Split status bar into three sections
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(50),
            Constraint::Percentage(25),
        ])
        .split(area);

    // Left: Provider info
    let provider_text = Line::from(vec![
        Span::styled("AI: ", Style::default().fg(Color::DarkGray)),
        Span::styled(
            &app.current_provider,
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        ),
    ]);
    let provider = Paragraph::new(provider_text)
        .style(Style::default())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
    frame.render_widget(provider, chunks[0]);

    // Center: Help text
    let help = Paragraph::new(help_text)
        .style(Style::default().fg(Color::Gray))
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
    frame.render_widget(help, chunks[1]);

    // Right: Working directory (truncated)
    let cwd = std::env::current_dir()
        .map(|p| {
            let path = p.display().to_string();
            if path.len() > 20 {
                format!("…{}", &path[path.len() - 19..])
            } else {
                path
            }
        })
        .unwrap_or_else(|_| "?".to_string());

    let cwd_text = Line::from(vec![
        Span::styled("📁 ", Style::default()),
        Span::styled(cwd, Style::default().fg(Color::DarkGray)),
    ]);
    let cwd_widget = Paragraph::new(cwd_text)
        .alignment(Alignment::Right)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
    frame.render_widget(cwd_widget, chunks[2]);
}
