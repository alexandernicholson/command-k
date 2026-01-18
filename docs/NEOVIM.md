# Command K for Neovim

Like Cursor's CMD+K, but for Neovim. Get AI-powered command and code suggestions with full context awareness.

## Installation

### With lazy.nvim

```lua
{
  "alexandernicholson/command-k",
  build = "cd cmdk-rs && cargo build --release",
  config = function()
    require("cmdk").setup({
      -- Optional: path to binary (auto-detected if nil)
      binary_path = nil,
      -- Keybinding to open Command K
      keymap = "<C-k>",
      -- Floating window settings
      width = 0.8,
      height = 0.7,
      border = "rounded",
    })
  end,
}
```

### With packer.nvim

```lua
use {
  "alexandernicholson/command-k",
  run = "cd cmdk-rs && cargo build --release",
  config = function()
    require("cmdk").setup()
  end,
}
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/alexandernicholson/command-k ~/.config/nvim/pack/plugins/start/command-k
   ```

2. Build the Rust binary:
   ```bash
   cd ~/.config/nvim/pack/plugins/start/command-k/cmdk-rs
   cargo build --release
   ```

3. Add to your Neovim config:
   ```lua
   require("cmdk").setup()
   ```

## Requirements

- Neovim 0.8+ (for floating windows and Lua API)
- Rust/Cargo (for building cmdk-rs)
- **AI CLI (one of):**
  - [Claude Code](https://github.com/anthropics/claude-code) (`claude`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)

## Usage

### Keybindings

| Mode | Key | Action |
|------|-----|--------|
| Normal | `<C-k>` | Open Command K |
| Visual | `<C-k>` | Open with selection |

### Commands

| Command | Description |
|---------|-------------|
| `:CmdK` | Open Command K |
| `:CmdKQuery <prompt>` | Quick query (non-interactive) |

### In the Popup

1. Type your request: "refactor this function", "add error handling", etc.
2. Review the AI suggestion
3. Choose an action:
   - **Insert at cursor** - Insert the result at your cursor position
   - **Replace line/selection** - Replace the current line or visual selection
   - **Copy to clipboard** - Copy the result
   - **Cancel** - Close without action

### Example Prompts

```
> add type annotations to this function
> explain what this code does
> refactor to use async/await
> add error handling for edge cases
> write unit tests for this function
> optimize this for performance
```

## Configuration

```lua
require("cmdk").setup({
  -- Path to cmdk-rs binary (auto-detected if nil)
  binary_path = nil,

  -- Keybinding to open Command K (set to nil to disable)
  keymap = "<C-k>",

  -- Floating window dimensions (as percentage of screen)
  width = 0.8,
  height = 0.7,

  -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
  border = "rounded",

  -- Context settings (what gets sent to the AI)
  send_buffer_content = true,     -- Current buffer content
  send_filetype = true,           -- File type/language
  send_cursor_position = true,    -- Cursor line and column
  send_visual_selection = true,   -- Selected text (in visual mode)
  send_lsp_diagnostics = true,    -- LSP errors/warnings
})
```

## Context Awareness

Command K captures rich context from your Neovim session:

| Context | Description |
|---------|-------------|
| Buffer content | Current file content (truncated to ~10KB) |
| File type | Language/syntax type (e.g., `python`, `typescript`) |
| Cursor position | Current line and column |
| Visual selection | Selected text when invoked in visual mode |
| LSP diagnostics | Errors and warnings from language servers |
| Terminal context | Shell, working directory, git status (shared with CLI) |

This context helps the AI understand what you're working on and provide relevant suggestions.

## Privacy

Context is sent to your configured AI provider (Claude or Codex). You can control what terminal context is sent via the shared settings file (`~/.command-k/settings.conf`) or the CLI settings menu (`cmdk-rs -s`).

Buffer content and Neovim-specific context are controlled by the plugin configuration options.

## Differences from tmux Plugin

| Feature | tmux Plugin | Neovim Plugin |
|---------|-------------|---------------|
| Context | Terminal content | Buffer content + LSP |
| Actions | Insert to terminal | Insert/Replace in buffer |
| Integration | tmux send-keys | Neovim API |
| Selection | N/A | Visual mode support |

## Troubleshooting

### Binary not found

If you see "cmdk-rs binary not found", either:

1. Build the binary: `cd cmdk-rs && cargo build --release`
2. Or set the path explicitly:
   ```lua
   require("cmdk").setup({
     binary_path = "/path/to/cmdk-rs"
   })
   ```

### No AI provider

Ensure you have either `claude` or `codex` CLI installed and in your PATH:

```bash
# Check if available
which claude
which codex
```

### Floating window issues

If the floating window doesn't appear correctly, try adjusting the dimensions:

```lua
require("cmdk").setup({
  width = 0.6,
  height = 0.5,
})
```
