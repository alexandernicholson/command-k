# VHS Demo for Command K
# https://github.com/charmbracelet/vhs

Output demo.gif
Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 500
Set Padding 15
Set Theme "Catppuccin Mocha"

# Start in a project directory
Type "cd ~/projects/api && git status"
Enter
Sleep 1.5s

Type "# Hmm, I need to undo my last commit..."
Enter
Sleep 1s

Type "# Let me use Command K! (prefix + Ctrl-k)"
Enter
Sleep 1.5s

# Simulate the popup appearance
Type "clear"
Enter
Sleep 300ms

# Show a cleaner mock of the UI
Type "cat << 'EOF'"
Enter
Type "╭──────────────────────────────────────────────────╮"
Enter
Type "│  ⌘K  Command K                                   │"
Enter
Type "╰──────────────────────────────────────────────────╯"
Enter
Type ""
Enter
Type "What do you need?"
Enter
Type "> undo last commit but keep changes"
Enter
Type ""
Enter
Type "Thinking..."
Enter
Type ""
Enter
Type "━━━ Response ━━━"
Enter
Type "git reset --soft HEAD~1"
Enter
Type "━━━━━━━━━━━━━━━━━"
Enter
Type ""
Enter
Type "[i]nsert  [c]opy  [f]ollow-up  [q]uit"
Enter
Type "EOF"
Enter
Sleep 2s

Type "# Pressed 'i' - command inserted!"
Enter
Sleep 500ms

Type "git reset --soft HEAD~1"
Sleep 1s
Enter
Sleep 1s

Type "git status"
Enter
Sleep 2s
