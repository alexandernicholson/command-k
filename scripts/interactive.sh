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

SPECIAL KEYS:
When the user needs to press special keys (like exiting vim, or keyboard shortcuts), use this notation:
- <Esc> - Escape key
- <Enter> or <CR> - Enter/Return key
- <Tab> - Tab key
- <BS> - Backspace
- <Del> - Delete
- <Up>, <Down>, <Left>, <Right> - Arrow keys
- <C-x> - Ctrl+x (e.g., <C-c> for Ctrl+C, <C-d> for Ctrl+D)
- <M-x> or <A-x> - Alt+x
- <F1> through <F12> - Function keys
- <Space> - Space (when it needs to be explicit)

For vim/vi operations:
- Always consider the current mode (INSERT, NORMAL, VISUAL, COMMAND)
- If in INSERT mode, include <Esc> before normal mode commands
- Example: To save and quit from INSERT mode: <Esc>:wq<Enter>
- Example: To exit without saving from INSERT mode: <Esc>:q!<Enter>

For tmux operations:
- Use prefix notation like: <C-b>d (Ctrl+B then d)

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
        
        # Show key legend if special keys are present
        if contains_special_keys "$RESPONSE"; then
            show_key_legend "$RESPONSE"
        fi

        # Save to result file
        echo "$RESPONSE" > "$RESULT_FILE"

        # Append to session history
        echo "## User: $PROMPT" >> "$SESSION_FILE"
        echo "" >> "$SESSION_FILE"
        echo "## Assistant:" >> "$SESSION_FILE"
        echo "$RESPONSE" >> "$SESSION_FILE"
        echo "" >> "$SESSION_FILE"

        # Action menu loop - stays here until success or explicit exit
        while true; do
            echo -e "${YELLOW}[i]nsert | [c]opy | [f]ollow up | [n]ew session | [q]uit${RESET}"
            echo -n "> "
            read -r -n 1 ACTION
            echo

            case "$ACTION" in
                i|I)
                    if insert_result; then
                        exit 0
                    else
                        echo -e "${RED}Insert failed - choose another option${RESET}"
                        echo
                    fi
                    ;;
                c|C)
                    if echo "$RESPONSE" | xclip -selection clipboard 2>/dev/null; then
                        echo -e "${GREEN}✓ Copied to clipboard${RESET}"
                        sleep 0.5
                        exit 0
                    elif echo "$RESPONSE" | pbcopy 2>/dev/null; then
                        echo -e "${GREEN}✓ Copied to clipboard${RESET}"
                        sleep 0.5
                        exit 0
                    elif echo "$RESPONSE" | xsel --clipboard 2>/dev/null; then
                        echo -e "${GREEN}✓ Copied to clipboard${RESET}"
                        sleep 0.5
                        exit 0
                    else
                        echo -e "${RED}Clipboard not available (no xclip, pbcopy, or xsel)${RESET}"
                        echo -e "${DIM}You can manually copy the command above${RESET}"
                        echo
                    fi
                    ;;
                f|F)
                    # Break out of action loop, continue to prompt loop
                    break
                    ;;
                n|N)
                    # Clear session and restart
                    rm -f "$SESSION_FILE"
                    echo -e "${GREEN}✓ Session cleared${RESET}"
                    sleep 0.3
                    main
                    exit 0
                    ;;
                q|Q)
                    exit 0
                    ;;
                $'\e')
                    # Escape key - could be arrow key sequence, read remaining chars
                    read -r -n 2 -t 0.1 EXTRA 2>/dev/null || true
                    # If it was just escape (no extra chars), treat as quit
                    # If it was arrow key ([A, [B, etc), ignore
                    if [[ -z "$EXTRA" ]]; then
                        exit 0
                    fi
                    # Arrow key or other escape sequence - just ignore
                    ;;
                *)
                    # Invalid key - just re-show menu
                    ;;
            esac
        done
    done
}

# Check if a string contains special key notation
contains_special_keys() {
    local text="$1"
    # Use simple glob patterns for reliable matching
    [[ "$text" == *"<Esc>"* ]] || \
    [[ "$text" == *"<Enter>"* ]] || \
    [[ "$text" == *"<CR>"* ]] || \
    [[ "$text" == *"<Tab>"* ]] || \
    [[ "$text" == *"<BS>"* ]] || \
    [[ "$text" == *"<Del>"* ]] || \
    [[ "$text" == *"<Up>"* ]] || \
    [[ "$text" == *"<Down>"* ]] || \
    [[ "$text" == *"<Left>"* ]] || \
    [[ "$text" == *"<Right>"* ]] || \
    [[ "$text" == *"<Space>"* ]] || \
    [[ "$text" == *"<C-"* ]] || \
    [[ "$text" == *"<M-"* ]] || \
    [[ "$text" == *"<A-"* ]] || \
    [[ "$text" == *"<F1>"* ]] || \
    [[ "$text" == *"<F2>"* ]] || \
    [[ "$text" == *"<F3>"* ]] || \
    [[ "$text" == *"<F4>"* ]] || \
    [[ "$text" == *"<F5>"* ]] || \
    [[ "$text" == *"<F6>"* ]] || \
    [[ "$text" == *"<F7>"* ]] || \
    [[ "$text" == *"<F8>"* ]] || \
    [[ "$text" == *"<F9>"* ]] || \
    [[ "$text" == *"<F10>"* ]] || \
    [[ "$text" == *"<F11>"* ]] || \
    [[ "$text" == *"<F12>"* ]]
}

# Convert special key notation to tmux send-keys format and send
send_with_special_keys() {
    local text="$1"
    local pane="$2"
    
    # Process the string character by character, handling special keys
    local remaining="$text"
    
    while [[ -n "$remaining" ]]; do
        # Check if current position starts with a special key
        if [[ "$remaining" =~ ^\<([^>]+)\>(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            remaining="${BASH_REMATCH[2]}"
            
            # Convert to tmux key format
            case "$key" in
                Esc)       tmux send-keys -t "$pane" Escape ;;
                Enter|CR)  tmux send-keys -t "$pane" Enter ;;
                Tab)       tmux send-keys -t "$pane" Tab ;;
                BS)        tmux send-keys -t "$pane" BSpace ;;
                Del)       tmux send-keys -t "$pane" DC ;;
                Up)        tmux send-keys -t "$pane" Up ;;
                Down)      tmux send-keys -t "$pane" Down ;;
                Left)      tmux send-keys -t "$pane" Left ;;
                Right)     tmux send-keys -t "$pane" Right ;;
                Space)     tmux send-keys -t "$pane" Space ;;
                C-?)
                    # Ctrl combinations: C-c -> C-c (tmux understands this format)
                    tmux send-keys -t "$pane" "$key"
                    ;;
                M-?|A-?)
                    # Alt combinations: A-x -> M-x for tmux
                    local alt_key="${key/A-/M-}"
                    tmux send-keys -t "$pane" "$alt_key"
                    ;;
                F[0-9]|F1[0-2])
                    # Function keys
                    tmux send-keys -t "$pane" "$key"
                    ;;
                *)
                    # Unknown special key - send literally
                    tmux send-keys -t "$pane" -l "<$key>"
                    ;;
            esac
        else
            # Find the next special key or end of string
            if [[ "$remaining" =~ ^([^<]+)(.*) ]]; then
                local literal="${BASH_REMATCH[1]}"
                remaining="${BASH_REMATCH[2]}"
                # Send literal text
                tmux send-keys -t "$pane" -l "$literal"
            else
                # No more special keys, send rest as literal
                tmux send-keys -t "$pane" -l "$remaining"
                break
            fi
        fi
    done
}

# Display key legend for special keys
show_key_legend() {
    local text="$1"
    local has_legend=false
    
    echo -e "${DIM}Key Legend:${RESET}"
    
    if [[ "$text" == *"<Esc>"* ]]; then
        echo -e "  ${DIM}<Esc>    = Escape key${RESET}"
        has_legend=true
    fi
    if [[ "$text" == *"<Enter>"* || "$text" == *"<CR>"* ]]; then
        echo -e "  ${DIM}<Enter>  = Enter/Return key${RESET}"
        has_legend=true
    fi
    if [[ "$text" == *"<Tab>"* ]]; then
        echo -e "  ${DIM}<Tab>    = Tab key${RESET}"
        has_legend=true
    fi
    if [[ "$text" == *"<C-"* ]]; then
        echo -e "  ${DIM}<C-x>    = Ctrl + x${RESET}"
        has_legend=true
    fi
    if [[ "$text" == *"<M-"* || "$text" == *"<A-"* ]]; then
        echo -e "  ${DIM}<M-x>    = Alt + x${RESET}"
        has_legend=true
    fi
    if [[ "$text" == *"<Space>"* ]]; then
        echo -e "  ${DIM}<Space>  = Space bar${RESET}"
        has_legend=true
    fi
    
    if $has_legend; then
        echo
    fi
}

insert_result() {
    if [[ ! -f "$RESULT_FILE" ]]; then
        echo -e "${RED}No result to insert${RESET}"
        return 1
    fi

    # Read result and strip trailing whitespace/newlines
    RESULT=$(cat "$RESULT_FILE" | tr -d '\r' | sed 's/[[:space:]]*$//')
    
    # Check if result contains special keys
    if contains_special_keys "$RESULT"; then
        echo -e "${CYAN}📋 Sending key sequence...${RESET}"
        if ! send_with_special_keys "$RESULT" "$SOURCE_PANE" 2>&1; then
            echo -e "${RED}Failed to send keys (pane: $SOURCE_PANE)${RESET}"
            return 1
        fi
        echo -e "${GREEN}✓ Key sequence sent to terminal${RESET}"
    else
        # Send to the source pane using -l for literal text
        if ! tmux send-keys -t "$SOURCE_PANE" -l "$RESULT" 2>&1; then
            echo -e "${RED}Failed to insert (pane: $SOURCE_PANE)${RESET}"
            return 1
        fi
        echo -e "${GREEN}✓ Inserted to terminal${RESET}"
    fi
    
    sleep 0.3
    return 0
}

# Cleanup on exit
cleanup() {
    rm -f "$CONTEXT_FILE" 2>/dev/null
    clear 2>/dev/null
}
trap cleanup EXIT

main "$@"
