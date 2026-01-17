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

# Ensure clean state
Hide
Type "tmux kill-server 2>/dev/null; sleep 0.5"
Enter
Type "source ~/.tmux.conf 2>/dev/null"
Enter
Sleep 500ms
Show

# Show we're in the command-k repo
Type "cd ~/.tmux/plugins/command-k"
Enter
Sleep 300ms

Type "git log --oneline -3"
Enter
Sleep 1s

Type "# I want a prettier git log... let me ask Command K!"
Enter
Sleep 1.5s

# Start tmux session
Type "tmux"
Enter
Sleep 1s

# Navigate to repo in tmux
Type "cd ~/.tmux/plugins/command-k && clear"
Enter
Sleep 500ms

# Trigger Command K (prefix + C-k)
Ctrl+b
Ctrl+k

# Wait for popup to appear
Sleep 2s

# Type the query
Type "git log with colors, graph, oneline, showing all branches"

Sleep 500ms
Enter

# Wait for Claude response
Sleep 12s

# Insert the result
Type "i"

# Wait for popup to close and command to be inserted
Sleep 2s

# Execute the inserted command
Enter

# Show the beautiful output
Sleep 4s

# Clean exit
Ctrl+d
Sleep 500ms
