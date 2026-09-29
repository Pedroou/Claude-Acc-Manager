# Make a profile share everything that isn't about its account with the default
# profile. Runs before every launch, for every profile but the default; it is
# idempotent, and silent unless it actually did something.
#
# Sharing means one copy, in ~/.claude, and a symlink to it in the profile. It
# covers what you wrote and what you did:
#
#   yours     CLAUDE.md rules agents commands skills output-styles
#             keybindings.json plugins
#   history   projects (transcripts and memory, so /resume sees every session)
#             file-history (/rewind) history.jsonl (the up-arrow)
#             paste-cache image-cache (what history.jsonl points into)
#             todos plans
#
# Everything else in a profile directory stays its own: the login, Claude
# Code's state file, the live session registry, org-managed settings, caches.
# settings.json is the one thing in between, and __claude_profiles_merge owns it.
#
# A link, once made, is never touched again - whether it points here or
# somewhere you chose. What needs work is a real file or directory where the
# link belongs: a profile from before it was shared, or one where something
# replaced the link with a copy. Then the copy is moved over if the shared side
# has none, or merged into it if it has, and the link takes its place.
function __claude_profiles_share -a dir
    set -l hub $HOME/.claude
    set -l name (string replace $HOME/.claude- '' -- $dir)
    set -l backup
    set -l merged
    set -l waiting
    set -l failed

    for entry in CLAUDE.md rules agents commands skills output-styles keybindings.json plugins \
            projects file-history history.jsonl paste-cache image-cache todos plans
        set -l here $dir/$entry
        set -l there $hub/$entry

        test -L $here; and continue

        # -T throughout: never move into, or link inside, a directory that
        # another launch running at the same moment has just put in place.
        if not test -e $here
            test -e $there; and ln -sT $there $here 2>/dev/null
            continue
        end

        if not test -e $there
            # Nothing to merge with, so it only moves - which is safe even with
            # a session running: a move within a filesystem leaves open files
            # open, and anything opened afterwards resolves through the link.
            mkdir -p $hub
            mv -T $here $there 2>/dev/null; and ln -sT $there $here
            or test -L $here # a launch alongside this one did it first
            or set -a failed $entry
            continue
        end

        # Both sides have one. A merge swaps out files a running session may be
        # holding open, so it waits until nothing is running in this profile.
        if __claude_profiles_running $dir >/dev/null
            set -a waiting $entry
            continue
        end

        set -q backup[1]; or set backup $hub/backups/profiles-(date +%Y%m%d-%H%M%S)-$name
        if __claude_profiles_adopt $entry $here $there $backup
            ln -sT $there $here
            set -a merged $entry
        else
            set -a failed $entry
        end
    end

    if set -q merged[1]
        echo "claude-profiles: merged $name's own "(string join ', ' $merged)" into the shared copy." >&2
        # The backup only exists if a merge had to choose between two versions.
        test -d "$backup"; and echo "                 Versions it replaced are in $backup" >&2
    end
    if set -q waiting[1]
        echo "claude-profiles: $name has its own "(string join ', ' $waiting)"; it joins the shared copy" >&2
        echo "                 the next time nothing is running in $name." >&2
    end
    if set -q failed[1]
        echo "claude-profiles: couldn't share "(string join ', ' $failed)" for $name; it keeps its own for now." >&2
        return 1
    end
end

# Merge a profile's own copy of an entry into the shared one, leaving nothing
# behind at `here`. Nothing is lost: where two versions of the same file differ,
# the newer one is kept and the other goes to `backup`, at the same relative path.
function __claude_profiles_adopt -a entry here there backup
    set -l tmp $there.$fish_pid.tmp

    if test "$entry" = history.jsonl
        # Prompt history is a log, so both halves are kept: the union of the
        # lines, back in time order. Sessions in other profiles append to the
        # shared file as this runs, so if it grew meanwhile, the merge is
        # simply done again - a line typed during it is never dropped.
        for attempt in 1 2 3
            set -l before (stat -c '%.9Y %s' $there)
            awk '!seen[$0]++' $there $here >$tmp.union
            or return 1
            jq -c -s 'sort_by(.timestamp // 0)[]' $tmp.union >$tmp 2>/dev/null
            or cp $tmp.union $tmp # a line jq can't read: keep the union as it is
            rm -f $tmp.union
            if test "$before" = "$(stat -c '%.9Y %s' $there)"
                mv $tmp $there; and rm $here
                return
            end
        end
        rm -f $tmp
        return 1
    end

    if test "$entry" = plugins
        __claude_profiles_adopt_plugins $here $there $backup; and rm -rf $here
        return
    end

    if test -d $here -a -d $there
        if not command -q rsync
            echo "claude-profiles: merging $entry needs rsync, which isn't installed." >&2
            return 1
        end
        # Two passes into one backup directory. The first brings over every file
        # that is newer here, saving the shared version it replaces; the second
        # runs the other way over the files both sides have, which saves this
        # side's version wherever the shared one was newer. Between them, every
        # version that loses ends up in the backup - and only those.
        rsync -a --update --backup --backup-dir=$backup/$entry $here/ $there/
        and rsync -a --existing --update --backup --backup-dir=$backup/$entry $there/ $here/
        and rm -rf $here
        return
    end

    if test -f $here -a -f $there
        if cmp -s $here $there
            rm $here
        else if test (path mtime $here) -gt (path mtime $there)
            # Copied to the backup rather than moved, so the shared file is
            # replaced in one step and never missing in between.
            mkdir -p (path dirname $backup/$entry); and cp -p $there $backup/$entry
            and mv $here $there
        else
            mkdir -p (path dirname $backup/$entry); and mv $here $backup/$entry
        end
        return
    end

    # A file on one side and a directory on the other: nothing sensible to merge,
    # so this side's is set aside and the shared one stands.
    mkdir -p (path dirname $backup/$entry); and mv $here $backup/$entry
end

# Plugins are mostly a cache - git checkouts Claude Code fetches again whenever
# one is missing - so a profile's own plugin directory is not merged file by
# file. What is kept is what can't be fetched again without you: the entries in
# its two registries the shared one lacks (a plugin, or a marketplace, you only
# installed there), with their files moved over and their paths rewritten, and
# the plugins' own data, merged like any other directory.
function __claude_profiles_adopt_plugins -a here there backup
    for spec in installed_plugins.json:plugins known_marketplaces.json
        set -l parts (string split : -- $spec)
        set -l file $parts[1]
        set -l at '[]'
        set -q parts[2]; and set at '["'$parts[2]'"]'
        test -f $here/$file; or continue

        set -l theirs $there/$file
        test -f $theirs; or set theirs /dev/null # slurps to [], so $hub[0] is null
        set -l args --argjson at $at --arg from $here/ --arg to $there/ \
            --slurpfile hub $theirs --slurpfile mine $here/$file
        # The shared registry, or this one emptied if there isn't a shared one,
        # and the entries only this profile has, under whichever key holds them.
        set -l common '($hub[0] // ($mine[0] | setpath($at; {}))) as $base
            | ($mine[0] | getpath($at) // {}
               | with_entries(select(.key as $k | $base | getpath($at) // {} | has($k) | not))
              ) as $only_here'

        for from in (jq -n -r $args "$common
                | [\$only_here | .. | strings | select(startswith(\$from))] | unique[]")
            set -l to (string replace -- $here/ $there/ $from)
            if test -e $from -a ! -e $to
                mkdir -p (path dirname $to); and mv $from $to
            end
        end

        jq -n $args "$common
            | \$only_here | walk(if type == \"string\" and startswith(\$from)
                                 then \$to + .[(\$from | length):] else . end) as \$new
            | \$base | setpath(\$at; (getpath(\$at) // {}) + \$new)" >$there/$file.$fish_pid.tmp
        and mv $there/$file.$fish_pid.tmp $there/$file
        or begin
            rm -f $there/$file.$fish_pid.tmp
            return 1
        end
    end

    test -d $here/data; or return 0
    if test -d $there/data
        __claude_profiles_adopt plugins/data $here/data $there/data $backup
    else
        mv -T $here/data $there/data
    end
end
