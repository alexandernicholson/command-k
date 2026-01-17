#!/usr/bin/env bash
# Interactive Command K popup with follow-up support

set -e

# Config
HISTORY_DIR="${COMMAND_K_HISTORY_DIR:-$HOME/.command-k}"
SESSION_TIMEOUT=3600  # 1 hour - start new conversation after this

# Colors
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Get the original pane we were called from
ORIGINAL_PANE="$TMUX_PANE"
ORIGINAL_PANE="${ORIGINAL_PANE:-$(tmux display-message -p '#{pane_id}')}"

# For popup, we need to get the pane that was active before the popup
if [[ -n "$COMMAND_K_SOURCE_PANE" ]]; then
    SOURCE_PANE="$COMMAND_K_SOURCE_PANE"
else
    SOURCE_PANE="$ORIGINAL_PANE"
fi

mkdir -p "$HISTORY_DIR"

# Session file for conversation continuity (per source pane)
PANE_HASH=$(echo "$SOURCE_PANE" | md5sum | cut -c1-8)
SESSION_FILE="$HISTORY_DIR/session-$PANE_HASH.md"
RESULT_FILE="$HISTORY_DIR/last-result.txt"

# Check if session is stale
if [[ -f "$SESSION_FILE" ]]; then
    LAST_MOD=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || stat -f %m "$SESSION_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if (( NOW - LAST_MOD > SESSION_TIMEOUT )); then
        rm -f "$SESSION_FILE"
    fi
fi

# Gather context
CONTEXT_FILE=$(mktemp)
~/.tmux/plugins/command-k/scripts/context.sh "$SOURCE_PANE" "$CONTEXT_FILE"

# Build conversation history display
show_history() {
    if [[ -f "$SESSION_FILE" ]]; then
        echo -e "${DIM}--- Conversation History ---${RESET}"
        cat "$SESSION_FILE" | head -50
        echo -e "${DIM}--- End History ---${RESET}"
        echo
    fi
}

# Main interaction loop
main() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}Command K${RESET} - AI Command Assistant                            ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "${DIM}Commands: [Enter] Send | [Ctrl+C] Cancel | /clear Reset | /insert Last${RESET}"
    echo -e "${DIM}          /context Show context | /history Show conversation${RESET}"
    echo

    # Show if we have an ongoing conversation
    if [[ -f "$SESSION_FILE" ]]; then
        TURN_COUNT=$(grep -c "^## User:" "$SESSION_FILE" 2>/dev/null || echo 0)
        echo -e "${GREEN}↪ Continuing conversation (${TURN_COUNT} previous turns)${RESET}"
        echo -e "${DIM}  Type /clear to start fresh${RESET}"
        echo
    fi

    while true; do
        echo -e "${BOLD}${YELLOW}What do you need?${RESET}"
        echo -n "> "
        read -r PROMPT

        # Handle commands
        case "$PROMPT" in
            /clear)
                rm -f "$SESSION_FILE"
                echo -e "${GREEN}✓ Conversation cleared${RESET}"
                echo
                continue
                ;;
            /context)
                echo -e "${DIM}--- Current Context ---${RESET}"
                cat "$CONTEXT_FILE"
                echo -e "${DIM}--- End Context ---${RESET}"
                echo
                continue
                ;;
            /history)
                show_history
                continue
                ;;
            /insert)
                if [[ -f "$RESULT_FILE" ]]; then
                    insert_result
                    exit 0
                else
                    echo -e "${RED}No previous result to insert${RESET}"
                    echo
                fi
                continue
                ;;
            /quit|/exit|/q)
                exit 0
                ;;
            "")
                continue
                ;;
        esac

        # Build the full prompt with context and history
        FULL_PROMPT=$(mktemp)
        
        cat > "$FULL_PROMPT" << PROMPT_EOF
You are helping a user in their terminal. They will ask for commands, code snippets, or explanations.

RULES:
- For commands/code: Output ONLY the command or code, no explanations unless asked
- Be concise and precise
- If multiple options exist, give the most common/safest one
- For dangerous operations, include a brief warning
- Match the user's context (shell, editor, etc.)

$(cat "$CONTEXT_FILE")

PROMPT_EOF

        # Add conversation history if exists
        if [[ -f "$SESSION_FILE" ]]; then
            echo "## Previous Conversation:" >> "$FULL_PROMPT"
            cat "$SESSION_FILE" >> "$FULL_PROMPT"
            echo "" >> "$FULL_PROMPT"
        fi

        echo "## User: $PROMPT" >> "$FULL_PROMPT"

        echo
        echo -e "${DIM}Thinking...${RESET}"
        echo

        # Call Claude Code
        RESPONSE=$(cat "$FULL_PROMPT" | claude --print 2>&1)
        CLAUDE_EXIT=$?

        rm -f "$FULL_PROMPT"

        if [[ $CLAUDE_EXIT -ne 0 ]]; then
            echo -e "${RED}Error from Claude:${RESET}"
            echo "$RESPONSE"
            echo
            continue
        fi

        # Display response
        echo -e "${BOLD}${GREEN}━━━ Claude ━━━${RESET}"
        echo "$RESPONSE"
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━${RESET}"
        echo

        # Save to result file
        echo "$RESPONSE" > "$RESULT_FILE"

        # Append to session history
        echo "## User: $PROMPT" >> "$SESSION_FILE"
        echo "" >> "$SESSION_FILE"
        echo "## Assistant:" >> "$SESSION_FILE"
        echo "$RESPONSE" >> "$SESSION_FILE"
        echo "" >> "$SESSION_FILE"

        # Ask what to do
        echo -e "${YELLOW}[i]nsert to terminal | [c]opy to clipboard | [f]ollow up | [q]uit${RESET}"
        echo -n "> "
        read -r -n 1 ACTION
        echo

        case "$ACTION" in
            i|I)
                insert_result
                exit 0
                ;;
            c|C)
                echo "$RESPONSE" | xclip -selection clipboard 2>/dev/null || \
                echo "$RESPONSE" | pbcopy 2>/dev/null || \
                echo -e "${RED}Clipboard not available${RESET}"
                echo -e "${GREEN}✓ Copied to clipboard${RESET}"
                sleep 0.5
                exit 0
                ;;
            f|F)
                echo
                continue
                ;;
            q|Q|$'\e')
                exit 0
                ;;
            *)
                echo
                continue
                ;;
        esac
    done
}

insert_result() {
    if [[ ! -f "$RESULT_FILE" ]]; then
        echo -e "${RED}No result to insert${RESET}"
        return 1
    fi

    RESULT=$(cat "$RESULT_FILE")
    
    # Escape special characters for tmux send-keys
    # Send the result to the source pane
    tmux send-keys -t "$SOURCE_PANE" "$RESULT"
    
    echo -e "${GREEN}✓ Inserted to terminal${RESET}"
    sleep 0.3
}

# Cleanup on exit
cleanup() {
    rm -f "$CONTEXT_FILE"
}
trap cleanup EXIT

main "$@"
