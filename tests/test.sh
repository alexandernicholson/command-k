#!/usr/bin/env bash
# Tests for Command K
# Run: ./tests/test.sh

# Don't exit on error - we track failures ourselves
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

section() {
    echo -e "\n${YELLOW}== $1 ==${NC}"
}

# --- Tests ---

section "Script Files"

if [[ -x "$SCRIPT_DIR/scripts/interactive.sh" ]]; then pass "interactive.sh is executable"; else fail "interactive.sh is not executable"; fi
if [[ -x "$SCRIPT_DIR/scripts/popup-wrapper.sh" ]]; then pass "popup-wrapper.sh is executable"; else fail "popup-wrapper.sh is not executable"; fi
if [[ -x "$SCRIPT_DIR/scripts/launcher.sh" ]]; then pass "launcher.sh is executable"; else fail "launcher.sh is not executable"; fi
if [[ -x "$SCRIPT_DIR/scripts/settings.sh" ]]; then pass "settings.sh is executable"; else fail "settings.sh is not executable"; fi
if [[ -x "$SCRIPT_DIR/scripts/context.sh" ]]; then pass "context.sh is executable"; else fail "context.sh is not executable"; fi
if [[ -x "$SCRIPT_DIR/cmdk" ]]; then pass "cmdk is executable"; else fail "cmdk is not executable"; fi

section "Settings"

source "$SCRIPT_DIR/scripts/settings.sh"
init_settings

# Test get/set settings
set_setting "test_setting" "test_value"
[[ "$(get_setting 'test_setting')" == "test_value" ]] && pass "set_setting/get_setting works" || fail "set_setting/get_setting failed"

# Test toggle
set_setting "test_bool" "true"
toggle_setting "test_bool"
[[ "$(get_setting 'test_bool')" == "false" ]] && pass "toggle_setting works" || fail "toggle_setting failed"

# Clean up test settings
sed -i '/^test_/d' "$SETTINGS_FILE" 2>/dev/null || true

section "AI Provider"

# Source nvm if available (needed for codex)
[[ -f ~/.nvm/nvm.sh ]] && source ~/.nvm/nvm.sh 2>/dev/null

# Test get_ai_command
AI_CMD=$(get_ai_command 2>/dev/null) || true
if [[ "$AI_CMD" == "claude --print" ]] || [[ "$AI_CMD" == "CODEX" ]]; then
    pass "get_ai_command returns valid command: $AI_CMD"
elif [[ -z "$AI_CMD" ]]; then
    echo -e "${YELLOW}!${NC} get_ai_command returned empty (no AI CLI found)"
else
    fail "get_ai_command returned unexpected: $AI_CMD"
fi

# Test provider name
PROVIDER=$(get_current_provider_name 2>/dev/null) || true
[[ -n "$PROVIDER" ]] && pass "get_current_provider_name works: $PROVIDER" || fail "get_current_provider_name failed"

section "Context Gathering"

# Test context.sh
CONTEXT_FILE=$(mktemp)
"$SCRIPT_DIR/scripts/context.sh" "" "$CONTEXT_FILE" >/dev/null 2>&1
if [[ -s "$CONTEXT_FILE" ]]; then
    pass "context.sh generates context"
    # Check for expected sections
    grep -q "Terminal Context" "$CONTEXT_FILE" && pass "Context has Terminal Context section" || fail "Context missing Terminal Context section"
    grep -q "Working Directory" "$CONTEXT_FILE" && pass "Context has Working Directory" || fail "Context missing Working Directory"
else
    fail "context.sh generated empty context"
fi
rm -f "$CONTEXT_FILE"

section "History File"

HIST_FILE="${COMMAND_K_HISTORY_DIR:-$HOME/.command-k}/prompt_history"
[[ -f "$HIST_FILE" ]] && pass "Prompt history file exists" || echo -e "${YELLOW}!${NC} Prompt history file doesn't exist yet (OK for first run)"

section "tmux Integration"

if command -v tmux &>/dev/null; then
    pass "tmux is installed"
    
    # Check if binding exists (only if tmux server is running)
    if tmux list-keys 2>/dev/null | grep -q "command-k\|C-k.*display-popup"; then
        pass "Command K keybinding is registered"
    else
        echo -e "${YELLOW}!${NC} Keybinding not found (run 'tmux source ~/.tmux.conf' to load)"
    fi
else
    fail "tmux is not installed"
fi

section "Dependencies"

command -v claude &>/dev/null && pass "claude CLI is installed" || echo -e "${YELLOW}!${NC} claude CLI not found"
command -v codex &>/dev/null && pass "codex CLI is installed" || echo -e "${YELLOW}!${NC} codex CLI not found"
command -v gum &>/dev/null && pass "gum is installed (for cmdk)" || echo -e "${YELLOW}!${NC} gum not found (needed for cmdk standalone)"

section "Mock AI Provider"

# Test mock-ai script exists and is executable
if [[ -x "$SCRIPT_DIR/tests/mock-ai" ]]; then
    pass "mock-ai is executable"
else
    fail "mock-ai is not executable"
fi

# Test mock-ai returns expected output
MOCK_RESPONSE=$(echo "list files" | "$SCRIPT_DIR/tests/mock-ai")
if [[ "$MOCK_RESPONSE" == "ls -la" ]]; then
    pass "mock-ai returns expected command for 'list files'"
else
    fail "mock-ai returned unexpected: $MOCK_RESPONSE"
fi

# Test mock provider setting
ORIG_PROVIDER=$(get_setting "ai_provider")
set_setting "ai_provider" "mock"

MOCK_CMD=$(get_ai_command 2>/dev/null)
if [[ "$MOCK_CMD" == *"mock-ai"* ]]; then
    pass "get_ai_command returns mock-ai path"
else
    fail "get_ai_command with mock provider returned: $MOCK_CMD"
fi

# Test full flow with mock provider
MOCK_RESULT=$(echo "show disk space" | run_ai_query 2>/dev/null)
if [[ "$MOCK_RESULT" == "df -h" ]]; then
    pass "run_ai_query with mock returns correct command"
else
    fail "run_ai_query with mock returned: $MOCK_RESULT"
fi

# Restore original provider
set_setting "ai_provider" "$ORIG_PROVIDER"

section "Custom Provider"

# Save original settings
ORIG_PROVIDER=$(get_setting "ai_provider")
ORIG_CUSTOM_CMD=$(get_setting "custom_provider_cmd")

# Test custom provider with mock-ai as the custom command
set_setting "ai_provider" "custom"
set_setting "custom_provider_cmd" "$SCRIPT_DIR/tests/mock-ai"

CUSTOM_CMD=$(get_ai_command 2>/dev/null)
if [[ "$CUSTOM_CMD" == "$SCRIPT_DIR/tests/mock-ai" ]]; then
    pass "Custom provider returns configured command"
else
    fail "Custom provider returned: $CUSTOM_CMD"
fi

# Test custom provider flow
CUSTOM_RESULT=$(echo "show running processes" | run_ai_query 2>/dev/null)
if [[ "$CUSTOM_RESULT" == "ps aux | head -20" ]]; then
    pass "Custom provider executes correctly"
else
    fail "Custom provider returned: $CUSTOM_RESULT"
fi

# Test custom provider without command set
set_setting "custom_provider_cmd" ""
EMPTY_CMD=$(get_ai_command 2>&1)
if [[ "$EMPTY_CMD" == *"custom_provider_cmd not set"* ]]; then
    pass "Custom provider errors when command not set"
else
    fail "Custom provider should error when command not set: $EMPTY_CMD"
fi

# Restore original settings
set_setting "ai_provider" "$ORIG_PROVIDER"
set_setting "custom_provider_cmd" "$ORIG_CUSTOM_CMD"

section "Insert Function"

# Test the send-keys command format (without actually sending)
if tmux list-panes &>/dev/null; then
    PANE_ID=$(tmux display-message -p '#{pane_id}')
    # Just verify we can get a pane ID
    [[ "$PANE_ID" =~ ^%[0-9]+$ ]] && pass "Can get valid pane ID: $PANE_ID" || fail "Invalid pane ID format: $PANE_ID"
else
    echo -e "${YELLOW}!${NC} Not in tmux session, skipping insert test"
fi

section "Signal Handling"

# Check that launcher.sh has signal traps
if grep -q "trap.*INT" "$SCRIPT_DIR/scripts/launcher.sh"; then
    pass "launcher.sh has INT signal trap"
else
    fail "launcher.sh missing INT signal trap"
fi

if grep -q "trap.*INT" "$SCRIPT_DIR/scripts/interactive.sh"; then
    pass "interactive.sh has INT signal trap"
else
    fail "interactive.sh missing INT signal trap"
fi

# Check popup-wrapper exits cleanly
if grep -q "exit 0" "$SCRIPT_DIR/scripts/popup-wrapper.sh"; then
    pass "popup-wrapper.sh exits with 0"
else
    fail "popup-wrapper.sh missing exit 0"
fi

section "Keybinding Format"

# Check that run-shell doesn't use -b flag (causes return message)
BINDING=$(tmux list-keys -T prefix C-k 2>/dev/null || echo "")
if [[ -n "$BINDING" ]]; then
    if echo "$BINDING" | grep -q "run-shell -b"; then
        fail "Keybinding uses run-shell -b (causes Ctrl+C message)"
    else
        pass "Keybinding doesn't use run-shell -b"
    fi
fi

# --- Summary ---

echo -e "\n${YELLOW}== Summary ==${NC}"
echo -e "${GREEN}Passed: $PASSED${NC}"
[[ $FAILED -gt 0 ]] && echo -e "${RED}Failed: $FAILED${NC}" || echo -e "Failed: $FAILED"

exit $FAILED
