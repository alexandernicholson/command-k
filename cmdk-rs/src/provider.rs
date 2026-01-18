use anyhow::{anyhow, Context, Result};
use std::io::Write;
use std::process::{Command, Stdio};

use crate::settings;

/// AI Provider types
#[derive(Debug, Clone, PartialEq)]
pub enum Provider {
    Claude,
    Codex,
    Custom(String),
    Mock,
}

impl std::fmt::Display for Provider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Provider::Claude => write!(f, "Claude"),
            Provider::Codex => write!(f, "Codex"),
            Provider::Custom(_) => write!(f, "Custom"),
            Provider::Mock => write!(f, "Mock (test)"),
        }
    }
}

/// Check if a command exists in PATH
fn command_exists(cmd: &str) -> bool {
    Command::new("which")
        .arg(cmd)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Get the current AI provider based on settings
pub fn get_current_provider() -> Result<Provider> {
    let provider_setting = settings::get_setting("ai_provider")?;

    match provider_setting.as_str() {
        "claude" => {
            if command_exists("claude") {
                Ok(Provider::Claude)
            } else {
                Err(anyhow!("claude not found in PATH"))
            }
        }
        "codex" => {
            if command_exists("codex") {
                Ok(Provider::Codex)
            } else {
                Err(anyhow!("codex not found in PATH"))
            }
        }
        "custom" => {
            let custom_cmd = settings::get_setting("custom_provider_cmd")?;
            if custom_cmd.is_empty() {
                Err(anyhow!("custom_provider_cmd not set"))
            } else {
                Ok(Provider::Custom(custom_cmd))
            }
        }
        "mock" => Ok(Provider::Mock),
        _ => {
            // Auto-detect: prefer Claude, fall back to Codex
            if command_exists("claude") {
                Ok(Provider::Claude)
            } else if command_exists("codex") {
                Ok(Provider::Codex)
            } else {
                Err(anyhow!("No AI CLI found (install claude or codex)"))
            }
        }
    }
}

/// Get display name of current provider
pub fn get_current_provider_name() -> String {
    match get_current_provider() {
        Ok(provider) => {
            let provider_setting = settings::get_setting("ai_provider").unwrap_or_default();
            if provider_setting == "auto" {
                format!("{} (auto)", provider)
            } else {
                provider.to_string()
            }
        }
        Err(_) => "None".to_string(),
    }
}

/// Run an AI query and return the response
pub fn run_query(prompt: &str) -> Result<String> {
    let provider = get_current_provider()?;

    match provider {
        Provider::Claude => run_claude_query(prompt),
        Provider::Codex => run_codex_query(prompt),
        Provider::Custom(cmd) => run_custom_query(prompt, &cmd),
        Provider::Mock => run_mock_query(prompt),
    }
}

/// Run a query using Claude CLI
fn run_claude_query(prompt: &str) -> Result<String> {
    let mut child = Command::new("claude")
        .arg("--print")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("Failed to spawn claude process")?;

    // Write prompt to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .context("Failed to write to claude stdin")?;
    }

    let output = child
        .wait_with_output()
        .context("Failed to wait for claude process")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("Claude error: {}", stderr));
    }

    let response = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(response)
}

/// Run a query using Codex CLI
fn run_codex_query(prompt: &str) -> Result<String> {
    // Codex needs special handling with a temp file for output
    let temp_dir = std::env::temp_dir();
    let output_file = temp_dir.join(format!("cmdk-codex-{}.txt", std::process::id()));

    let mut child = Command::new("codex")
        .args([
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "-o",
            output_file.to_str().unwrap(),
            "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Failed to spawn codex process")?;

    // Write prompt to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .context("Failed to write to codex stdin")?;
    }

    let status = child
        .wait()
        .context("Failed to wait for codex process")?;

    // Read output from temp file
    let response = if output_file.exists() {
        let content = std::fs::read_to_string(&output_file)
            .context("Failed to read codex output")?;
        std::fs::remove_file(&output_file).ok();
        content.trim().to_string()
    } else {
        return Err(anyhow!("Codex did not produce output"));
    };

    if !status.success() && response.is_empty() {
        return Err(anyhow!("Codex error"));
    }

    Ok(response)
}

/// Run a query using a custom command
fn run_custom_query(prompt: &str, cmd: &str) -> Result<String> {
    // Split command into program and args
    let parts: Vec<&str> = cmd.split_whitespace().collect();
    if parts.is_empty() {
        return Err(anyhow!("Empty custom command"));
    }

    let program = parts[0];
    let args = &parts[1..];

    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context(format!("Failed to spawn custom command: {}", cmd))?;

    // Write prompt to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .context("Failed to write to custom command stdin")?;
    }

    let output = child
        .wait_with_output()
        .context("Failed to wait for custom command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("Custom command error: {}", stderr));
    }

    let response = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(response)
}

/// Run a mock query for testing
fn run_mock_query(prompt: &str) -> Result<String> {
    // Simple mock that echoes a test response
    Ok(format!("echo 'Mock response for: {}'", prompt.lines().last().unwrap_or("empty")))
}

/// Build a full prompt with context and system instructions
pub fn build_full_prompt(user_query: &str, context: &str, history: Option<&str>) -> String {
    let mut prompt = String::new();

    prompt.push_str(
        r#"You are a terminal command assistant. Output ONLY the exact command to run.

CRITICAL RULES:
- Output ONLY the command itself - no shell prompts, no $, no explanation
- No markdown code blocks - just the raw command
- Single command only (use && or ; for multiple)
- If asked for explanation, then explain - otherwise just the command

"#,
    );

    prompt.push_str(context);

    if let Some(hist) = history {
        if !hist.is_empty() {
            prompt.push_str("\n## Previous Conversation:\n");
            prompt.push_str(hist);
        }
    }

    prompt.push_str(&format!("\n## User: {}\n", user_query));

    prompt
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_prompt() {
        let prompt = build_full_prompt("list files", "## Context\nShell: zsh", None);
        assert!(prompt.contains("list files"));
        assert!(prompt.contains("terminal command assistant"));
    }
}
