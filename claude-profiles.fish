# Claude Code account profiles
#   claude-work          → work account   (stock setup: ~/.claude + ~/.claude.json)
#   claude-personal      → personal account (~/.claude-personal)
#   claude               → whichever profile was launched last (sticky),
#                          remembered in ~/.claude-last-profile; falls back to work.
#   claude-profiles-diff → show what differs between the two profiles
#   claude-profiles-sync → copy settings + plugins from one profile to the other
# All flags are forwarded, so `claude-personal -r`, `claude -c`, etc. work.
# On every launch, warns if settings/plugins have diverged between the two
# profiles (state caches like .claude.json are intentionally not compared).

# Profile dirs are derived from $HOME on every call, never cached in a global:
# a cached global is captured at load time and ignores a later $HOME, which
# makes the code untestable and would point sync at the wrong dirs.
function __claude_work_dir
    echo $HOME/.claude
end

function __claude_pers_dir
    echo $HOME/.claude-personal
end

function __claude_profile_divergence
    set -l work $HOME/.claude
    set -l pers $HOME/.claude-personal
    set -l diffs

    for f in settings.json settings.local.json
        if test -e $work/$f; or test -e $pers/$f
            if not cmp -s $work/$f $pers/$f 2>/dev/null
                set -a diffs $f
            end
        end
    end

    set -l wplugins (jq -r '.plugins | keys | sort | join(",")' $work/plugins/installed_plugins.json 2>/dev/null)
    set -l pplugins (jq -r '.plugins | keys | sort | join(",")' $pers/plugins/installed_plugins.json 2>/dev/null)
    if test "$wplugins" != "$pplugins"
        set -a diffs plugins
    end

    string join \n $diffs
end

function claude-profiles-diff --description 'Show config differences between work and personal Claude profiles'
    set -l work $HOME/.claude
    set -l pers $HOME/.claude-personal
    set -l found 0

    for f in settings.json settings.local.json
        if not cmp -s $work/$f $pers/$f 2>/dev/null
            set found 1
            set_color --bold; echo "── $f (work vs personal) ──"; set_color normal
            diff -u --label work/$f --label personal/$f $work/$f $pers/$f
        end
    end

    set -l wplugins (jq -r '.plugins | keys[]' $work/plugins/installed_plugins.json 2>/dev/null | sort)
    set -l pplugins (jq -r '.plugins | keys[]' $pers/plugins/installed_plugins.json 2>/dev/null | sort)
    for p in $wplugins
        if not contains -- $p $pplugins
            set found 1
            echo "plugin only in work:     $p"
        end
    end
    for p in $pplugins
        if not contains -- $p $wplugins
            set found 1
            echo "plugin only in personal: $p"
        end
    end

    test $found = 0; and echo "Profiles are in sync (settings.json, settings.local.json, plugin list)."
end

function claude-profiles-sync --description 'Copy settings + plugins from one Claude profile to the other'
    set -l work $HOME/.claude
    set -l pers $HOME/.claude-personal
    set -l src
    set -l dst
    set -l srcname
    set -l dstname

    switch "$argv[1]"
        case work-to-personal
            set src $work
            set dst $pers
            set srcname work
            set dstname personal
        case personal-to-work
            set src $pers
            set dst $work
            set srcname personal
            set dstname work
        case '*'
            echo "Usage: claude-profiles-sync work-to-personal|personal-to-work"
            echo "Syncs settings.json, settings.local.json and the plugins directory."
            echo
            set -l d (__claude_profile_divergence)
            if test (count $d) -gt 0
                echo "Currently diverged: "(string join ', ' $d)
            else
                echo "Profiles are currently in sync."
            end
            return 1
    end

    set -l d (__claude_profile_divergence)
    if test (count $d) -eq 0
        echo "Profiles are already in sync — nothing to do."
        return 0
    end
    echo "Diverged: "(string join ', ' $d)

    read -l -P "Overwrite $dstname's settings & plugins with $srcname's? [y/N] " reply
    if not string match -qi y -- "$reply"
        echo "Aborted."
        return 1
    end

    # Back up what's about to be overwritten
    set -l bak $dst/backups/profile-sync-(date +%Y%m%d-%H%M%S)
    mkdir -p $bak
    for f in settings.json settings.local.json
        test -e $dst/$f; and cp -a $dst/$f $bak/
    end
    test -e $dst/plugins/installed_plugins.json
    and cp -a $dst/plugins/installed_plugins.json $bak/plugins-installed_plugins.json

    for f in settings.json settings.local.json
        if test -e $src/$f
            cp -a $src/$f $dst/$f
        else if test -e $dst/$f
            rm $dst/$f # source profile deleted it; backup kept in $bak
        end
    end

    if test -d $src/plugins
        rsync -a --delete $src/plugins/ $dst/plugins/
        # The plugin registry stores absolute installPaths — repoint them at the destination
        for j in $dst/plugins/*.json
            sed -i "s|$src/plugins|$dst/plugins|g" $j
        end
    end

    set -l after (__claude_profile_divergence)
    if test (count $after) -eq 0
        echo "Synced $srcname → $dstname. Profiles are now in sync. (backup: $bak)"
    else
        echo "Sync ran, but still diverged: "(string join ', ' $after)" (backup: $bak)"
        return 1
    end
end

function __claude_run
    set -l profile $argv[1]
    set -l rest $argv[2..]
    echo $profile >$HOME/.claude-last-profile

    set -l diverged (__claude_profile_divergence)
    if test (count $diverged) -gt 0
        set_color --bold yellow
        echo "⚠  Claude work/personal profiles have diverged: "(string join ', ' $diverged)
        set_color normal
        echo "   Run 'claude-profiles-diff' to inspect or 'claude-profiles-sync' to reconcile."
        sleep 2 # fullscreen TUI hides the terminal right after launch — keep the warning readable
    end

    if test "$profile" = personal
        CLAUDE_CONFIG_DIR=$HOME/.claude-personal command claude $rest
    else
        # Work = stock behavior: no CLAUDE_CONFIG_DIR, so state stays at ~/.claude.json.
        # (Setting it, even to ~/.claude, makes claude look for .claude.json INSIDE the dir.)
        env -u CLAUDE_CONFIG_DIR claude $rest
    end
end

function claude-work --wraps claude --description 'Claude Code (work account)'
    __claude_run work $argv
end

function claude-personal --wraps claude --description 'Claude Code (personal account)'
    __claude_run personal $argv
end

function claude --wraps claude --description 'Claude Code (last-used account)'
    set -l profile work
    if test -f $HOME/.claude-last-profile
        set -l saved (string trim <$HOME/.claude-last-profile)
        test "$saved" = personal; and set profile personal
    end
    __claude_run $profile $argv
end
