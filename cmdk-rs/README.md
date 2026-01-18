# cmdk-rs

Rust implementation of Command K - an AI-powered command assistant for the terminal and Neovim.

## Building

```bash
# Development build
cargo build

# Release build
cargo build --release
```

The binary will be at `target/release/cmdk-rs`.

## Usage

### Standalone CLI

```bash
# Interactive TUI
cmdk-rs

# Direct query mode (outputs command directly)
cmdk-rs -q "find files larger than 100MB"

# Piped input
echo "list all rust files" | cmdk-rs

# View current context
cmdk-rs -c

# Privacy settings
cmdk-rs -s
```

### Neovim Integration

The binary supports a `--nvim` flag for integration with the Neovim Lua plugin:

```bash
# Used by the Neovim plugin (not typically called directly)
cmdk-rs --nvim /path/to/context/file
cmdk-rs --nvim /path/to/context/file -q "quick query"
```

See [docs/NEOVIM.md](../docs/NEOVIM.md) for Neovim plugin setup.

## Requirements

- **AI CLI (one of):**
  - [Claude Code](https://github.com/anthropics/claude-code) (`claude`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)

## Features

- Full ratatui-based TUI with menus, styled output
- Context-aware: captures terminal info, git status, shell history
- Neovim integration: buffer content, filetype, LSP diagnostics
- Follow-up conversations with session history
- Privacy controls for what context is sent
- Supports multiple AI providers (Claude, Codex, custom)
- Compatible with the original bash `cmdk` settings

## Configuration

Settings are stored in `~/.command-k/settings.conf` and are shared with the bash version.

## Architecture

```
src/
├── main.rs       # CLI argument parsing, entry points
├── app.rs        # Application state machine, TUI logic
├── ui.rs         # ratatui UI rendering
├── events.rs     # Keyboard event handling
├── context.rs    # Terminal context gathering
├── nvim.rs       # Neovim integration (context, actions)
├── settings.rs   # Settings file management
├── provider.rs   # AI provider abstraction
└── session.rs    # Conversation history
```
