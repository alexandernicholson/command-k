#!/usr/bin/env bash
# Settings management for Command K
# Compatible with bash 4+ and zsh

SETTINGS_FILE="${COMMAND_K_HISTORY_DIR:-$HOME/.command-k}/settings.conf"

# Default settings (all enabled)
declare -A DEFAULT_SETTINGS=(
    [send_terminal_content]="true"
    [send_shell_history]="true"
    [send_git_status]="true"
    [send_working_dir]="true"
    [send_env_var_names]="true"
    [send_shell_type]="true"
    [send_terminal_size]="true"
    [send_current_process]="true"
    [ai_provider]="auto"
    [custom_provider_cmd]=""
)

# Initialize settings file with defaults if it doesn't exist
init_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        cat > "$SETTINGS_FILE" << 'EOF'
# Command K Settings

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
EOF
    fi
}

# Read a setting value
get_setting() {
    local key="$1"
    local default="${DEFAULT_SETTINGS[$key]:-true}"
    
    init_settings
    
    # Check if setting exists in file
    if grep -q "^${key}=" "$SETTINGS_FILE" 2>/dev/null; then
        # Return value (may be empty)
        grep "^${key}=" "$SETTINGS_FILE" 2>/dev/null | cut -d= -f2 | tr -d ' '
    else
        echo "$default"
    fi
}

# Set a setting value
set_setting() {
    local key="$1"
    local value="$2"
    
    init_settings
    
    if grep -q "^${key}=" "$SETTINGS_FILE" 2>/dev/null; then
        # Update existing setting (use | as delimiter to handle paths with /)
        sed -i "s|^${key}=.*|${key}=${value}|" "$SETTINGS_FILE"
    else
        # Add new setting
        echo "${key}=${value}" >> "$SETTINGS_FILE"
    fi
}

# Toggle a setting
toggle_setting() {
    local key="$1"
    local current=$(get_setting "$key")
    
    if [[ "$current" == "true" ]]; then
        set_setting "$key" "false"
    else
        set_setting "$key" "true"
    fi
}

# Get all settings as associative array output
get_all_settings() {
    init_settings
    
    for key in "${!DEFAULT_SETTINGS[@]}"; do
        echo "$key=$(get_setting "$key")"
    done
}

# Get the AI command to use
# Returns: command string to pipe input to
# For codex, returns "CODEX" marker - use run_ai_query function
# For custom, returns the user-specified command
get_ai_command() {
    local provider=$(get_setting "ai_provider")
    
    case "$provider" in
        claude)
            if command -v claude &>/dev/null; then
                echo "claude --print"
            else
                echo "ERROR: claude not found" >&2
                return 1
            fi
            ;;
        codex)
            if command -v codex &>/dev/null; then
                echo "CODEX"  # Special marker - use run_ai_query
            else
                echo "ERROR: codex not found" >&2
                return 1
            fi
            ;;
        custom)
            # User-provided custom command
            local custom_cmd=$(get_setting "custom_provider_cmd")
            if [[ -n "$custom_cmd" ]]; then
                echo "$custom_cmd"
            else
                echo "ERROR: custom_provider_cmd not set" >&2
                return 1
            fi
            ;;
        mock)
            # Internal testing provider - not shown in UI
            local script_dir="${BASH_SOURCE[0]%/*}"
            local mock_cli="$script_dir/../tests/mock-ai"
            if [[ -x "$mock_cli" ]]; then
                echo "$mock_cli"
            else
                echo "ERROR: mock-ai not found" >&2
                return 1
            fi
            ;;
        auto|*)
            if command -v claude &>/dev/null; then
                echo "claude --print"
            elif command -v codex &>/dev/null; then
                echo "CODEX"  # Special marker - use run_ai_query
            else
                echo "ERROR: No AI CLI found (install claude or codex)" >&2
                return 1
            fi
            ;;
    esac
}

# Run AI query - handles both claude and codex
# Usage: echo "prompt" | run_ai_query
run_ai_query() {
    local ai_cmd=$(get_ai_command)
    if [[ $? -ne 0 ]]; then
        echo "$ai_cmd" >&2
        return 1
    fi
    
    if [[ "$ai_cmd" == "CODEX" ]]; then
        # Codex needs special handling:
        # - --sandbox read-only prevents command execution
        # - -o file captures only final message
        # - redirect stdout/stderr to hide agent output
        local tmpfile=$(mktemp)
        cat | codex exec --skip-git-repo-check --sandbox read-only -o "$tmpfile" - >/dev/null 2>&1
        local exit_code=$?
        cat "$tmpfile"
        rm -f "$tmpfile"
        return $exit_code
    else
        # Claude and others: simple pipe
        cat | $ai_cmd
    fi
}

# List available AI providers
list_ai_providers() {
    local available=()
    command -v claude &>/dev/null && available+=("claude")
    command -v codex &>/dev/null && available+=("codex")
    echo "${available[*]}"
}

# Get the display name of current provider
get_current_provider_name() {
    local provider=$(get_setting "ai_provider")
    
    case "$provider" in
        claude) echo "Claude" ;;
        codex) echo "Codex" ;;
        custom) echo "Custom" ;;
        mock) echo "Mock (test)" ;;
        auto|*)
            if command -v claude &>/dev/null; then
                echo "Claude (auto)"
            elif command -v codex &>/dev/null; then
                echo "Codex (auto)"
            else
                echo "None"
            fi
            ;;
    esac
}

# Export for use in other scripts
export -f init_settings get_setting set_setting toggle_setting get_all_settings get_ai_command run_ai_query list_ai_providers get_current_provider_name 2>/dev/null || true
