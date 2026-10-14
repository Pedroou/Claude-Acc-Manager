# A `claude-<name>` for every profile, as one word for `claude <name>`.
#
# Made from the disk like everything else, at shell start (conf.d) and again by
# add, remove and rename, so the shell they ran in keeps up. Others already open
# catch up when they restart; until then a shortcut to a profile that's gone
# says so rather than handing its name to Claude Code as a prompt.
#
# Never in place of a command or function that's already there - claude-profiles
# and claude-help included.
function __claude_profiles_shortcuts
    set -q __claude_profiles_shortcuts; or set -g __claude_profiles_shortcuts
    for fn in $__claude_profiles_shortcuts
        functions -e $fn
    end
    set -g __claude_profiles_shortcuts

    for line in (__claude_profiles_find)
        set -l name (string split \t -- $line)[1]
        set -l fn claude-$name
        functions -q $fn; or command -q $fn; and continue
        function $fn --inherit-variable name --description "Claude Code, in the $name profile"
            if not __claude_profiles_find $name >/dev/null
                echo "claude-$name: there's no profile called '$name' any more. See 'claude-profiles'." >&2
                return 1
            end
            claude $name $argv
        end
        set -a __claude_profiles_shortcuts $fn
    end
end
