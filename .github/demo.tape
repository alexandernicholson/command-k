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
Sleep 300ms
# Set clean PS1 without hostname
Type "export PS1='\\[\\033[01;32m\\]\\u\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '"
Enter
Sleep 200ms
Show

# Start tmux with clean status
Type "tmux new-session -s demo"
Enter
Sleep 1s

# Set clean prompt inside tmux and hide hostname from status
Type "export PS1='\\[\\033[01;32m\\]\\u\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '"
Enter
Type "tmux set status-right ''"
Enter
Type "clear"
Enter
Sleep 500ms

# Go to repo
Type "cd ~/.tmux/plugins/command-k"
Enter
Sleep 300ms

# Trigger Command K (prefix + C-k)
Ctrl+b
Ctrl+k

# Wait for popup to appear
Sleep 2s

# Type the query
Type "git log with colors, graph, oneline, all branches"
Sleep 500ms
Enter

# Wait for AI response
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
Type "exit"
Enter
Sleep 500ms
