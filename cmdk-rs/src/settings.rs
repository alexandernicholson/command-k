use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Get the command-k directory path
pub fn get_command_k_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("COMMAND_K_HISTORY_DIR") {
        PathBuf::from(dir)
    } else {
        dirs::home_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join(".command-k")
    }
}

/// Get the settings file path
pub fn get_settings_file() -> PathBuf {
    get_command_k_dir().join("settings.conf")
}

/// All available setting keys
#[allow(dead_code)]
pub const SETTING_KEYS: &[&str] = &[
    "send_terminal_content",
    "send_shell_history",
    "send_git_status",
    "send_working_dir",
    "send_env_var_names",
    "send_shell_type",
    "send_terminal_size",
    "send_current_process",
    "ai_provider",
    "custom_provider_cmd",
];

/// Privacy settings that can be toggled
pub const PRIVACY_SETTINGS: &[(&str, &str)] = &[
    ("send_terminal_content", "Terminal content"),
    ("send_shell_history", "Shell command history"),
    ("send_git_status", "Git repository status"),
    ("send_working_dir", "Working directory path"),
    ("send_env_var_names", "Environment variable names"),
    ("send_shell_type", "Shell type"),
    ("send_terminal_size", "Terminal dimensions"),
    ("send_current_process", "Current running process"),
];

/// Get default value for a setting
pub fn get_default_setting(key: &str) -> &'static str {
    match key {
        "send_terminal_content" => "true",
        "send_shell_history" => "true",
        "send_git_status" => "true",
        "send_working_dir" => "true",
        "send_env_var_names" => "true",
        "send_shell_type" => "true",
        "send_terminal_size" => "true",
        "send_current_process" => "true",
        "ai_provider" => "auto",
        "custom_provider_cmd" => "",
        _ => "true",
    }
}

/// Initialize settings file with defaults if it doesn't exist
pub fn init_settings() -> Result<()> {
    let settings_file = get_settings_file();
    
    if !settings_file.exists() {
        let dir = get_command_k_dir();
        fs::create_dir_all(&dir)
            .with_context(|| format!("Failed to create directory: {:?}", dir))?;
        
        let default_content = r#"# Command K Settings

# AI Provider: auto, claude, or codex
ai_provider=auto

# --- Privacy Settings ---
# Set to "true" or "false"

# Terminal content (last 500 lines of visible output)
send_terminal_content=true

# Shell command history
send_shell_history=true

# Git repository status
send_git_status=true

# Current working directory
send_working_dir=true

# Environment variable names (values are never sent)
send_env_var_names=true

# Shell type (bash, zsh, fish, etc.)
send_shell_type=true

# Terminal dimensions
send_terminal_size=true

# Current running process
send_current_process=true
"#;
        
        fs::write(&settings_file, default_content)
            .with_context(|| format!("Failed to write settings file: {:?}", settings_file))?;
    }
    
    Ok(())
}

/// Parse the settings file into a HashMap
fn parse_settings_file() -> Result<HashMap<String, String>> {
    let settings_file = get_settings_file();
    let mut settings = HashMap::new();
    
    if settings_file.exists() {
        let content = fs::read_to_string(&settings_file)
            .with_context(|| format!("Failed to read settings file: {:?}", settings_file))?;
        
        for line in content.lines() {
            let line = line.trim();
            // Skip comments and empty lines
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            
            if let Some((key, value)) = line.split_once('=') {
                settings.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
    }
    
    Ok(settings)
}

/// Get a setting value
pub fn get_setting(key: &str) -> Result<String> {
    init_settings()?;
    
    let settings = parse_settings_file()?;
    
    Ok(settings
        .get(key)
        .map(|s| s.to_string())
        .unwrap_or_else(|| get_default_setting(key).to_string()))
}

/// Set a setting value
pub fn set_setting(key: &str, value: &str) -> Result<()> {
    init_settings()?;
    
    let settings_file = get_settings_file();
    let content = if settings_file.exists() {
        fs::read_to_string(&settings_file)?
    } else {
        String::new()
    };
    
    let mut found = false;
    let mut new_lines: Vec<String> = Vec::new();
    
    for line in content.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('#') && !trimmed.is_empty() {
            if let Some((k, _)) = trimmed.split_once('=') {
                if k.trim() == key {
                    new_lines.push(format!("{}={}", key, value));
                    found = true;
                    continue;
                }
            }
        }
        new_lines.push(line.to_string());
    }
    
    if !found {
        new_lines.push(format!("{}={}", key, value));
    }
    
    fs::write(&settings_file, new_lines.join("\n") + "\n")
        .with_context(|| format!("Failed to write settings file: {:?}", settings_file))?;
    
    Ok(())
}

/// Toggle a boolean setting
pub fn toggle_setting(key: &str) -> Result<()> {
    let current = get_setting(key)?;
    let new_value = if current == "true" { "false" } else { "true" };
    set_setting(key, new_value)
}

/// Check if a setting is enabled (true)
pub fn is_enabled(key: &str) -> bool {
    get_setting(key).map(|v| v == "true").unwrap_or(true)
}

/// Get all settings as a HashMap
#[allow(dead_code)]
pub fn get_all_settings() -> Result<HashMap<String, String>> {
    init_settings()?;
    
    let mut settings = HashMap::new();
    for key in SETTING_KEYS {
        settings.insert(key.to_string(), get_setting(key)?);
    }
    
    Ok(settings)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_settings() {
        assert_eq!(get_default_setting("ai_provider"), "auto");
        assert_eq!(get_default_setting("send_git_status"), "true");
    }
}
