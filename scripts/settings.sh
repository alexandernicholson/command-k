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
)

# Initialize settings file with defaults if it doesn't exist
init_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        cat > "$SETTINGS_FILE" << 'EOF'
# Command K Privacy Settings
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

# Export for use in other scripts
export -f init_settings get_setting set_setting toggle_setting get_all_settings 2>/dev/null || true
