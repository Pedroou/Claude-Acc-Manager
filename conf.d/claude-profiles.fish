# Profile names as the first argument of `claude`, each described by its
# directory, and this tool's own two words. Added to whatever completions
# claude has, never in place of them.
complete -c claude -n __fish_is_first_arg -a '(__claude_profiles_find | string replace -r "\t$HOME" "\t~")'
complete -c claude -n __fish_is_first_arg -a profiles -d 'List, add, remove or rename profiles'
complete -c claude -n __fish_is_first_arg -a help -d 'Show the claude-profiles commands'
complete -c claude-help -f

# claude-<profile>, for each one there is. Checked first because after a `git
# pull`, this file is already the new one until install.fish links the function.
functions -q __claude_profiles_shortcuts; and __claude_profiles_shortcuts
