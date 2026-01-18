use anyhow::{Context, Result};
use md5::{Digest, Md5};
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use crate::settings;

/// Session timeout in seconds (1 hour)
const SESSION_TIMEOUT: u64 = 3600;

/// Get the session file path for the current directory
pub fn get_session_file() -> PathBuf {
    let dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let dir_str = dir.to_string_lossy();

    // Hash the directory path (first 8 chars of MD5)
    let mut hasher = Md5::new();
    hasher.update(dir_str.as_bytes());
    let result = hasher.finalize();
    let hash = format!("{:x}", result);
    let short_hash = &hash[..8];

    settings::get_command_k_dir().join(format!("cli-session-{}.md", short_hash))
}

/// Get the last result file path
pub fn get_result_file() -> PathBuf {
    settings::get_command_k_dir().join("last-result.txt")
}

/// Get the prompt history file path
pub fn get_history_file() -> PathBuf {
    settings::get_command_k_dir().join("prompt_history")
}

/// Check if session file is stale and remove it if so
pub fn cleanup_stale_session() -> Result<()> {
    let session_file = get_session_file();

    if session_file.exists() {
        let metadata = fs::metadata(&session_file)?;
        let modified = metadata.modified()?;
        let age = SystemTime::now()
            .duration_since(modified)
            .unwrap_or(Duration::ZERO);

        if age.as_secs() > SESSION_TIMEOUT {
            fs::remove_file(&session_file).ok();
        }
    }

    Ok(())
}

/// Get the conversation history from the session file
pub fn get_session_history() -> Result<Option<String>> {
    cleanup_stale_session()?;

    let session_file = get_session_file();

    if session_file.exists() {
        let content = fs::read_to_string(&session_file)
            .context("Failed to read session file")?;
        if content.trim().is_empty() {
            Ok(None)
        } else {
            Ok(Some(content))
        }
    } else {
        Ok(None)
    }
}

/// Get the number of turns in the current session
pub fn get_session_turn_count() -> usize {
    if let Ok(Some(history)) = get_session_history() {
        history.matches("## User:").count()
    } else {
        0
    }
}

/// Append a user message and response to the session history
pub fn append_to_session(user_message: &str, response: &str) -> Result<()> {
    let session_file = get_session_file();
    let dir = settings::get_command_k_dir();

    // Ensure directory exists
    fs::create_dir_all(&dir)?;

    // Append to session file
    let mut content = if session_file.exists() {
        fs::read_to_string(&session_file)?
    } else {
        String::new()
    };

    content.push_str(&format!("## User: {}\n\n", user_message));
    content.push_str("## Assistant:\n");
    content.push_str(response);
    content.push_str("\n\n");

    fs::write(&session_file, content)?;

    // Also save the last result
    save_last_result(response)?;

    Ok(())
}

/// Clear the current session
pub fn clear_session() -> Result<()> {
    let session_file = get_session_file();
    if session_file.exists() {
        fs::remove_file(&session_file)?;
    }
    Ok(())
}

/// Save the last result to a file
pub fn save_last_result(result: &str) -> Result<()> {
    let result_file = get_result_file();
    let dir = settings::get_command_k_dir();
    fs::create_dir_all(&dir)?;
    fs::write(&result_file, result)?;
    Ok(())
}

/// Get the last result
#[allow(dead_code)]
pub fn get_last_result() -> Result<Option<String>> {
    let result_file = get_result_file();
    if result_file.exists() {
        let content = fs::read_to_string(&result_file)?;
        if content.trim().is_empty() {
            Ok(None)
        } else {
            Ok(Some(content))
        }
    } else {
        Ok(None)
    }
}

/// Add a prompt to the history file
pub fn add_to_prompt_history(prompt: &str) -> Result<()> {
    let history_file = get_history_file();
    let dir = settings::get_command_k_dir();
    fs::create_dir_all(&dir)?;

    let mut content = if history_file.exists() {
        fs::read_to_string(&history_file)?
    } else {
        String::new()
    };

    content.push_str(prompt);
    content.push('\n');

    fs::write(&history_file, content)?;
    Ok(())
}

/// Get recent prompts from history (deduplicated, most recent first)
pub fn get_recent_prompts(limit: usize) -> Result<Vec<String>> {
    let history_file = get_history_file();

    if !history_file.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&history_file)?;
    let lines: Vec<&str> = content.lines().collect();

    // Reverse, deduplicate, and limit
    let mut seen = std::collections::HashSet::new();
    let prompts: Vec<String> = lines
        .iter()
        .rev()
        .filter(|line| {
            let trimmed = line.trim();
            if trimmed.is_empty() || seen.contains(trimmed) {
                false
            } else {
                seen.insert(trimmed.to_string());
                true
            }
        })
        .take(limit)
        .map(|s| s.to_string())
        .collect();

    Ok(prompts)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_file_hash() {
        // The hash should be deterministic
        let file1 = get_session_file();
        let file2 = get_session_file();
        assert_eq!(file1, file2);
    }
}
