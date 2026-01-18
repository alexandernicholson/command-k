#!/usr/bin/env bash
# Interactive Command K popup with follow-up support
# Compatible with bash 4+ and zsh

# Don't exit on error - handle errors gracefully
set +e

# Config
HISTORY_DIR="${COMMAND_K_HISTORY_DIR:-$HOME/.command-k}"
SESSION_TIMEOUT=3600  # 1 hour - start new conversation after this

# Source settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/settings.sh"

# Prompt history for up/down arrow support
PROMPT_HISTORY_FILE="$HISTORY_DIR/prompt_history"
mkdir -p "$HISTORY_DIR"
touch "$PROMPT_HISTORY_FILE"

# Disable normal bash history (we don't want shell commands)
set +o history
unset HISTFILE

# Load ONLY our prompt history into readline
HISTSIZE=1000
history -c  # Clear any existing history
while IFS= read -r line; do
    # Skip empty lines and use -- to prevent lines starting with - being treated as options
    [[ -n "$line" ]] && history -s -- "$line"
done < "$PROMPT_HISTORY_FILE" 2>/dev/null

# Clean exit on Ctrl+C
trap 'clear 2>/dev/null; exit 0' INT TERM HUP

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
    # Trim any whitespace
    SOURCE_PANE="${COMMAND_K_SOURCE_PANE//[[:space:]]/}"
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

# Settings menu
show_settings() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}Settings${RESET}                                                  ${BOLD}${CYAN}║${RESET}"
        echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
        echo
        
        # AI Provider
        local current_ai=$(get_setting "ai_provider")
        local available_ai=$(list_ai_providers)
        echo -e "${BOLD}AI Provider:${RESET} ${CYAN}$current_ai${RESET} ${DIM}(available: $available_ai)${RESET}"
        echo -e "  ${DIM}[p] Change provider${RESET}"
        echo
        
        echo -e "${BOLD}Privacy - Context sent to AI:${RESET}"
        echo -e "${DIM}Toggle by entering the number.${RESET}"
        echo
        
        local settings=(
            "send_terminal_content:Terminal content (last 500 lines)"
            "send_shell_history:Shell command history"
            "send_git_status:Git repository status"
            "send_working_dir:Working directory path"
            "send_env_var_names:Environment variable names"
            "send_shell_type:Shell type (bash/zsh/fish)"
            "send_terminal_size:Terminal dimensions"
            "send_current_process:Current running process"
        )
        
        local i=1
        for setting in "${settings[@]}"; do
            local key="${setting%%:*}"
            local desc="${setting#*:}"
            local value=$(get_setting "$key")
            
            if [[ "$value" == "true" ]]; then
                echo -e "  ${GREEN}[$i]${RESET} ${GREEN}✓${RESET} $desc"
            else
                echo -e "  ${RED}[$i]${RESET} ${RED}✗${RESET} $desc"
            fi
            ((i++))
        done
        
        echo
        echo -e "  ${DIM}[a] Enable all  [n] Disable all  [q] Back${RESET}"
        echo
        echo -n "> "
        read -r choice
        
        case "$choice" in
            p|P)
                echo
                echo -e "Select AI provider:"
                echo -e "  [1] auto (prefer claude, fallback to codex)"
                echo -e "  [2] claude"
                echo -e "  [3] codex"
                echo -n "> "
                read -r ai_choice
                case "$ai_choice" in
                    1) set_setting "ai_provider" "auto" ;;
                    2) set_setting "ai_provider" "claude" ;;
                    3) set_setting "ai_provider" "codex" ;;
                esac
                ;;
            [1-8])
                local idx=$((choice - 1))
                local key="${settings[$idx]%%:*}"
                toggle_setting "$key"
                ;;
            a|A)
                for setting in "${settings[@]}"; do
                    local key="${setting%%:*}"
                    set_setting "$key" "true"
                done
                ;;
            n|N)
                for setting in "${settings[@]}"; do
                    local key="${setting%%:*}"
                    set_setting "$key" "false"
                done
                ;;
            q|Q|"")
                # Refresh context with new settings
                CONTEXT_FILE=$(mktemp)
                ~/.tmux/plugins/command-k/scripts/context.sh "$SOURCE_PANE" "$CONTEXT_FILE"
                return
                ;;
        esac
    done
}

# Main interaction loop
main() {
    clear
    local provider_name=$(get_current_provider_name)
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}Command K${RESET} - AI Command Assistant                            ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "  ${DIM}Provider: ${CYAN}$provider_name${RESET}"
    echo
    echo -e "  ${DIM}Commands: [Enter] Send | [Ctrl+C] Cancel | /clear Reset | /insert Last${RESET}"
    echo -e "  ${DIM}          /context Show context | /history Conversation | /settings Settings${RESET}"
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
        # Use read -e for readline support (up/down arrow history)
        read -e -p "> " PROMPT
        
        # Save non-empty, non-command prompts to history
        if [[ -n "$PROMPT" && ! "$PROMPT" =~ ^/ ]]; then
            history -s "$PROMPT"  # Add to readline history
            echo "$PROMPT" >> "$PROMPT_HISTORY_FILE"  # Persist to file
        fi

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
            /settings)
                show_settings
                main  # Restart main to show updated header
                return
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
You are a terminal command assistant. Output ONLY the exact command to run.

CRITICAL RULES:
- Output ONLY the command itself - no shell prompts, no \$, no explanation
- No markdown code blocks - just the raw command
- No "Here's the command:" or similar prefixes
- Single command only (use && or ; for multiple)
- If asked for explanation, then explain - otherwise just the command

Context from user's terminal:
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
        provider_name=$(get_current_provider_name)
        echo -e "${DIM}Thinking... ($provider_name)${RESET}"
        echo

        # Call AI using run_ai_query
        RESPONSE=$(cat "$FULL_PROMPT" | run_ai_query 2>&1)
        AI_EXIT=$?

        rm -f "$FULL_PROMPT"

        if [[ $AI_EXIT -ne 0 ]]; then
            echo -e "${RED}Error from $provider_name:${RESET}"
            echo "$RESPONSE"
            echo
            continue
        fi

        # Display response
        echo -e "${BOLD}${GREEN}━━━ $provider_name ━━━${RESET}"
        echo "$RESPONSE"
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━${RESET}"
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

    # Read result and strip trailing whitespace/newlines
    RESULT=$(cat "$RESULT_FILE" | tr -d '\r' | sed 's/[[:space:]]*$//')
    
    # Send to the source pane using -l for literal text
    if ! tmux send-keys -t "$SOURCE_PANE" -l "$RESULT" 2>&1; then
        echo -e "${RED}Failed to insert (pane: $SOURCE_PANE)${RESET}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Inserted to terminal${RESET}"
    sleep 0.3
}

# Cleanup on exit
cleanup() {
    rm -f "$CONTEXT_FILE" 2>/dev/null
    clear 2>/dev/null
}
trap cleanup EXIT

main "$@"
