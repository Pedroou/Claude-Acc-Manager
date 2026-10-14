# claude-help, or `claude help` - every command this tool adds to `claude`.
function claude-help --description 'Show the claude-profiles commands'
    echo
    echo "Usage:"
    echo "  claude [<args>…]                      Start Claude Code with the last profile used"
    echo "  claude-<profile> [<args>…]            Start Claude Code with the chosen profile"
    echo "  claude-profiles                       List your profiles"
    echo "  claude-profiles add <name>            Add a new profile (for another account)"
    echo "  claude-profiles remove <name>         Remove one (the shared history and settings survive)"
    echo "  claude-profiles rename <old> <new>    Rename one (including the default profile)"
    echo "  claude-help                           Show this helpfull usage info"
    echo
    echo "'claude-profiles', 'claude-<profile>' and 'claude-help' also work as 'claude profiles', 'claude <profile>' and 'claude help'."
    echo
    echo
end
