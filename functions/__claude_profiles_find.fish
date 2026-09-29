# Every profile, or the directory of one.
#
#   __claude_profiles_find          prints "name<TAB>dir" per profile, default first
#   __claude_profiles_find <name>   prints that profile's directory, or fails
#
# A profile is a config directory, which is all Claude Code itself means by one:
# ~/.claude is the default, and any ~/.claude-<name> Claude Code has started in
# is another. That is the whole registry - there is no list to keep in step
# with the disk, because the disk is the list.
#
# "Has started in" means it holds .claude.json or .credentials.json, the two
# files Claude Code writes into a directory it owns. That keeps out whatever
# else happens to be called ~/.claude-something.
function __claude_profiles_find -a want
    set -l default (__claude_profiles_state default-name; or echo default)

    if set -q argv[1]
        if test "$want" = "$default"
            echo $HOME/.claude
            return 0
        end
        # Names are plain words; anything else can't be one, and must not be
        # allowed to glob or walk out of $HOME.
        string match -qr '^[a-z0-9][a-z0-9_-]*$' -- $want; or return 1
        set -l dir $HOME/.claude-$want
        test -d $dir -a ! -L $dir; or return 1
        test -f $dir/.claude.json -o -f $dir/.credentials.json; or return 1
        echo $dir
        return 0
    end

    printf '%s\t%s\n' $default $HOME/.claude
    for dir in $HOME/.claude-*
        test -d $dir -a ! -L $dir; or continue
        test -f $dir/.claude.json -o -f $dir/.credentials.json; or continue
        set -l name (string replace $HOME/.claude- '' -- $dir)
        string match -qr '^[a-z0-9][a-z0-9_-]*$' -- $name; or continue
        # A directory named after the default would be unreachable by name.
        test "$name" = "$default"; and continue
        printf '%s\t%s\n' $name $dir
    end
end
