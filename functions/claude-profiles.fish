# claude-profiles [list | add <name> | remove <name> | rename <old> <new>]
#
# Everything about profiles other than using one, which is `claude <name>`.
function claude-profiles --description 'List, add, remove or rename Claude Code profiles'
    set -l command list
    set -q argv[1]; and set command $argv[1]
    set -e argv[1]

    switch $command
        case list ls
            __claude_profiles_list
        case add new
            __claude_profiles_add $argv
        case remove rm
            __claude_profiles_remove $argv
        case rename mv
            __claude_profiles_rename $argv
        case help -h --help
            echo "Usage:"
            echo "  claude [profile] [args…]              start Claude Code (the last-used profile if none given)"
            echo "  claude-profiles                       list your profiles"
            echo "  claude-profiles add <name>            make a new one, for another account"
            echo "  claude-profiles remove <name>         delete one; the shared history and settings stay"
            echo "  claude-profiles rename <old> <new>    rename one, the default included"
        case '*'
            echo "claude-profiles: no such command '$command'. Try 'claude-profiles help'." >&2
            return 2
    end
end

# One line per profile, the one `claude` opens marked:
#
#   ● work       you@company.com     ~/.claude            2 running
#     personal   you@example.com     ~/.claude-personal
function __claude_profiles_list
    set -l last (__claude_profiles_state last; or echo)
    set -l rows
    set -l widths 0 0 0
    set -l marked 0
    for line in (__claude_profiles_find)
        set -l profile (string split \t -- $line)
        # The default profile keeps its state file beside ~/.claude, not in it.
        set -l state $profile[2]/.claude.json
        test $profile[2] = $HOME/.claude; and set state $HOME/.claude.json
        set -l account (jq -r '.oauthAccount.emailAddress // empty' $state 2>/dev/null)
        test -n "$account"; or set account 'not logged in'
        set -l running (__claude_profiles_running $profile[2])
        test $running -gt 0; and set running "$running running"; or set running ''
        set -a rows $profile[1] $account (string replace -r "^$HOME" '~' -- $profile[2]) $running
        test "$profile[1]" = "$last"; and set marked (math (count $rows) / 4)
    end
    # Nothing remembered, or a profile since removed: `claude` opens the default.
    test $marked -eq 0; and set marked 1

    for i in (seq 1 4 (count $rows))
        for c in 1 2 3
            set -l len (string length -- $rows[(math $i + $c - 1)])
            set widths[$c] (math "max($widths[$c], $len)")
        end
    end
    # Quoted, because on a terminal without colours set_color prints nothing,
    # and an unquoted nothing would shift every column after it.
    set -l bold "$(set_color --bold)"
    set -l dim "$(set_color brblack)"
    set -l off "$(set_color normal)"
    for i in (seq 1 4 (count $rows))
        set -l mark ' '
        test (math "($i + 3) / 4") -eq $marked; and set mark "$(set_color green)●$off"
        printf '%s %s%s%s   %s   %s%s%s   %s\n' $mark \
            $bold (string pad -r -w $widths[1] -- $rows[$i]) $off \
            (string pad -r -w $widths[2] -- $rows[(math $i + 1)]) \
            $dim (string pad -r -w $widths[3] -- $rows[(math $i + 2)]) $off \
            $rows[(math $i + 3)]
    end
end

function __claude_profiles_add -a name
    __claude_profiles_new_name "$name"; or return

    set -l dir $HOME/.claude-$name
    mkdir -p $dir; or return
    chmod 700 $dir

    # A new profile would otherwise start at Claude Code's first run: the
    # onboarding, then a "do you trust this folder?" for every project you
    # already trust. Those are answers you've given already, so they carry over
    # from the default profile - and nothing about the account does. The file
    # existing is also what makes the directory a profile.
    set -l seed '{}'
    test -f $HOME/.claude.json; and set seed $HOME/.claude.json
    jq '{hasCompletedOnboarding, lastOnboardingVersion, lastReleaseNotesSeen, theme,
         autoUpdates, installMethod, mcpServers,
         projects: ((.projects // {}) | map_values({hasTrustDialogAccepted}
                                                  | with_entries(select(.value != null))))}
        | with_entries(select(.value != null))' $seed >$dir/.claude.json 2>/dev/null
    or echo '{}' >$dir/.claude.json
    chmod 600 $dir/.claude.json

    __claude_profiles_share $dir
    __claude_profiles_merge 2>/dev/null # reports that the new profile got the settings: it's what add is for

    echo "Added $name, in "(string replace -r "^$HOME" '~' -- $dir)", with everything the other profiles share."
    echo "Log it in to its account:  claude $name, then /login"
end

function __claude_profiles_remove -a name
    set -l default (__claude_profiles_state default-name; or echo default)
    set -l dir (__claude_profiles_find "$name")
    set -l running (__claude_profiles_running "$dir")
    if test -z "$name"
        echo "Usage: claude-profiles remove <name>" >&2
        return 2
    else if test "$name" = "$default"
        echo "claude-profiles: $name is the default profile, ~/.claude, and the shared copy of" >&2
        echo "                 everything lives there. It can be renamed, not removed." >&2
        return 1
    else if test -z "$dir"
        echo "claude-profiles: there's no profile called '$name'." >&2
        return 1
    else if test $running -gt 0
        echo "claude-profiles: $name has $running session(s) running. Close them first." >&2
        return 1
    end

    read -l -P "Remove $name? Its login goes; history, settings and plugins stay shared. [y/N] " reply
    string match -qi 'y*' -- "$reply"; or return 1

    # Whatever it still holds of its own joins the shared copy first - its own
    # files, and any setting it changed since its last launch.
    __claude_profiles_share $dir; or return
    __claude_profiles_merge

    # What's left is the account: the login, which is what you asked to be rid
    # of, and Claude Code's state for it. The state is kept, out of the way,
    # rather than deleted - it's small, and removing a profile shouldn't be the
    # one thing here that can lose something.
    set -l kept $HOME/.claude/backups/removed-$name-(date +%Y%m%d-%H%M%S)
    rm -f $dir/.credentials.json
    # The links into the shared copy go too: a backup shouldn't lead into live data.
    find $dir -mindepth 1 -maxdepth 1 -type l -lname "$HOME/.claude/*" -delete
    mkdir -p (path dirname $kept); and mv -T $dir $kept; or return
    test "$name" = (__claude_profiles_state last; or echo); and __claude_profiles_state last $default
    echo "Removed $name. What was left of it is in "(string replace -r "^$HOME" '~' -- $kept)"."
end

function __claude_profiles_rename -a old new
    set -l default (__claude_profiles_state default-name; or echo default)
    set -l dir (__claude_profiles_find "$old")
    if test -z "$old" -o -z "$new"
        echo "Usage: claude-profiles rename <old> <new>" >&2
        return 2
    else if test -z "$dir"
        echo "claude-profiles: there's no profile called '$old'." >&2
        return 1
    end
    __claude_profiles_new_name "$new"; or return

    if test "$old" = "$default"
        # The default's directory is ~/.claude whatever it's called, so its
        # name is the one thing that has to be written down.
        __claude_profiles_state default-name $new
    else
        set -l running (__claude_profiles_running $dir)
        if test $running -gt 0
            echo "claude-profiles: $old has $running session(s) running. Close them first." >&2
            return 1
        end
        # Sharing first points any plugin path recorded through the old name
        # back at the shared copy; after the move, nothing would find it.
        __claude_profiles_share $dir
        mv $dir $HOME/.claude-$new; or return
    end
    test "$old" = (__claude_profiles_state last; or echo); and __claude_profiles_state last $new
    echo "Renamed $old to $new."
end

# Is this a name a new profile can have? Explains why not, if it isn't.
function __claude_profiles_new_name -a name
    if test -z "$name"
        echo "Usage: claude-profiles add <name>" >&2
        return 2
    end
    if not string match -qr '^[a-z0-9][a-z0-9_-]*$' -- $name
        echo "claude-profiles: a profile name is lowercase letters, digits, - and _." >&2
        return 1
    end
    if __claude_profiles_find $name >/dev/null; or test -e $HOME/.claude-$name
        echo "claude-profiles: '$name' is taken." >&2
        return 1
    end
    # `claude <name>` has to open the profile, so the name can't be one of
    # Claude Code's own commands. Asked of claude itself, so a command added
    # in a later version is caught too.
    set -l commands (command claude --help 2>/dev/null \
        | string match -gr '^  ([a-z][a-z|-]*)(?: |$)' | string split '|')
    if contains -- $name $commands
        echo "claude-profiles: '$name' is one of Claude Code's own commands (claude $name)." >&2
        return 1
    end
end
