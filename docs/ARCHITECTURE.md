# Command K Architecture

## Overview

Command K is a tmux plugin that provides AI-powered command suggestions. It captures terminal context, sends it to an AI provider, and inserts the suggested command into your terminal.

```
┌─────────────────────────────────────────────────────────────┐
│                         tmux                                 │
│  ┌─────────────────┐    ┌────────────────────────────────┐  │
│  │  Source Pane    │    │         Popup Window           │  │
│  │                 │    │  ┌──────────────────────────┐  │  │
│  │  $ _            │◄───│  │    interactive.sh        │  │  │
│  │                 │    │  │                          │  │  │
│  │                 │    │  │  - Capture context       │  │  │
│  │                 │    │  │  - Get user prompt       │  │  │
│  │                 │    │  │  - Call AI provider      │  │  │
│  │                 │    │  │  - Insert result         │  │  │
│  │                 │    │  └──────────────────────────┘  │  │
│  └─────────────────┘    └────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Entry Points

| File | Description |
|------|-------------|
| `command-k.tmux` | Plugin entry point, sets up keybinding |
| `cmdk` | Standalone CLI (no tmux required) |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/launcher.sh` | Gets pane ID and launches popup |
| `scripts/popup-wrapper.sh` | Ensures clean exit from popup |
| `scripts/interactive.sh` | Main UI loop, handles user interaction |
| `scripts/context.sh` | Gathers terminal context |
| `scripts/settings.sh` | Settings management and AI provider abstraction |

### Data Flow

1. **Trigger** (`prefix + C-k`)
   - `command-k.tmux` binding triggers `launcher.sh`
   - Launcher captures source pane ID
   - Opens tmux popup with `interactive.sh`

2. **Context Gathering** (`context.sh`)
   - Terminal content (last 500 lines)
   - Working directory
   - Shell type and environment variables
   - Git status (if in repo)
   - Shell history

3. **User Interaction** (`interactive.sh`)
   - Displays prompt with readline support
   - Handles commands (`/settings`, `/context`, etc.)
   - Manages conversation history

4. **AI Query** (`settings.sh`)
   - Routes to appropriate provider (Claude, Codex, custom)
   - Handles provider-specific flags and output parsing

5. **Result Handling**
   - Display response in popup
   - User chooses: insert, copy, or follow-up
   - Insert uses `tmux send-keys` to source pane

## File Structure

```
command-k/
├── command-k.tmux       # Plugin entry point
├── cmdk                 # Standalone CLI
├── scripts/
│   ├── launcher.sh      # Popup launcher
│   ├── popup-wrapper.sh # Clean exit wrapper
│   ├── interactive.sh   # Main UI
│   ├── context.sh       # Context gathering
│   └── settings.sh      # Settings & providers
├── docs/
│   ├── ARCHITECTURE.md  # This file
│   └── PROVIDERS.md     # AI provider docs
├── tests/
│   ├── test.sh          # Test suite
│   └── mock-ai          # Mock provider for testing
└── .github/
    └── workflows/
        └── test.yml     # CI workflow
```

## Settings Storage

Settings are stored in `~/.command-k/settings.conf`:

```ini
ai_provider=auto
custom_provider_cmd=
send_terminal_content=true
send_shell_history=true
...
```

## Conversation History

- Per-directory sessions: `~/.command-k/cli-session-<hash>.md`
- Per-pane sessions: `~/.command-k/session-<hash>.md`
- Prompt history: `~/.command-k/prompt_history`
- Sessions expire after 1 hour of inactivity

## Signal Handling

All scripts handle `INT`, `TERM`, `HUP` signals for clean exit:
- `launcher.sh`: Traps signals to exit silently
- `interactive.sh`: Clears screen and exits
- `popup-wrapper.sh`: Always exits with code 0
