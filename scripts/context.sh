#!/usr/bin/env bash
# Gather context from current tmux pane
# Compatible with bash 4+ and zsh

PANE_ID="${1:-}"
CONTEXT_FILE="${2:-/tmp/command-k-context.txt}"

# Source settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/settings.sh"

# Initialize settings if needed
init_settings

# Helper to check if a setting is enabled
is_enabled() {
    [[ "$(get_setting "$1")" == "true" ]]
}

# Get pane info
PANE_PATH=$(tmux display-message -p -t "$PANE_ID" '#{pane_current_path}' 2>/dev/null)
PANE_CMD=$(tmux display-message -p -t "$PANE_ID" '#{pane_current_command}' 2>/dev/null)
PANE_WIDTH=$(tmux display-message -p -t "$PANE_ID" '#{pane_width}' 2>/dev/null)
PANE_HEIGHT=$(tmux display-message -p -t "$PANE_ID" '#{pane_height}' 2>/dev/null)

# Get current shell
CURRENT_SHELL=$(basename "$SHELL" 2>/dev/null || echo "unknown")

# Get environment variable names (without values for privacy)
ENV_VAR_NAMES=$(env | cut -d= -f1 | sort | tr '\n' ' ')

# Capture pane content (visible + scrollback, last 500 lines)
PANE_CONTENT=""
if is_enabled "send_terminal_content"; then
    PANE_CONTENT=$(tmux capture-pane -t "$PANE_ID" -p -S -500 2>/dev/null | tail -500)
fi

# Get current command line if at shell prompt
CMDLINE=""
if [[ "$PANE_CMD" =~ ^(bash|zsh|fish|sh)$ ]]; then
    CMDLINE=$(echo "$PANE_CONTENT" | tail -1)
fi

# Detect context type
CONTEXT_TYPE="shell"
case "$PANE_CMD" in
    vim|nvim|vi) CONTEXT_TYPE="editor" ;;
    python|python3|ipython) CONTEXT_TYPE="python-repl" ;;
    node) CONTEXT_TYPE="node-repl" ;;
    psql|mysql|sqlite3) CONTEXT_TYPE="sql-repl" ;;
    ssh|mosh) CONTEXT_TYPE="remote-shell" ;;
    *) 
        if [[ "$PANE_CMD" =~ ^(bash|zsh|fish|sh)$ ]]; then
            CONTEXT_TYPE="shell"
        else
            CONTEXT_TYPE="unknown"
        fi
        ;;
esac

# Get recent shell history if available
SHELL_HISTORY=""
if is_enabled "send_shell_history"; then
    USER_SHELL=$(basename "$SHELL" 2>/dev/null)
    
    if [[ "$USER_SHELL" == "zsh" ]] && [[ -f ~/.zsh_history ]]; then
        SHELL_HISTORY=$(tail -30 ~/.zsh_history 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | tail -20)
    elif [[ "$USER_SHELL" == "zsh" ]] && [[ -f ~/.histfile ]]; then
        SHELL_HISTORY=$(tail -30 ~/.histfile 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | tail -20)
    elif [[ -f ~/.bash_history ]]; then
        SHELL_HISTORY=$(tail -20 ~/.bash_history 2>/dev/null)
    elif [[ -f ~/.zsh_history ]]; then
        SHELL_HISTORY=$(tail -30 ~/.zsh_history 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | tail -20)
    fi
fi

# Get git info if in a repo
GIT_INFO=""
if is_enabled "send_git_status"; then
    if [[ -d "$PANE_PATH/.git" ]] || git -C "$PANE_PATH" rev-parse --git-dir &>/dev/null 2>&1; then
        GIT_BRANCH=$(git -C "$PANE_PATH" branch --show-current 2>/dev/null)
        GIT_STATUS=$(git -C "$PANE_PATH" status --short 2>/dev/null | head -10)
        GIT_INFO="Branch: $GIT_BRANCH
Modified files:
$GIT_STATUS"
    fi
fi

# Build context document
{
    echo "## Terminal Context"
    echo ""
    
    if is_enabled "send_shell_type"; then
        echo "**Shell:** $CURRENT_SHELL"
    fi
    
    if is_enabled "send_working_dir"; then
        echo "**Working Directory:** $PANE_PATH"
    fi
    
    if is_enabled "send_current_process"; then
        echo "**Current Process:** $PANE_CMD"
        echo "**Context Type:** $CONTEXT_TYPE"
    fi
    
    if is_enabled "send_terminal_size"; then
        echo "**Terminal Size:** ${PANE_WIDTH}x${PANE_HEIGHT}"
    fi
    
    if is_enabled "send_env_var_names"; then
        echo ""
        echo "### Environment Variables (names only)"
        echo "\`\`\`"
        echo "$ENV_VAR_NAMES"
        echo "\`\`\`"
    fi
    
    if is_enabled "send_git_status" && [[ -n "$GIT_INFO" ]]; then
        echo ""
        echo "### Git Status"
        echo "$GIT_INFO"
    fi
    
    if is_enabled "send_shell_history" && [[ -n "$SHELL_HISTORY" ]]; then
        echo ""
        echo "### Recent Shell History"
        echo "\`\`\`"
        echo "$SHELL_HISTORY"
        echo "\`\`\`"
    fi
    
    if is_enabled "send_terminal_content" && [[ -n "$PANE_CONTENT" ]]; then
        echo ""
        echo "### Current Terminal Content (last 500 lines)"
        echo "\`\`\`"
        echo "$PANE_CONTENT"
        echo "\`\`\`"
    fi
    
    if [[ -n "$CMDLINE" ]]; then
        echo ""
        echo "### Current Command Line"
        echo "\`\`\`"
        echo "$CMDLINE"
        echo "\`\`\`"
    fi
} > "$CONTEXT_FILE"

echo "$CONTEXT_FILE"
