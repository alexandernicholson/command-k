# Command K - AI Command Assistant for tmux

![IMG_6824](https://github.com/user-attachments/assets/ee82b449-47c9-46d8-a534-5c8f335c955d)


Like Cursor's CMD+K, but for your terminal. Get AI-powered command suggestions with full context awareness.

![Command K Demo](https://vhs.charm.sh/vhs-Dc6dHb2teLwxP3l0nnyq6.gif)

## Features

- **Context-aware**: Captures terminal content, working directory, git status, shell history
- **Follow-ups**: Continue conversations without losing context
- **Preview first**: See the suggestion before inserting
- **Smart detection**: Knows if you're in vim, a REPL, SSH session, etc.

## Installation

### With TPM (recommended)

Install [TPM (Tmux Plugin Manager)](https://github.com/tmux-plugins/tpm).

Add to `~/.tmux.conf`:

```bash
set -g @plugin 'alexandernicholson/command-k'
```

Then press `prefix + I` (as in, capital I) to install.

Updates are performed with `prefix + U` (as in, capital U), followed by typing the name of the plugin, `commmand-k` and pressing ENTER.

### Manual

```bash
git clone https://github.com/alexandernicholson/command-k ~/.tmux/plugins/command-k

# Add to ~/.tmux.conf
echo "run-shell ~/.tmux/plugins/command-k/command-k.tmux" >> ~/.tmux.conf

# Reload tmux
tmux source ~/.tmux.conf
```

## Requirements

- **AI CLI (one of):**
  - [Claude Code](https://github.com/anthropics/claude-code) (`claude`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
- bash 4+ or zsh
- **For tmux plugin:** tmux 3.2+ (for `display-popup`)
- **For standalone CLI:** [gum](https://github.com/charmbracelet/gum)

## Usage

### Standalone CLI (no tmux required)

```bash
# Add to your PATH
ln -s ~/.tmux/plugins/command-k/cmdk ~/.local/bin/cmdk

# Interactive TUI
cmdk

# Quick query (outputs command directly)
cmdk -q "find files larger than 100MB"

# View current context
cmdk -c

# Privacy settings
cmdk -s
```

### tmux Plugin

1. Press `prefix + Ctrl-k` (default: `C-b C-k`)
2. Type what you need: "git command to undo last commit"
3. Review the suggestion
4. Press `i` to insert, `c` to copy, `f` to follow up, `q` to quit

### Commands in the popup

| Command | Action |
|---------|--------|
| `/clear` | Reset conversation history |
| `/context` | Show captured terminal context |
| `/history` | Show conversation history |
| `/settings` | Privacy settings menu |
| `/insert` | Insert last result |
| `/quit` | Exit |

### Action keys

| Key | Action |
|-----|--------|
| `i` | Insert result to terminal |
| `c` | Copy to clipboard |
| `f` | Follow up (continue conversation) |
| `q` | Quit |

## Configuration

### AI Provider

Command K supports both Claude and Codex. Configure via `/settings` or edit `~/.command-k/settings.conf`:

```bash
# Options: auto, claude, codex
ai_provider=auto
```

`auto` prefers Claude, falls back to Codex if Claude isn't installed.

### tmux Options

Add to `~/.tmux.conf` before the plugin loads:

```bash
# Change keybinding (default: C-k)
set -g @command-k-key 'k'

# Popup size (default: 80% x 70%)
set -g @command-k-width '90%'
set -g @command-k-height '80%'
```

## Privacy Controls

Use `/settings` in the popup to control what context is sent to Claude. All settings are persistent.

| Setting | Description |
|---------|-------------|
| Terminal content | Last 500 lines of visible output |
| Shell history | Recent command history |
| Git status | Branch and modified files |
| Working directory | Current path |
| Environment variables | Variable names only (values never sent) |
| Shell type | bash, zsh, fish, etc. |
| Terminal size | Dimensions |
| Current process | Running command |

Settings are stored in `~/.command-k/settings.conf`.

## How It Works

1. **Captures context** from your current pane (based on privacy settings):
   - Terminal content (last 500 lines)
   - Working directory
   - Current command/process
   - Git status (if in repo)
   - Shell type and environment variable names
   - Recent shell history

2. **Sends to Claude Code** with conversation history for context

3. **Shows response in popup** with options:
   - Insert directly to terminal
   - Copy to clipboard
   - Continue conversation (follow-up)

## Examples

```
> git command to squash last 3 commits into one
git rebase -i HEAD~3

> [f] make it non-interactive, use the first commit message
git reset --soft HEAD~3 && git commit --reuse-message=HEAD@{3}
```

```
> kubectl command to get all pods with high memory usage
kubectl top pods --all-namespaces | sort -k4 -h | tail -20
```

```
> one-liner to find all files modified in last 24h larger than 100MB
find . -type f -mtime -1 -size +100M -ls
```

## Files

- `~/.command-k/` - Conversation history and state
  - `session-*.md` - Per-pane conversation history (auto-expires after 1 hour)
  - `last-result.txt` - Most recent response

## Tips

- Use follow-ups to refine: "make it recursive" or "add error handling"
- Works great for:
  - Complex git commands
  - One-liners (awk, sed, find, etc.)
  - Docker/kubectl commands  
  - Quick scripts
  - Explaining what's on screen
- The context capture helps Claude understand what you're working on

## License

MIT
