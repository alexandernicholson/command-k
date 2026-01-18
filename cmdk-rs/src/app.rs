use anyhow::Result;
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io::{self, Stdout};
use std::process::Command;
use std::sync::mpsc;
use std::thread;

use crate::context;
use crate::events::{key_to_action, key_to_input_action, AppEvent, EventHandler, KeyAction};
use crate::provider;
use crate::session;
use crate::settings;
use crate::ui;

/// Application state
#[derive(Debug, Clone)]
pub enum AppState {
    MainMenu,
    PromptInput,
    Loading,
    ShowingResult { response: String },
    ContextView,
    SettingsMenu,
    RecentPrompts,
    Error { message: String },
}

/// Main menu items
#[derive(Debug, Clone, PartialEq)]
pub enum MenuItem {
    AskQuestion,
    RecentPrompts,
    ViewContext,
    PrivacySettings,
    ClearConversation,
    Exit,
}

/// Result action items
#[derive(Debug, Clone, PartialEq)]
pub enum ResultAction {
    RunCommand,
    CopyToClipboard,
    AskFollowUp,
    BackToMenu,
}

/// Settings menu items
#[derive(Debug, Clone)]
pub enum SettingsMenuItem {
    ChangeProvider,
    Separator,
    Toggle {
        key: String,
        label: String,
        enabled: bool,
    },
    Separator2,
    EnableAll,
    DisableAll,
    Back,
}

/// Main application struct
pub struct App {
    pub state: AppState,
    pub running: bool,

    // Menu state
    pub menu_items: Vec<MenuItem>,
    pub selected_index: usize,

    // Input state
    pub input: String,
    pub cursor_position: usize,

    // Result state
    pub result_actions: Vec<ResultAction>,
    pub result_selected: usize,
    pub last_response: Option<String>,

    // Settings state
    pub settings_items: Vec<SettingsMenuItem>,
    pub settings_selected: usize,
    pub current_provider: String,

    // Recent prompts state
    pub recent_prompts: Vec<String>,
    pub prompts_selected: usize,

    // Context display
    pub context_display: String,

    // Session info
    pub session_turns: usize,

    // Spinner animation frame
    pub spinner_frame: usize,

    // Pending query for async execution
    pub pending_query: Option<String>,
    pub query_receiver: Option<mpsc::Receiver<Result<String, String>>>,
}

impl App {
    pub fn new() -> Result<Self> {
        let session_turns = session::get_session_turn_count();

        Ok(Self {
            state: AppState::MainMenu,
            running: true,
            menu_items: vec![
                MenuItem::AskQuestion,
                MenuItem::RecentPrompts,
                MenuItem::ViewContext,
                MenuItem::PrivacySettings,
                MenuItem::ClearConversation,
                MenuItem::Exit,
            ],
            selected_index: 0,
            input: String::new(),
            cursor_position: 0,
            result_actions: vec![
                ResultAction::RunCommand,
                ResultAction::CopyToClipboard,
                ResultAction::AskFollowUp,
                ResultAction::BackToMenu,
            ],
            result_selected: 0,
            last_response: None,
            settings_items: Vec::new(),
            settings_selected: 0,
            current_provider: provider::get_current_provider_name(),
            recent_prompts: Vec::new(),
            prompts_selected: 0,
            context_display: String::new(),
            session_turns,
            spinner_frame: 0,
            pending_query: None,
            query_receiver: None,
        })
    }

    /// Advance the spinner animation
    pub fn tick_spinner(&mut self) {
        self.spinner_frame = (self.spinner_frame + 1) % 10;
    }

    /// Start an async query
    pub fn start_query(&mut self, query: &str) -> Result<()> {
        // Save to prompt history
        session::add_to_prompt_history(query)?;

        // Get context
        let ctx = context::gather_context()?;

        // Get session history
        let history = session::get_session_history()?;

        // Build full prompt
        let full_prompt = provider::build_full_prompt(query, &ctx, history.as_deref());

        // Store the query for session saving later
        self.pending_query = Some(query.to_string());

        // Create channel for result
        let (tx, rx) = mpsc::channel();
        self.query_receiver = Some(rx);

        // Run query in background thread
        thread::spawn(move || {
            let result = provider::run_query(&full_prompt);
            let _ = tx.send(result.map_err(|e| e.to_string()));
        });

        // Set loading state
        self.state = AppState::Loading;

        Ok(())
    }

    /// Check if query is complete and handle result
    pub fn check_query_complete(&mut self) -> Result<bool> {
        if let Some(ref rx) = self.query_receiver {
            match rx.try_recv() {
                Ok(result) => {
                    let query = self.pending_query.take().unwrap_or_default();
                    self.query_receiver = None;

                    match result {
                        Ok(response) => {
                            // Save to session
                            session::append_to_session(&query, &response)?;
                            self.session_turns = session::get_session_turn_count();

                            self.last_response = Some(response.clone());
                            self.result_selected = 0;
                            self.state = AppState::ShowingResult { response };
                        }
                        Err(e) => {
                            self.state = AppState::Error { message: e };
                        }
                    }
                    Ok(true)
                }
                Err(mpsc::TryRecvError::Empty) => Ok(false),
                Err(mpsc::TryRecvError::Disconnected) => {
                    self.query_receiver = None;
                    self.pending_query = None;
                    self.state = AppState::Error {
                        message: "Query thread disconnected".to_string(),
                    };
                    Ok(true)
                }
            }
        } else {
            Ok(false)
        }
    }

    /// Refresh settings menu items
    fn refresh_settings_items(&mut self) {
        self.current_provider = provider::get_current_provider_name();

        let mut items = vec![SettingsMenuItem::ChangeProvider, SettingsMenuItem::Separator];

        for (key, label) in settings::PRIVACY_SETTINGS {
            let enabled = settings::is_enabled(key);
            items.push(SettingsMenuItem::Toggle {
                key: key.to_string(),
                label: label.to_string(),
                enabled,
            });
        }

        items.push(SettingsMenuItem::Separator2);
        items.push(SettingsMenuItem::EnableAll);
        items.push(SettingsMenuItem::DisableAll);
        items.push(SettingsMenuItem::Back);

        self.settings_items = items;
    }

    /// Handle key events based on current state
    pub fn handle_key(&mut self, event: AppEvent) -> Result<()> {
        let AppEvent::Key(key) = event;
        match &self.state {
                AppState::MainMenu => self.handle_main_menu_key(key_to_action(key))?,
                AppState::PromptInput => self.handle_input_key(key_to_input_action(key))?,
                AppState::Loading => {} // Ignore input during loading
                AppState::ShowingResult { .. } => self.handle_result_key(key_to_action(key))?,
                AppState::ContextView => self.handle_context_key(key_to_action(key))?,
                AppState::SettingsMenu => self.handle_settings_key(key_to_action(key))?,
                AppState::RecentPrompts => self.handle_prompts_key(key_to_action(key))?,
            AppState::Error { .. } => self.handle_error_key(key_to_action(key))?,
        }
        Ok(())
    }

    fn handle_main_menu_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Up => {
                if self.selected_index > 0 {
                    self.selected_index -= 1;
                }
            }
            KeyAction::Down => {
                if self.selected_index < self.menu_items.len() - 1 {
                    self.selected_index += 1;
                }
            }
            KeyAction::Select => {
                let item = &self.menu_items[self.selected_index];
                match item {
                    MenuItem::AskQuestion => {
                        self.input.clear();
                        self.cursor_position = 0;
                        self.state = AppState::PromptInput;
                    }
                    MenuItem::RecentPrompts => {
                        self.recent_prompts = session::get_recent_prompts(20)?;
                        self.prompts_selected = 0;
                        self.state = AppState::RecentPrompts;
                    }
                    MenuItem::ViewContext => {
                        self.context_display = context::gather_context_display()?;
                        self.state = AppState::ContextView;
                    }
                    MenuItem::PrivacySettings => {
                        self.refresh_settings_items();
                        self.settings_selected = 0;
                        self.state = AppState::SettingsMenu;
                    }
                    MenuItem::ClearConversation => {
                        session::clear_session()?;
                        self.session_turns = 0;
                    }
                    MenuItem::Exit => {
                        self.running = false;
                    }
                }
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_input_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Char(c) => {
                self.input.insert(self.cursor_position, c);
                self.cursor_position += 1;
            }
            KeyAction::Backspace => {
                if self.cursor_position > 0 {
                    self.cursor_position -= 1;
                    self.input.remove(self.cursor_position);
                }
            }
            KeyAction::Delete => {
                if self.cursor_position < self.input.len() {
                    self.input.remove(self.cursor_position);
                }
            }
            KeyAction::Left => {
                if self.cursor_position > 0 {
                    self.cursor_position -= 1;
                }
            }
            KeyAction::Right => {
                if self.cursor_position < self.input.len() {
                    self.cursor_position += 1;
                }
            }
            KeyAction::Home => {
                self.cursor_position = 0;
            }
            KeyAction::End => {
                self.cursor_position = self.input.len();
            }
            KeyAction::Select => {
                if !self.input.trim().is_empty() {
                    let query = self.input.clone();
                    self.submit_query(&query)?;
                }
            }
            KeyAction::Back => {
                self.state = AppState::MainMenu;
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_result_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Up => {
                if self.result_selected > 0 {
                    self.result_selected -= 1;
                }
            }
            KeyAction::Down => {
                if self.result_selected < self.result_actions.len() - 1 {
                    self.result_selected += 1;
                }
            }
            KeyAction::Select => {
                let action = &self.result_actions[self.result_selected].clone();
                self.handle_result_action(action)?;
            }
            KeyAction::Back => {
                self.state = AppState::MainMenu;
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_result_action(&mut self, action: &ResultAction) -> Result<()> {
        match action {
            ResultAction::RunCommand => {
                if self.last_response.is_some() {
                    // We need to exit the TUI to run the command
                    self.running = false;
                }
            }
            ResultAction::CopyToClipboard => {
                if let Some(ref response) = self.last_response {
                    if let Ok(mut clipboard) = arboard::Clipboard::new() {
                        clipboard.set_text(response.clone()).ok();
                    }
                }
                self.state = AppState::MainMenu;
            }
            ResultAction::AskFollowUp => {
                self.input.clear();
                self.cursor_position = 0;
                self.state = AppState::PromptInput;
            }
            ResultAction::BackToMenu => {
                self.state = AppState::MainMenu;
            }
        }
        Ok(())
    }

    fn handle_context_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Back | KeyAction::Select => {
                self.state = AppState::MainMenu;
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_settings_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Up => {
                if self.settings_selected > 0 {
                    self.settings_selected -= 1;
                    // Skip separators
                    while self.settings_selected > 0 {
                        if let SettingsMenuItem::Separator | SettingsMenuItem::Separator2 =
                            self.settings_items[self.settings_selected]
                        {
                            self.settings_selected -= 1;
                        } else {
                            break;
                        }
                    }
                }
            }
            KeyAction::Down => {
                if self.settings_selected < self.settings_items.len() - 1 {
                    self.settings_selected += 1;
                    // Skip separators
                    while self.settings_selected < self.settings_items.len() - 1 {
                        if let SettingsMenuItem::Separator | SettingsMenuItem::Separator2 =
                            self.settings_items[self.settings_selected]
                        {
                            self.settings_selected += 1;
                        } else {
                            break;
                        }
                    }
                }
            }
            KeyAction::Select => {
                let item = self.settings_items[self.settings_selected].clone();
                match item {
                    SettingsMenuItem::ChangeProvider => {
                        // Cycle through providers: auto -> claude -> codex -> auto
                        let current = settings::get_setting("ai_provider")?;
                        let next = match current.as_str() {
                            "auto" => "claude",
                            "claude" => "codex",
                            "codex" => "auto",
                            _ => "auto",
                        };
                        settings::set_setting("ai_provider", next)?;
                        self.refresh_settings_items();
                    }
                    SettingsMenuItem::Toggle { key, .. } => {
                        settings::toggle_setting(&key)?;
                        self.refresh_settings_items();
                    }
                    SettingsMenuItem::EnableAll => {
                        for (key, _) in settings::PRIVACY_SETTINGS {
                            settings::set_setting(key, "true")?;
                        }
                        self.refresh_settings_items();
                    }
                    SettingsMenuItem::DisableAll => {
                        for (key, _) in settings::PRIVACY_SETTINGS {
                            settings::set_setting(key, "false")?;
                        }
                        self.refresh_settings_items();
                    }
                    SettingsMenuItem::Back => {
                        self.state = AppState::MainMenu;
                    }
                    _ => {}
                }
            }
            KeyAction::Back => {
                self.state = AppState::MainMenu;
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_prompts_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Up => {
                if self.prompts_selected > 0 {
                    self.prompts_selected -= 1;
                }
            }
            KeyAction::Down => {
                if self.prompts_selected < self.recent_prompts.len().saturating_sub(1) {
                    self.prompts_selected += 1;
                }
            }
            KeyAction::Select => {
                if !self.recent_prompts.is_empty() {
                    let query = self.recent_prompts[self.prompts_selected].clone();
                    self.submit_query(&query)?;
                }
            }
            KeyAction::Back => {
                self.state = AppState::MainMenu;
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    fn handle_error_key(&mut self, action: KeyAction) -> Result<()> {
        match action {
            KeyAction::Select | KeyAction::Back => {
                self.state = AppState::MainMenu;
            }
            KeyAction::Quit => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    /// Submit a query to the AI (starts async query)
    fn submit_query(&mut self, query: &str) -> Result<()> {
        self.start_query(query)
    }

    /// Check if we should run a command on exit
    pub fn should_run_command(&self) -> bool {
        if let AppState::ShowingResult { .. } = &self.state {
            self.result_actions.get(self.result_selected) == Some(&ResultAction::RunCommand)
        } else {
            false
        }
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

/// Run the interactive TUI mode
pub fn run_interactive_mode() -> Result<()> {
    let mut terminal = setup_terminal()?;
    let mut app = App::new()?;
    let event_handler = EventHandler::new(100);

    // Clean up stale sessions
    session::cleanup_stale_session()?;

    while app.running {
        // Check if async query is complete
        if matches!(app.state, AppState::Loading) {
            app.check_query_complete()?;
            app.tick_spinner();
        }

        // Draw UI
        terminal.draw(|f| ui::render(f, &app))?;

        // Handle events (but not during loading - just animate)
        if let Some(event) = event_handler.next()? {
            if !matches!(app.state, AppState::Loading) {
                app.handle_key(event)?;
            }
        }
    }

    // Check if we need to run a command
    let should_run = app.should_run_command();
    let command_to_run = if should_run {
        app.last_response.clone()
    } else {
        None
    };

    // Restore terminal
    restore_terminal(&mut terminal)?;

    // Run command if requested (after exiting TUI)
    if let Some(cmd) = command_to_run {
        println!("\x1b[1;33m▶ Running:\x1b[0m {}", cmd);
        println!();
        let status = Command::new("sh").arg("-c").arg(&cmd).status();
        match status {
            Ok(s) => {
                println!();
                if s.success() {
                    println!("\x1b[1;32m✓ Command completed successfully\x1b[0m");
                } else {
                    println!(
                        "\x1b[1;31m✗ Command exited with code {}\x1b[0m",
                        s.code().unwrap_or(-1)
                    );
                }
            }
            Err(e) => {
                eprintln!("\x1b[1;31m✗ Failed to run command: {}\x1b[0m", e);
            }
        }
    }

    Ok(())
}

/// Run settings mode (opens settings directly)
pub fn run_settings_mode() -> Result<()> {
    let mut terminal = setup_terminal()?;
    let mut app = App::new()?;
    app.refresh_settings_items();
    app.state = AppState::SettingsMenu;

    let event_handler = EventHandler::new(100);

    while app.running {
        terminal.draw(|f| ui::render(f, &app))?;

        if let Some(event) = event_handler.next()? {
            app.handle_key(event)?;
        }

        // Exit settings mode when going back to main menu
        if let AppState::MainMenu = app.state {
            break;
        }
    }

    restore_terminal(&mut terminal)?;
    Ok(())
}

/// Run direct query mode (non-interactive)
pub fn run_query_mode(query: &str) -> Result<()> {
    // Get context
    let ctx = context::gather_context()?;

    // Build prompt
    let full_prompt = provider::build_full_prompt(query, &ctx, None);

    // Run query
    let response = provider::run_query(&full_prompt)?;

    // Print response
    println!("{}", response);

    Ok(())
}
