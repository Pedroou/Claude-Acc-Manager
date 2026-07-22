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
# Session/chat history (projects/, file-history/, history.jsonl) is 100%
# shared: it lives in ~/.claude and the personal profile symlinks to it, so
# /resume shows the same sessions from either account.

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

# Union of two prompt-history jsonl files, deduped, ordered by timestamp.
# Prints to stdout; caller redirects. Falls back to plain union order if the
# files contain anything jq can't parse.
function __claude_merge_history -a af bf
    set -l tmp (mktemp)
    begin
        cat $af 2>/dev/null
        cat $bf 2>/dev/null
    end | awk '!seen[$0]++' >$tmp
    if not jq -sc 'sort_by(.timestamp // 0)[]' $tmp 2>/dev/null
        cat $tmp
    end
    rm -f $tmp
end

# Share one state directory (projects/, file-history/) between profiles: merge
# personal's copy into work's (union; newer file wins, overwritten work files
# are backed up), park the merged-away personal dir under backups/, and leave a
# symlink behind. Self-healing like __claude_share_settings_local: if anything
# ever replaces the symlink with a real directory, the next launch merges it
# back and restores the link. No-op if already a symlink or no personal profile.
function __claude_share_state_dir -a rel
    set -l work (__claude_work_dir)
    set -l pers_dir (__claude_pers_dir)
    set -l src $work/$rel
    set -l dst $pers_dir/$rel

    test -d $pers_dir; or return 0
    test -L $dst; and return 0

    mkdir -p $src
    if test -d $dst
        command -q rsync; or begin
            echo "⚠  rsync not found; cannot share $rel between profiles" >&2
            return 1
        end
        set -l stamp (date +%Y%m%d-%H%M%S)
        mkdir -p $work/backups $pers_dir/backups
        rsync -a --update --backup --backup-dir=$work/backups/$rel-overwritten-$stamp $dst/ $src/
        and mv $dst $pers_dir/backups/$rel-merged-$stamp
        or return 1
    end
    ln -s $src $dst
end

# Share history.jsonl (prompt history) the same way: merge once, then symlink.
function __claude_share_history_file
    set -l work (__claude_work_dir)
    set -l pers_dir (__claude_pers_dir)
    set -l wh $work/history.jsonl
    set -l ph $pers_dir/history.jsonl

    test -d $pers_dir; or return 0
    test -L $ph; and return 0

    if test -e $ph
        __claude_merge_history $wh $ph >$wh.tmp
        and mv $wh.tmp $wh
        and rm $ph
        or begin
            rm -f $wh.tmp
            return 1
        end
    else if not test -e $wh
        touch $wh
    end
    ln -s $wh $ph
end

# Session/chat history is fully shared between profiles: transcripts + memory
# (projects/), checkpoint data for /rewind (file-history/), and the prompt
# history (history.jsonl) all live in the work profile; personal holds symlinks.
# /resume therefore lists the same sessions from either profile.
function __claude_share_sessions
    __claude_share_state_dir projects
    __claude_share_state_dir file-history
    __claude_share_history_file
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

function __claude_last_profile
    set -l p work
    if test -f $HOME/.claude-last-profile
        test (string trim <$HOME/.claude-last-profile) = personal; and set p personal
    end
    echo $p
end

# Pre-launch reconcile. LAST is the sync source of truth (the previously-run
# profile); the other profile is the destination. Does not record last-profile
# or launch — that stays in __claude_run so the current launch is never its own
# source. Non-interactive shells get a one-line hint and never block.
function __claude_prelaunch -a launched last
    __claude_share_settings_local
    __claude_share_sessions

    set -l diverged (__claude_profile_divergence)
    test (count $diverged) -gt 0; or return 0

    set -l dst personal
    test $last = personal; and set dst work
    set -l dir "$last-to-$dst"

    set_color --bold yellow
    echo "⚠  Shared config drifted: "(string join ', ' $diverged)
    set_color normal

    if isatty stdin
        read -l -P "   Sync $last→$dst now? [Y/n] " reply
        if string match -qi 'n*' -- "$reply"
            echo "   Skipped. Run 'claude-profiles-sync $dir' when you want to reconcile."
        else
            claude-profiles-sync $dir
        end
    else
        echo "   Run 'claude-profiles-sync $dir' to reconcile."
    end
end

function __claude_run
    set -l profile $argv[1]
    set -l rest $argv[2..]

    # Source of truth = the profile run LAST (before this launch overwrites it).
    # If the marker is absent (first ever launch), default to the launched one.
    set -l last $profile
    test -f $HOME/.claude-last-profile; and set last (__claude_last_profile)

    __claude_prelaunch $profile $last

    # Only now record the current launch, so it is never its own sync source.
    echo $profile >$HOME/.claude-last-profile

    if test "$profile" = personal
        CLAUDE_CONFIG_DIR=(__claude_pers_dir) command claude $rest
    else
        # Work = stock behavior: no CLAUDE_CONFIG_DIR, so state stays at ~/.claude.json.
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
