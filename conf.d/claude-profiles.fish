# Profile names as the first argument of `claude`, each described by its
# directory. Added to whatever completions claude has, never in place of them.
complete -c claude -n __fish_is_first_arg -a '(__claude_profiles_find | string replace -r "\t$HOME" "\t~")'
