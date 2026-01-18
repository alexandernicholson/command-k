use anyhow::Result;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

use crate::settings;

/// Gather terminal context based on privacy settings
pub fn gather_context() -> Result<String> {
    settings::init_settings()?;

    let mut context = String::new();
    context.push_str("## Terminal Context\n\n");

    // Shell type
    if settings::is_enabled("send_shell_type") {
        if let Ok(shell) = env::var("SHELL") {
            let shell_name = PathBuf::from(&shell)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| shell.clone());
            context.push_str(&format!("**Shell:** {}\n", shell_name));
        }
    }

    // Working directory
    if settings::is_enabled("send_working_dir") {
        if let Ok(cwd) = env::current_dir() {
            context.push_str(&format!("**Working Directory:** {}\n", cwd.display()));
        }
    }

    // Terminal size
    if settings::is_enabled("send_terminal_size") {
        if let Ok((cols, rows)) = crossterm::terminal::size() {
            context.push_str(&format!("**Terminal Size:** {}x{}\n", cols, rows));
        }
    }

    // Environment variable names (not values)
    if settings::is_enabled("send_env_var_names") {
        let mut env_names: Vec<String> = env::vars().map(|(k, _)| k).collect();
        env_names.sort();
        context.push_str("\n### Environment Variables (names only)\n```\n");
        context.push_str(&env_names.join(" "));
        context.push_str("\n```\n");
    }

    // Git status
    if settings::is_enabled("send_git_status") {
        if let Some(git_info) = get_git_status() {
            context.push_str("\n### Git Status\n");
            context.push_str(&git_info);
        }
    }

    // Shell history
    if settings::is_enabled("send_shell_history") {
        if let Some(history) = get_shell_history() {
            context.push_str("\n### Recent Shell History\n```\n");
            context.push_str(&history);
            context.push_str("\n```\n");
        }
    }

    Ok(context)
}

/// Get git status if in a git repository
fn get_git_status() -> Option<String> {
    // Check if we're in a git repo
    let git_dir = Command::new("git")
        .args(["rev-parse", "--git-dir"])
        .output()
        .ok()?;

    if !git_dir.status.success() {
        return None;
    }

    let mut result = String::new();

    // Get current branch
    if let Ok(output) = Command::new("git")
        .args(["branch", "--show-current"])
        .output()
    {
        if output.status.success() {
            let branch = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !branch.is_empty() {
                result.push_str(&format!("Branch: {}\n", branch));
            }
        }
    }

    // Get modified files (short status)
    if let Ok(output) = Command::new("git").args(["status", "--short"]).output() {
        if output.status.success() {
            let status = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = status.lines().take(10).collect();
            if !lines.is_empty() {
                result.push_str("Modified files:\n");
                for line in lines {
                    result.push_str(line);
                    result.push('\n');
                }
            }
        }
    }

    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

/// Get recent shell history
fn get_shell_history() -> Option<String> {
    let home = dirs::home_dir()?;

    // Try zsh history first, then bash
    let history_files = [
        home.join(".zsh_history"),
        home.join(".bash_history"),
    ];

    for history_file in &history_files {
        if history_file.exists() {
            if let Ok(content) = fs::read_to_string(history_file) {
                let lines: Vec<&str> = content.lines().collect();
                let recent: Vec<String> = lines
                    .iter()
                    .rev()
                    .take(20)
                    .rev()
                    .map(|line| {
                        // Handle zsh history format (: timestamp:0;command)
                        if line.starts_with(": ") {
                            line.split_once(';')
                                .map(|(_, cmd)| cmd.to_string())
                                .unwrap_or_else(|| line.to_string())
                        } else {
                            line.to_string()
                        }
                    })
                    .collect();

                if !recent.is_empty() {
                    return Some(recent.join("\n"));
                }
            }
        }
    }

    None
}

/// Get a formatted context string for display (without markdown)
pub fn gather_context_display() -> Result<String> {
    settings::init_settings()?;

    let mut lines = Vec::new();

    // Shell type
    if settings::is_enabled("send_shell_type") {
        if let Ok(shell) = env::var("SHELL") {
            let shell_name = PathBuf::from(&shell)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| shell.clone());
            lines.push(format!("Shell: {}", shell_name));
        }
    }

    // Working directory
    if settings::is_enabled("send_working_dir") {
        if let Ok(cwd) = env::current_dir() {
            lines.push(format!("Working Directory: {}", cwd.display()));
        }
    }

    // Terminal size
    if settings::is_enabled("send_terminal_size") {
        if let Ok((cols, rows)) = crossterm::terminal::size() {
            lines.push(format!("Terminal Size: {}x{}", cols, rows));
        }
    }

    // Git status
    if settings::is_enabled("send_git_status") {
        if let Some(git_info) = get_git_status() {
            lines.push(String::new());
            lines.push("Git Status:".to_string());
            for line in git_info.lines() {
                lines.push(format!("  {}", line));
            }
        }
    }

    // Environment variable count
    if settings::is_enabled("send_env_var_names") {
        let count = env::vars().count();
        lines.push(format!("Environment Variables: {} names", count));
    }

    // Shell history
    if settings::is_enabled("send_shell_history") && get_shell_history().is_some() {
        lines.push("Shell History: last 20 commands".to_string());
    }

    Ok(lines.join("\n"))
}
