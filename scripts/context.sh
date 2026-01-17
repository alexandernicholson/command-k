#!/usr/bin/env bash
# Gather context from current tmux pane
# Compatible with bash 4+ and zsh

PANE_ID="${1:-}"
CONTEXT_FILE="${2:-/tmp/command-k-context.txt}"

# Get pane info
PANE_PATH=$(tmux display-message -p -t "$PANE_ID" '#{pane_current_path}' 2>/dev/null)
PANE_CMD=$(tmux display-message -p -t "$PANE_ID" '#{pane_current_command}' 2>/dev/null)
PANE_WIDTH=$(tmux display-message -p -t "$PANE_ID" '#{pane_width}' 2>/dev/null)
PANE_HEIGHT=$(tmux display-message -p -t "$PANE_ID" '#{pane_height}' 2>/dev/null)

# Capture pane content (visible + scrollback, last 500 lines)
PANE_CONTENT=$(tmux capture-pane -t "$PANE_ID" -p -S -500 2>/dev/null | tail -500)

# Get current command line if at shell prompt
CMDLINE=""
if [[ "$PANE_CMD" =~ ^(bash|zsh|fish|sh)$ ]]; then
    # Try to get the current input line (last line that looks like a prompt)
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
# Detect user's shell and read appropriate history
SHELL_HISTORY=""
USER_SHELL=$(basename "$SHELL" 2>/dev/null)

if [[ "$USER_SHELL" == "zsh" ]] && [[ -f ~/.zsh_history ]]; then
    # zsh extended history format: `: timestamp:0;command` or just `command`
    SHELL_HISTORY=$(tail -30 ~/.zsh_history 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | tail -20)
elif [[ "$USER_SHELL" == "zsh" ]] && [[ -f ~/.histfile ]]; then
    SHELL_HISTORY=$(tail -30 ~/.histfile 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | tail -20)
elif [[ -f ~/.bash_history ]]; then
    SHELL_HISTORY=$(tail -20 ~/.bash_history 2>/dev/null)
elif [[ -f ~/.zsh_history ]]; then
    SHELL_HISTORY=$(tail -30 ~/.zsh_history 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | tail -20)
fi

# Get git info if in a repo
GIT_INFO=""
if [[ -d "$PANE_PATH/.git" ]] || git -C "$PANE_PATH" rev-parse --git-dir &>/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$PANE_PATH" branch --show-current 2>/dev/null)
    GIT_STATUS=$(git -C "$PANE_PATH" status --short 2>/dev/null | head -10)
    GIT_INFO="Branch: $GIT_BRANCH
Modified files:
$GIT_STATUS"
fi

# Build context document
cat > "$CONTEXT_FILE" << CONTEXT_EOF
## Terminal Context

**Working Directory:** $PANE_PATH
**Current Process:** $PANE_CMD
**Context Type:** $CONTEXT_TYPE
**Terminal Size:** ${PANE_WIDTH}x${PANE_HEIGHT}

### Git Status
$GIT_INFO

### Recent Shell History
\`\`\`
$SHELL_HISTORY
\`\`\`

### Current Terminal Content (last 500 lines)
\`\`\`
$PANE_CONTENT
\`\`\`

### Current Command Line
\`\`\`
$CMDLINE
\`\`\`
CONTEXT_EOF

echo "$CONTEXT_FILE"
