use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use std::time::Duration;

/// Event handling for the TUI
pub struct EventHandler {
    tick_rate: Duration,
}

impl EventHandler {
    pub fn new(tick_rate_ms: u64) -> Self {
        Self {
            tick_rate: Duration::from_millis(tick_rate_ms),
        }
    }

    /// Poll for the next event
    pub fn next(&self) -> Result<Option<AppEvent>> {
        if event::poll(self.tick_rate)? {
            if let Event::Key(key) = event::read()? {
                return Ok(Some(AppEvent::Key(key)));
            }
        }
        Ok(None)
    }
}

/// Application events
#[derive(Debug, Clone)]
pub enum AppEvent {
    Key(KeyEvent),
}

/// Key action types for menu navigation
#[derive(Debug, Clone, PartialEq)]
pub enum KeyAction {
    Up,
    Down,
    Select,
    Back,
    Quit,
    Char(char),
    Backspace,
    Delete,
    Home,
    End,
    Left,
    Right,
    None,
}

/// Convert a key event to a key action
pub fn key_to_action(key: KeyEvent) -> KeyAction {
    // Handle Ctrl+C for quit
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        return KeyAction::Quit;
    }

    match key.code {
        KeyCode::Up | KeyCode::Char('k') if key.modifiers.is_empty() => KeyAction::Up,
        KeyCode::Down | KeyCode::Char('j') if key.modifiers.is_empty() => KeyAction::Down,
        KeyCode::Enter => KeyAction::Select,
        KeyCode::Esc => KeyAction::Back,
        KeyCode::Char('q') if key.modifiers.is_empty() => KeyAction::Quit,
        KeyCode::Char(c) => KeyAction::Char(c),
        KeyCode::Backspace => KeyAction::Backspace,
        KeyCode::Delete => KeyAction::Delete,
        KeyCode::Home => KeyAction::Home,
        KeyCode::End => KeyAction::End,
        KeyCode::Left => KeyAction::Left,
        KeyCode::Right => KeyAction::Right,
        _ => KeyAction::None,
    }
}

/// Key action for input mode (more permissive)
pub fn key_to_input_action(key: KeyEvent) -> KeyAction {
    // Handle Ctrl+C for quit
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        return KeyAction::Quit;
    }

    match key.code {
        KeyCode::Enter => KeyAction::Select,
        KeyCode::Esc => KeyAction::Back,
        KeyCode::Char(c) => KeyAction::Char(c),
        KeyCode::Backspace => KeyAction::Backspace,
        KeyCode::Delete => KeyAction::Delete,
        KeyCode::Home => KeyAction::Home,
        KeyCode::End => KeyAction::End,
        KeyCode::Left => KeyAction::Left,
        KeyCode::Right => KeyAction::Right,
        KeyCode::Up => KeyAction::Up,
        KeyCode::Down => KeyAction::Down,
        _ => KeyAction::None,
    }
}
