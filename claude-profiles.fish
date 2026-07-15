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

# Canonical (sorted, compact) JSON with volatile keys stripped, for comparison.
function __claude_shared -a f
    jq -Sc 'del(.model, .effortLevel, .advisorModel, .tui)' $f 2>/dev/null; or echo '{}'
end

function __claude_plugin_keys -a dir
    jq -r '.plugins | keys | sort | join(",")' $dir/plugins/installed_plugins.json 2>/dev/null
end

function __claude_profile_divergence
    set -l work (__claude_work_dir)
    set -l pers (__claude_pers_dir)
    set -l diffs

    # settings.json: compare only the shared surface (volatile keys stripped).
    # Assign to a local first: a command substitution that yields no output makes
    # a `set -l` var an empty list, and "$var" then expands to a single empty-string
    # argument — avoiding the zero-argument breakage of bare `test (cmd) != (cmd)`.
    # This idiom works on all supported fish versions (3.2+), unlike `"$(cmd)"`.
    if test -e $work/settings.json; or test -e $pers/settings.json
        set -l ws (__claude_shared $work/settings.json)
        set -l ps (__claude_shared $pers/settings.json)
        if test "$ws" != "$ps"
            set -a diffs settings.json
        end
    end

    # settings.local.json is shared via symlink (§4) — never compared here.

    # Plugin registry key list only; the cache is never inspected.
    set -l wp (__claude_plugin_keys $work)
    set -l pp (__claude_plugin_keys $pers)
    if test "$wp" != "$pp"
        set -a diffs plugins
    end

    string join \n $diffs
end

# Merge for sync: result = SRC's non-volatile keys + DST's own volatile keys.
# Volatile keys therefore never cross profiles in either direction. Missing
# files are treated as {}. Prints to stdout; caller redirects.
function __claude_merge_settings -a srcf dstf
    begin
        cat $srcf 2>/dev/null; or echo '{}'
        echo
        cat $dstf 2>/dev/null; or echo '{}'
    end | jq -s '
        (.[0] | del(.model, .effortLevel, .advisorModel, .tui)) as $shared
        | (.[1] | {model, effortLevel, advisorModel, tui}
                | with_entries(select(.value != null))) as $vol
        | $shared + $vol
    '
end

# Repoint plugin installPaths from SRCPREFIX to DSTPREFIX (registry only; the
# cache is never copied). Prints to stdout; caller redirects.
function __claude_rewrite_registry -a regf srcprefix dstprefix
    jq --arg s "$srcprefix" --arg d "$dstprefix" '
        .plugins |= with_entries(
            if (.value | type == "object")
               and ((.value.installPath? // "") | startswith($s))
            then .value.installPath = ($d + (.value.installPath[($s | length):]))
            else . end)
    ' $regf
end

# Union two settings.local.json permission sets (A is the base). Dedupes the
# allow/deny/ask arrays and drops any that end up empty. Prints to stdout.
function __claude_merge_permissions -a af bf
    begin
        cat $af 2>/dev/null; or echo '{}'
        echo
        cat $bf 2>/dev/null; or echo '{}'
    end | jq -s '
        def U(x; y): ((x // []) + (y // []) | unique);
        (.[0]) as $a | (.[1]) as $b
        | (($a.permissions // {}) * ($b.permissions // {})) as $mp
        | $a * {permissions: ($mp + {
              allow: U($a.permissions.allow; $b.permissions.allow),
              deny:  U($a.permissions.deny;  $b.permissions.deny),
              ask:   U($a.permissions.ask;   $b.permissions.ask)
          })}
        | .permissions |= with_entries(
              select((.value | type != "array") or (.value | length > 0)))
    '
end

# Make personal/settings.local.json a symlink to work/settings.local.json so
# the permission allowlist is one shared file. Self-healing: if a write ever
# replaced the symlink with a regular file, its grants are unioned back into the
# shared file and the symlink restored. No-op if already a symlink or if there
# is no personal profile yet. Local and race-free (touches only these paths).
function __claude_share_settings_local
    set -l work (__claude_work_dir)/settings.local.json
    set -l pers_dir (__claude_pers_dir)
    set -l pers $pers_dir/settings.local.json

    test -d $pers_dir; or return 0        # no personal profile yet
    test -L $pers; and return 0           # already shared

    if not test -e $work
        # No shared target yet: adopt personal's file if present, else create empty.
        mkdir -p (__claude_work_dir)
        if test -e $pers
            mv $pers $work
        else
            echo '{"permissions":{}}' >$work
        end
    else if test -e $pers
        # Both exist: union personal's grants into the shared file, then drop it.
        __claude_merge_permissions $work $pers >$work.tmp
        and mv $work.tmp $work
        and rm $pers
    end

    ln -s $work $pers
end

function claude-profiles-diff --description 'Show shared-config differences between work and personal Claude profiles'
    set -l work (__claude_work_dir)
    set -l pers (__claude_pers_dir)
    set -l found 0

    if test (__claude_shared $work/settings.json) != (__claude_shared $pers/settings.json)
        set found 1
        set_color --bold; echo "── settings.json (shared keys; model/effort/advisor/tui ignored) ──"; set_color normal
        diff -u --label work --label personal \
            (jq -S 'del(.model, .effortLevel, .advisorModel, .tui)' $work/settings.json 2>/dev/null | psub) \
            (jq -S 'del(.model, .effortLevel, .advisorModel, .tui)' $pers/settings.json 2>/dev/null | psub)
    end

    set -l wplugins (jq -r '.plugins | keys[]' $work/plugins/installed_plugins.json 2>/dev/null | sort)
    set -l pplugins (jq -r '.plugins | keys[]' $pers/plugins/installed_plugins.json 2>/dev/null | sort)
    for p in $wplugins
        if not contains -- $p $pplugins
            set found 1; echo "plugin only in work:     $p"
        end
    end
    for p in $pplugins
        if not contains -- $p $wplugins
            set found 1; echo "plugin only in personal: $p"
        end
    end

    echo "(settings.local.json is shared between profiles — no diff.)"
    test $found = 0; and echo "Profiles are in sync (shared settings.json + plugin list)."
end

function claude-profiles-sync --description 'Reconcile shared config from one Claude profile to the other'
    set -l work (__claude_work_dir)
    set -l pers (__claude_pers_dir)
    set -l src; set -l dst; set -l srcname; set -l dstname

    switch "$argv[1]"
        case work-to-personal
            set src $work; set dst $pers; set srcname work; set dstname personal
        case personal-to-work
            set src $pers; set dst $work; set srcname personal; set dstname work
        case '*'
            echo "Usage: claude-profiles-sync work-to-personal|personal-to-work"
            echo "Copies settings.json's shared keys (model/effort/advisor/tui kept per-profile)"
            echo "and the plugin registry. The plugin cache is never copied; settings.local.json"
            echo "is shared and needs no sync."
            echo
            set -l d (__claude_profile_divergence)
            if test (count $d) -gt 0
                echo "Currently drifted: "(string join ', ' $d)
            else
                echo "Profiles are in sync."
            end
            return 1
    end

    set -l stamp (date +%Y%m%d-%H%M%S)
    set -l bak $dst/backups/profile-sync-$stamp
    mkdir -p $bak

    # settings.json — key-merge, preserving dst's volatile keys.
    if test -e $src/settings.json
        test -e $dst/settings.json; and cp -a $dst/settings.json $bak/
        __claude_merge_settings $src/settings.json $dst/settings.json >$dst/settings.json.tmp
        and mv $dst/settings.json.tmp $dst/settings.json
        echo "↺ settings.json: $srcname → $dstname (shared keys; $dstname's model/effort/tui kept)"
    end

    # plugin registry only — repoint installPaths; the cache re-fetches on demand.
    set -l reg plugins/installed_plugins.json
    if test -e $src/$reg
        mkdir -p $dst/plugins
        test -e $dst/$reg; and cp -a $dst/$reg $bak/plugins-installed_plugins.json
        __claude_rewrite_registry $src/$reg "$src/plugins" "$dst/plugins" >$dst/$reg.tmp
        and mv $dst/$reg.tmp $dst/$reg
        echo "↺ plugins registry: $srcname → $dstname (cache re-fetched on demand)"
    end

    echo "   backup: $bak"
    set -l after (__claude_profile_divergence)
    if test (count $after) -eq 0
        echo "Profiles are now in sync."
    else
        echo "Still drifted: "(string join ', ' $after)
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
