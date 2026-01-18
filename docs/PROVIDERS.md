# AI Providers

Command K supports multiple AI providers for generating command suggestions. You can use built-in providers or create your own.

## Built-in Providers

### Auto (default)

Automatically selects the best available provider:
1. Claude (if installed)
2. Codex (if installed)

```ini
ai_provider=auto
```

### Claude

Uses [Claude Code CLI](https://github.com/anthropics/claude-code).

```ini
ai_provider=claude
```

**Requirements:**
- `claude` command in PATH
- Valid API key configured

### Codex

Uses [OpenAI Codex CLI](https://github.com/openai/codex).

```ini
ai_provider=codex
```

**Requirements:**
- `codex` command in PATH (via npm: `@openai/codex`)
- Valid API key configured

## Custom Provider

You can plug in any AI provider by specifying a custom command.

### Configuration

Edit `~/.command-k/settings.conf`:

```ini
ai_provider=custom
custom_provider_cmd=/path/to/your/provider
```

Or set via the settings UI (`/settings` in Command K).

### Provider Interface

Your custom provider must:

1. **Read the prompt from stdin** - The full prompt including context is piped to your command
2. **Write the response to stdout** - Just the command/response, no extra formatting
3. **Exit with code 0 on success**

### Input Format

Your provider receives a prompt like this on stdin:

```
You are a terminal command assistant. Output ONLY the exact command to run.

CRITICAL RULES:
- Output ONLY the command itself - no shell prompts, no $, no explanation
- No markdown code blocks - just the raw command
- Single command only (use && or ; for multiple)
- If asked for explanation, then explain - otherwise just the command

## Terminal Context

**Shell:** zsh
**Working Directory:** /home/user/project
**Terminal Size:** 120x40

### Environment Variables (names only)
HOME PATH USER SHELL ...

### Git Status
Branch: main
Modified files:
M  src/app.js

### Recent Shell History
git status
npm test
...

### Current Terminal Content (last 500 lines)
...

## User: list all large files
```

### Output Format

Your provider should output **only** the command:

```
find . -type f -size +100M -ls
```

No explanations, no markdown, no prefixes.

## Example: Custom Provider

### Simple Script Provider

```bash
#!/bin/bash
# my-provider.sh - Custom AI provider using Ollama

# Read prompt from stdin
PROMPT=$(cat)

# Call your AI
ollama run codellama "$PROMPT" 2>/dev/null | \
  grep -v '^$' | \
  head -1
```

### API-based Provider

```bash
#!/bin/bash
# api-provider.sh - Custom provider using an HTTP API

PROMPT=$(cat)

curl -s "https://your-api.com/complete" \
  -H "Authorization: Bearer $YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg p "$PROMPT" '{prompt: $p}')" | \
  jq -r '.response'
```

### Python Provider

```python
#!/usr/bin/env python3
# python-provider.py - Custom provider in Python

import sys
import openai

prompt = sys.stdin.read()

response = openai.ChatCompletion.create(
    model="gpt-4",
    messages=[{"role": "user", "content": prompt}],
    max_tokens=100
)

print(response.choices[0].message.content.strip())
```

## Testing Your Provider

1. **Test manually:**
   ```bash
   echo "list files" | /path/to/your/provider
   ```

2. **Use mock mode to verify integration:**
   ```bash
   # Set your provider
   echo "ai_provider=custom" >> ~/.command-k/settings.conf
   echo "custom_provider_cmd=/path/to/your/provider" >> ~/.command-k/settings.conf
   
   # Run tests
   cd ~/.tmux/plugins/command-k
   ./tests/test.sh
   ```

3. **Test in Command K:**
   - Open Command K (`prefix + C-k`)
   - Check provider shows in header
   - Try a query

## Provider Guidelines

### Do
- Return a single, executable command
- Handle errors gracefully (exit 0, return empty or error message)
- Be fast (users are waiting)
- Support common query patterns (files, git, network, etc.)

### Don't
- Output markdown code blocks
- Include shell prompts (`$`, `>`)
- Add explanations unless asked
- Require interactive input
