complete -c claude-profiles -f
complete -c claude-profiles -n __fish_use_subcommand -a list -d 'List your profiles'
complete -c claude-profiles -n __fish_use_subcommand -a add -d 'Make a new profile, for another account'
complete -c claude-profiles -n __fish_use_subcommand -a remove -d 'Delete a profile; what is shared stays'
complete -c claude-profiles -n __fish_use_subcommand -a rename -d 'Rename a profile'
complete -c claude-profiles -n __fish_use_subcommand -a help -d 'Show usage'
complete -c claude-profiles -n '__fish_seen_subcommand_from remove rm rename mv; and __fish_is_nth_token 2' \
    -a '(__claude_profiles_find | string replace -r "\t$HOME" "\t~")'
