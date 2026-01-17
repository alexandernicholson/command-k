# VHS Demo for Command K - Real functionality
# https://github.com/charmbracelet/vhs

Output demo.gif
Set Shell "bash"
Set FontSize 15
Set Width 1100
Set Height 650
Set Padding 10
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# Clean start - hide setup
Hide
Type "tmux kill-server 2>/dev/null"
Enter
Type "source ~/.ssh/agent.env 2>/dev/null"
Enter
Type "export GIT_SSH_COMMAND='ssh -o BatchMode=yes'"
Enter
Sleep 500ms
Show

# Start directly in tmux
Type "tmux"
Enter
Sleep 1s

# Go to repo and clear
Type "cd ~/.tmux/plugins/command-k && clear"
Enter
Sleep 500ms

# Trigger Command K (prefix + C-k)
Ctrl+b
Ctrl+k

# Wait for popup to appear
Sleep 2s

# Type the query
Type "git log with colors, graph, oneline, all branches"
Sleep 500ms
Enter

# Wait for Claude response
Sleep 14s

# Insert the result
Type "i"

# Wait for popup to close and command to be inserted
Sleep 2s

# Execute the inserted command
Enter

# Show the beautiful output - give time to appreciate it
Sleep 8s

# Clean exit
Ctrl+d
Sleep 500ms
