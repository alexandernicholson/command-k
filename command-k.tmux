#!/usr/bin/env bash
# Command K - tmux plugin for AI-assisted command completion
# Compatible with bash and zsh
# 
# Usage: Add to ~/.tmux.conf:
#   run-shell ~/.tmux/plugins/command-k/command-k.tmux
#
# Default keybinding: prefix + C-k
# Customize with: set -g @command-k-key 'C-k'

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Make scripts executable
chmod +x "$CURRENT_DIR/scripts/"*.sh 2>/dev/null

# Get user config or defaults
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value=$(tmux show-option -gqv "$option")
    if [[ -z "$option_value" ]]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Configuration
KEY=$(get_tmux_option "@command-k-key" "C-k")
POPUP_WIDTH=$(get_tmux_option "@command-k-width" "80%")
POPUP_HEIGHT=$(get_tmux_option "@command-k-height" "70%")
export COMMAND_K_HISTORY_DIR="${COMMAND_K_HISTORY_DIR:-$HOME/.command-k}"

# Bind the key
# We pass the current pane ID to the script via environment variable
# run-shell is needed to properly expand #{pane_id} format
# Redirect output to avoid showing command on Ctrl+C
tmux bind-key "$KEY" run-shell -b "tmux display-popup -E -w '$POPUP_WIDTH' -h '$POPUP_HEIGHT' -e COMMAND_K_SOURCE_PANE='#{pane_id}' '$CURRENT_DIR/scripts/popup-wrapper.sh' 2>/dev/null"

# Also bind without prefix for quick access (optional, commented by default)
# Uncomment to enable: tmux bind-key -n M-k ...
# tmux bind-key -n M-k run-shell -b "tmux display-popup -E -w '$POPUP_WIDTH' -h '$POPUP_HEIGHT' -e COMMAND_K_SOURCE_PANE='#{pane_id}' '$CURRENT_DIR/scripts/interactive.sh'"

echo "Command K loaded. Press prefix + $KEY to activate."
