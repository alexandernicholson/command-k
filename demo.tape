# VHS Demo for Command K
# https://github.com/charmbracelet/vhs

Output demo.gif
Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "Dracula"

# Start fresh
Type "cd ~/projects/myapp"
Enter
Sleep 500ms

Type "git status"
Enter
Sleep 1s

# Show we're in a git repo with changes
Type "# I need to undo my last commit but keep the changes..."
Enter
Sleep 1s

# Simulate the Command K popup
# Since we can't actually run the interactive popup in vhs,
# we'll show the concept with a simpler demo
Type "# Let me ask Command K!"
Enter
Sleep 500ms

# Show a mock of what the interaction looks like
Type "echo '╔══════════════════════════════════════════════════════════════╗'"
Enter
Type "echo '║  Command K - AI Command Assistant                            ║'"
Enter
Type "echo '╚══════════════════════════════════════════════════════════════╝'"
Enter
Sleep 500ms

Type "echo 'What do you need?'"
Enter
Type "echo '> git command to undo last commit but keep changes'"
Enter
Sleep 1.5s

Type "echo ''"
Enter
Type "echo '━━━ Claude ━━━'"
Enter
Type "echo 'git reset --soft HEAD~1'"
Enter
Type "echo '━━━━━━━━━━━━━━'"
Enter
Sleep 1s

Type "echo '[i]nsert to terminal | [c]opy | [f]ollow up | [q]uit'"
Enter
Sleep 500ms

# Show the result being used
Type "echo 'Pressed: i'"
Enter
Sleep 500ms

Type "git reset --soft HEAD~1"
Enter
Sleep 1s

Type "git status"
Enter
Sleep 2s
