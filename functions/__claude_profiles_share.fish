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
# replaced the link with a copy. If the shared side has none, the copy simply
# moves over. If it has one, a directory of sessions is merged into it, so no
# conversation drops out of /resume; anything else is set aside in
# ~/.claude/backups, to be looked at rather than guessed about.
function __claude_profiles_share -a dir
    set -l hub $HOME/.claude
    set -l name (string replace $HOME/.claude- '' -- $dir)
    set -l backup
    set -l merged
    set -l aside
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
            # Nothing on the shared side, so it only moves - which is safe even
            # with a session running: a move within a filesystem leaves open
            # files open, and anything opened afterwards resolves through the link.
            mkdir -p $hub
            mv -T $here $there 2>/dev/null; and ln -sT $there $here
            or test -L $here # a launch alongside this one did it first
            or set -a failed $entry
            continue
        end

        # Both sides have one. Moving this one away pulls files out from under
        # any session that has them open, so it waits until nothing is running.
        if __claude_profiles_running $dir >/dev/null
            set -a waiting $entry
            continue
        end

        set -q backup[1]; or set backup $hub/backups/profiles-(date +%Y%m%d-%H%M%S)-$name
        if contains -- $entry projects file-history todos plans; and test -d $here -a -d $there
            # Sessions: everything this profile had joins the shared copy. A
            # file both sides have keeps the newer version, and the other is in
            # the backup - the second pass, run the other way, is what saves
            # this side's version wherever the shared one was newer.
            command -q rsync
            and rsync -a --update --backup --backup-dir=$backup/$entry $here/ $there/
            and rsync -a --existing --update --backup --backup-dir=$backup/$entry $there/ $here/
            and rm -rf $here
            and ln -sT $there $here
            and set -a merged $entry
            or set -a failed $entry
        else
            mkdir -p $backup
            and mv -T $here $backup/$entry
            and ln -sT $there $here
            and set -a aside $entry
            or set -a failed $entry
        end
    end

    __claude_profiles_repoint $dir/plugins/ $hub/plugins/

    if set -q merged[1]
        echo "claude-profiles: merged $name's own "(string join ', ' $merged)" into the shared copy." >&2
    end
    if set -q aside[1]
        echo "claude-profiles: $name had its own "(string join ', ' $aside)"; it now uses the shared one." >&2
    end
    if test -d "$backup"
        echo "                 Anything that was replaced is in $backup" >&2
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

# Point the plugin registries' paths at the shared copy rather than through a
# profile. Claude Code records absolute paths, and a plugin installed or updated
# from a profile is recorded through that profile's link -
# ~/.claude-work/plugins/cache/… - which works until the profile is renamed or
# removed. Costs a string match per launch; jq only runs when there is something
# to fix.
function __claude_profiles_repoint -a from to
    for registry in $to/installed_plugins.json $to/known_marketplaces.json
        test -f $registry; or continue
        string match -q -- "*\"$from*" (string collect <$registry); or continue
        set -l tmp $registry.$fish_pid.tmp
        jq --arg from $from --arg to $to '
            walk(if type == "string" and startswith($from)
                 then $to + .[($from | length):] else . end)' $registry >$tmp
        and mv $tmp $registry
        or rm -f $tmp
    end
end
