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
    
    local value=$(grep "^${key}=" "$SETTINGS_FILE" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    
    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Set a setting value
set_setting() {
    local key="$1"
    local value="$2"
    
    init_settings
    
    if grep -q "^${key}=" "$SETTINGS_FILE" 2>/dev/null; then
        # Update existing setting
        sed -i "s/^${key}=.*/${key}=${value}/" "$SETTINGS_FILE"
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
                echo "codex --print"
            else
                echo "ERROR: codex not found" >&2
                return 1
            fi
            ;;
        auto|*)
            # Auto-detect: prefer claude, fall back to codex
            if command -v claude &>/dev/null; then
                echo "claude --print"
            elif command -v codex &>/dev/null; then
                echo "codex --print"
            else
                echo "ERROR: No AI CLI found (install claude or codex)" >&2
                return 1
            fi
            ;;
    esac
}

# List available AI providers
list_ai_providers() {
    local available=()
    command -v claude &>/dev/null && available+=("claude")
    command -v codex &>/dev/null && available+=("codex")
    echo "${available[*]}"
}

# Export for use in other scripts
export -f init_settings get_setting set_setting toggle_setting get_all_settings get_ai_command list_ai_providers 2>/dev/null || true
