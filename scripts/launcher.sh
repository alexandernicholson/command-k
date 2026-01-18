#!/usr/bin/env bash
# Launcher script to get pane ID and start popup
# This is called by run-shell and handles all output suppression

# Get the source pane ID
PANE=$(tmux display-message -p '#{pane_id}')

# Get config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDTH="${COMMAND_K_WIDTH:-80%}"
HEIGHT="${COMMAND_K_HEIGHT:-70%}"

# Launch popup with all output suppressed
exec tmux display-popup -E -w "$WIDTH" -h "$HEIGHT" \
    -e "COMMAND_K_SOURCE_PANE=$PANE" \
    "$SCRIPT_DIR/popup-wrapper.sh" 2>/dev/null
