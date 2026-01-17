# VHS Demo for Command K
# https://github.com/charmbracelet/vhs

Output demo.gif
Set Shell "bash"
Set FontSize 15
Set Width 1100
Set Height 650
Set Padding 10
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# Setup
Hide
Type "tmux kill-server 2>/dev/null"
Enter
Type "export PS1='\\u:\\w\\$ '"
Enter
# Source nvm to get codex in PATH
Type "source ~/.nvm/nvm.sh 2>/dev/null"
Enter
Sleep 300ms
Show

# Start tmux
Type "tmux"
Enter
Sleep 1s

# Set simple prompt and clean status bar (remove hostname)
Type "export PS1='\\u:\\w\\$ '"
Enter
Type "tmux set status-left '[#S] '"
Enter
Type "tmux set status-right '%H:%M'"
Enter
Type "cd ~/.tmux/plugins/command-k && clear"
Enter
Sleep 500ms

# Trigger Command K (prefix + C-k)
Ctrl+b
Ctrl+k

# Wait for popup
Sleep 2s

# Type the query
Type "git log with colors, graph, oneline, all branches"
Sleep 500ms
Enter

# Wait for AI response
Sleep 14s

# Insert the result
Type "i"

# Wait and execute
Sleep 2s
Enter

# Show output
Sleep 8s

# Exit
Ctrl+d
Sleep 500ms
