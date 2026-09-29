# claude [profile] [claude's own arguments…]
#
# Claude Code, in the profile you name - or, if you don't name one, the one you
# used last. Everything after the profile goes to Claude Code untouched, so
# `claude personal -r` and `claude -c` mean what they always did.
#
# Before it starts, every profile is brought into line with the others (see
# __claude_profiles_share and __claude_profiles_merge). That takes a few
# milliseconds, asks nothing, and prints nothing unless it changed something.
#
# A CLAUDE_CONFIG_DIR already set in the environment is an explicit choice, and
# it wins over the remembered profile: it's how a copied resume command, like
# `CLAUDE_CONFIG_DIR=~/.claude-work claude --resume <id>`, keeps meaning what it says.
function claude --description 'Claude Code, in the profile you name or the one you used last'
    set -l name
    set -l dir
    if set -q argv[1]; and set dir (__claude_profiles_find $argv[1])
        set name $argv[1]
        set -e argv[1]
        __claude_profiles_state last $name
    else if set -q CLAUDE_CONFIG_DIR[1]
        set dir (path resolve -- $CLAUDE_CONFIG_DIR)
    else
        set name (__claude_profiles_state last)
        # The profile it remembers may have been renamed or removed since.
        set dir (__claude_profiles_find "$name"); or set dir $HOME/.claude
    end

    for profile in (__claude_profiles_find)[2..]
        __claude_profiles_share (string split \t -- $profile)[2]
    end
    __claude_profiles_merge

    # For anything of your own that should happen before every launch:
    #   function my-check --on-event claude_profiles_launch; …; end
    emit claude_profiles_launch $dir

    # The default profile runs with no CLAUDE_CONFIG_DIR at all, never with it set
    # to ~/.claude: set, Claude Code looks for its state file inside the
    # directory, but the default one lives beside it at ~/.claude.json, so it
    # would think this is a first run. `env` also skips this function and runs
    # the real claude from $PATH.
    if test "$dir" = $HOME/.claude
        env -u CLAUDE_CONFIG_DIR claude $argv
    else
        env CLAUDE_CONFIG_DIR=$dir claude $argv
    end
end
