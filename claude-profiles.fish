# Claude Code account profiles
#   claude-work          → work account   (stock setup: ~/.claude + ~/.claude.json)
#   claude-personal      → personal account (~/.claude-personal)
#   claude               → whichever profile was launched last (sticky),
#                          remembered in ~/.claude-last-profile; falls back to work.
#   claude-profiles-diff → show what differs between the two profiles
#   claude-profiles-sync → force a one-way copy of settings + plugins
# All flags are forwarded, so `claude-personal -r`, `claude -c`, etc. work.
#
# AUTO-SYNC: on launch, config drift between the two profiles is reconciled
# automatically — per file, the newer mtime wins. This only happens once the
# personal profile is SEEDED (see __claude_profiles_seeded); before that a
# fresh, near-empty profile would look "newest" and could overwrite a real one.
# Every candidate copy must also pass the guards in __claude_autosync_guard.
# Anything a guard rejects falls back to the old behavior: warn, and let the
# user reconcile by hand. Set CLAUDE_PROFILES_NO_AUTOSYNC=1 to disable.

# Where this repo lives, resolved through the conf.d symlink so we can find
# seed-personal.fish at launch time. Unlike the profile dirs this path is static,
# so caching it at source time is fine; tests override it by pre-setting the var.
set -q __claude_profiles_dir; or set -g __claude_profiles_dir (dirname (realpath (status filename)))

# Profile dirs are derived from $HOME on every call, never cached in a global:
# a cached global is captured at load time and silently ignores a later $HOME,
# which makes the whole thing untestable and would point sync at the wrong dirs.
function __claude_work_dir
    echo $HOME/.claude
end

function __claude_pers_dir
    echo $HOME/.claude-personal
end

# ── divergence detection ────────────────────────────────────────────────────

function __claude_profile_divergence
    set -l work (__claude_work_dir)
    set -l pers (__claude_pers_dir)
    set -l diffs

    for f in settings.json settings.local.json
        if test -e $work/$f; or test -e $pers/$f
            if not cmp -s $work/$f $pers/$f 2>/dev/null
                set -a diffs $f
            end
        end
    end

    if test (__claude_plugin_list $work) != (__claude_plugin_list $pers)
        set -a diffs plugins
    end

    string join \n $diffs
end

function __claude_plugin_list
    jq -r '.plugins | keys | sort | join(",")' $argv[1]/plugins/installed_plugins.json 2>/dev/null
end

# The personal profile only becomes an eligible sync SOURCE once it has been
# seeded from the work profile. A profile that has merely been logged into is
# still at first-run defaults: its config is newest on disk but nearly empty,
# and letting it win on mtime would wipe the real profile.
function __claude_profiles_seeded
    set -l pers (__claude_pers_dir)
    test -f $HOME/.claude.json
    and test -f $pers/.credentials.json
    and test -f $pers/.claude.json
    and test -f $pers/.profile-seeded
end

# ── auto-sync ───────────────────────────────────────────────────────────────

# Top-level key count of a JSON object; -1 if unreadable / not an object.
function __claude_json_keys
    test -e $argv[1]; or begin
        echo -1
        return
    end
    jq -e 'if type == "object" then (keys | length) else empty end' $argv[1] 2>/dev/null
    or echo -1
end

# Guards deciding whether $src may overwrite $dst. mtime says which file is
# NEWER; these say whether it is PLAUSIBLE. Echoes a reason and returns 1 when
# the copy must be refused. Direction-agnostic: protects work from a hollow
# personal profile and vice versa, because it inspects content, not identity.
function __claude_autosync_guard -a src dst label
    set -l sk (__claude_json_keys $src)
    set -l dk (__claude_json_keys $dst)

    # Source must be readable, well-formed JSON.
    if test $sk -lt 0
        echo "$label is missing or not valid JSON"
        return 1
    end

    # Nothing to protect if the destination has no real content.
    test $dk -le 0; and return 0

    # Never replace a populated config with an empty one.
    if test $sk -eq 0
        echo "it is empty ($dk entries would be lost)"
        return 1
    end

    # Shrink guard: refuse a source that drops >half the destination's entries.
    if test (math "$sk * 2") -lt $dk
        echo "shrink guard: $sk entries vs $dk (>half would be lost)"
        return 1
    end

    return 0
end

function __claude_autosync_refuse -a what why
    set -a __claude_autosync_refused $what
    set_color --bold yellow
    echo "⚠  auto-sync skipped $what — $why"
    set_color normal
end

# Back up $dstdir/$item into this launch's backup dir before overwriting it.
# For plugins this saves ONLY the registry JSONs: plugins/ also holds the plugin
# cache (hundreds of MB of git checkouts), and copying that on every launch would
# pile up gigabytes. The checkouts are re-fetchable; the registry is what matters.
function __claude_autosync_backup -a dstdir item
    set -l bak $dstdir/backups/profile-sync-$__claude_autosync_stamp
    if test "$item" = plugins
        mkdir -p $bak/plugins
        for j in $dstdir/plugins/*.json
            test -e $j; and cp -a $j $bak/plugins/
        end
    else
        mkdir -p $bak
        test -e $dstdir/$item; and cp -a $dstdir/$item $bak/
    end
    contains -- $bak $__claude_autosync_backups
    or set -a __claude_autosync_backups $bak
end

# Pick the newer of work/personal for $f. Sets __src to work|personal.
# Returns 1 when there is nothing to do or no safe way to choose.
function __claude_autosync_pick -a f
    set -l wf (__claude_work_dir)/$f
    set -l pf (__claude_pers_dir)/$f

    # Absent on both sides, or already identical → nothing to do.
    test -e $wf; or test -e $pf; or return 1
    cmp -s $wf $pf 2>/dev/null; and return 1

    # Present on only one side: that side is the source. Auto-sync only ever
    # ADDS a missing file — it never deletes one to mirror an absence.
    if not test -e $pf
        set -g __src work
        return 0
    else if not test -e $wf
        set -g __src personal
        return 0
    end

    set -l wm (stat -c %Y $wf)
    set -l pm (stat -c %Y $pf)
    if test $wm -gt $pm
        set -g __src work
    else if test $pm -gt $wm
        set -g __src personal
    else
        # Same mtime, different content — mtime can't break the tie.
        __claude_autosync_refuse $f "both copies have the same timestamp"
        return 1
    end
end

function __claude_autosync_file -a f
    __claude_autosync_pick $f; or return

    if test $__src = work
        __claude_autosync_apply $f work personal (__claude_work_dir) (__claude_pers_dir)
    else
        __claude_autosync_apply $f personal work (__claude_pers_dir) (__claude_work_dir)
    end
end

function __claude_autosync_apply -a f srcname dstname srcdir dstdir
    set -l why (__claude_autosync_guard $srcdir/$f $dstdir/$f "$srcname/$f")
    if test $status -ne 0
        __claude_autosync_refuse $f "$srcname/$f is newer but $why"
        return 1
    end

    __claude_autosync_backup $dstdir $f
    cp -a $srcdir/$f $dstdir/$f
    echo "↺ $f: $srcname → $dstname ($srcname was newer)"
end

function __claude_autosync_plugins
    set -l item plugins/installed_plugins.json
    __claude_autosync_pick $item; or return

    set -l srcname $__src
    set -l dstname work
    set -l srcdir (__claude_work_dir)
    set -l dstdir (__claude_pers_dir)
    if test $srcname = work
        set dstname personal
    else
        set srcdir (__claude_pers_dir)
        set dstdir (__claude_work_dir)
    end

    # Guard on the plugin registry itself: an empty or drastically shorter
    # plugin list must not wipe a populated one.
    set -l sc (jq -e '.plugins | length' $srcdir/$item 2>/dev/null; or echo -1)
    set -l dc (jq -e '.plugins | length' $dstdir/$item 2>/dev/null; or echo 0)
    if test $sc -lt 0
        __claude_autosync_refuse plugins "$srcname's plugin registry is missing or invalid"
        return 1
    end
    if test $dc -gt 0
        if test $sc -eq 0
            __claude_autosync_refuse plugins "$srcname lists no plugins ($dc would be lost)"
            return 1
        end
        if test (math "$sc * 2") -lt $dc
            __claude_autosync_refuse plugins "shrink guard: $srcname has $sc plugins vs $dstname's $dc"
            return 1
        end
    end

    __claude_autosync_backup $dstdir plugins
    rsync -a --delete $srcdir/plugins/ $dstdir/plugins/
    # The registry stores absolute installPaths — repoint them at the destination.
    for j in $dstdir/plugins/*.json
        sed -i "s|$srcdir/plugins|$dstdir/plugins|g" $j
    end
    echo "↺ plugins: $srcname → $dstname ($srcname was newer)"
end

function __claude_autosync
    set -g __claude_autosync_stamp (date +%Y%m%d-%H%M%S)
    set -g __claude_autosync_backups
    set -g __claude_autosync_refused

    for f in settings.json settings.local.json
        __claude_autosync_file $f
    end
    __claude_autosync_plugins

    for b in $__claude_autosync_backups
        echo "   backup: $b"
    end

    # Anything the guards refused is left for the user to reconcile by hand.
    if test (count $__claude_autosync_refused) -gt 0
        echo "   Run 'claude-profiles-diff' to inspect or 'claude-profiles-sync' to force a direction."
        sleep 2 # the fullscreen TUI wipes the terminal on launch — keep this readable
    end
end

# ── user-facing commands ────────────────────────────────────────────────────

function claude-profiles-diff --description 'Show config differences between work and personal Claude profiles'
    set -l work (__claude_work_dir)
    set -l pers (__claude_pers_dir)
    set -l found 0

    for f in settings.json settings.local.json
        if not cmp -s $work/$f $pers/$f 2>/dev/null
            set found 1
            set_color --bold
            echo "── $f (work vs personal) ──"
            set_color normal
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

function claude-profiles-sync --description 'Force-copy settings + plugins from one Claude profile to the other'
    set -l work (__claude_work_dir)
    set -l pers (__claude_pers_dir)
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
            echo "Forces a one-way copy of settings.json, settings.local.json and plugins,"
            echo "overriding the automatic newest-wins sync and its safety guards."
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

# ── launchers ───────────────────────────────────────────────────────────────

# Called on launch when the personal profile exists but auto-sync isn't armed.
# Walks the user through enabling it instead of making them find and run
# seed-personal.fish by hand. States handled:
#   • personal not logged in    → tell them to /login first (can't seed yet)
#   • declined earlier          → stay silent (marker at .autosync-declined)
#   • non-interactive shell      → brief hint, never block on a prompt
#   • otherwise                  → prompt; on yes, run the seed script for them
function __claude_maybe_offer_seed
    set -l pers (__claude_pers_dir)
    test -d $pers; or return # no personal profile at all yet — nothing to offer

    if not test -f $pers/.credentials.json; or not test -f $pers/.claude.json
        echo "ℹ  Personal profile exists but isn't logged in — run 'claude-personal' and /login, then relaunch to enable auto-sync."
        return
    end

    test -f $pers/.autosync-declined; and return # user said no; don't nag

    # Never block a non-interactive launch (scripts, IDE shells) on a prompt.
    if not isatty stdin
        echo "ℹ  Personal profile not seeded — auto-sync is off. Run '$__claude_profiles_dir/seed-personal.fish' to enable it."
        return
    end

    set_color --bold
    echo "Your work and personal Claude profiles aren't syncing yet."
    set_color normal
    echo "Enabling it seeds personal from work (settings, plugins, session history),"
    echo "then reconciles config drift automatically on every launch (newest wins,"
    echo "with guards so an empty profile can't wipe a full one)."
    read -l -P "Enable auto-sync now? [y/N] " reply

    if string match -qi y -- "$reply"
        set -l seed $__claude_profiles_dir/seed-personal.fish
        if test -f $seed
            fish $seed
        else
            echo "Couldn't find seed-personal.fish (looked in $__claude_profiles_dir)."
            echo "Run it by hand from the repo you cloned."
        end
    else
        touch $pers/.autosync-declined
        echo "Left off. To enable it later, run '$__claude_profiles_dir/seed-personal.fish'"
        echo "(or delete $pers/.autosync-declined to be asked again)."
    end
end

function __claude_run
    set -l profile $argv[1]
    set -l rest $argv[2..]
    echo $profile >$HOME/.claude-last-profile

    if __claude_profiles_seeded
        if not set -q CLAUDE_PROFILES_NO_AUTOSYNC
            __claude_autosync
        else if test (count (__claude_profile_divergence)) -gt 0
            set_color --bold yellow
            echo "⚠  Claude profiles have diverged (auto-sync disabled): "(string join ', ' (__claude_profile_divergence))
            set_color normal
            sleep 2
        end
    else
        # Not seeded yet: personal holds first-run defaults, not real config, so
        # syncing either way would be wrong. Offer to seed instead of just warning.
        __claude_maybe_offer_seed
    end

    if test "$profile" = personal
        CLAUDE_CONFIG_DIR=(__claude_pers_dir) command claude $rest
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
