#!/usr/bin/env bash
# Wrapper to ensure clean exit from popup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Debug: log to file
echo "COMMAND_K_SOURCE_PANE=[$COMMAND_K_SOURCE_PANE]" > /tmp/cmdk-debug.log

# Run the interactive script, always exit 0
"$SCRIPT_DIR/interactive.sh"
exit 0
