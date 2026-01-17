#!/usr/bin/env bash
# Wrapper to ensure clean exit from popup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the interactive script, always exit 0
"$SCRIPT_DIR/interactive.sh"
exit 0
