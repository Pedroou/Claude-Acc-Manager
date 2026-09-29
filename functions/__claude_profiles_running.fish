# How many Claude Code sessions are running in a profile right now. Prints the
# count, and succeeds only when it is more than zero.
#
# Claude Code keeps a record of each live session at <dir>/sessions/<pid>.json,
# but a session that is killed rather than closed leaves its record behind. So a
# record only counts if its process is alive *and* is still the same process:
# field 22 of /proc/<pid>/stat is the start time, and it has to match the
# record's procStart - which is what rules out a recycled pid. It is the check
# Claude Code makes on its own records.
#
# CLAUDE_PROFILES_PROC stands in for /proc under test.
function __claude_profiles_running -a dir
    set -l proc /proc
    set -q CLAUDE_PROFILES_PROC[1]; and set proc $CLAUDE_PROFILES_PROC

    set -l count 0
    for record in $dir/sessions/*.json
        set -l pid (path basename -E -- $record)
        string match -qr '^[0-9]+$' -- $pid; or continue
        test -r $proc/$pid/stat; or continue

        set -l want (string match -gr '"procStart"\s*:\s*"?([0-9]+)' <$record)
        if test -n "$want"
            # Field 2 is the command name in parentheses and may itself hold
            # spaces or parentheses, so count from after the last ')', where
            # field 22 becomes field 20.
            set -l stat (string collect <$proc/$pid/stat)
            set -l fields (string split -n ' ' -- (string replace -r '^.*\)' '' -- $stat))
            test "$fields[20]" = "$want"; or continue
        end
        set count (math $count + 1)
    end

    echo $count
    test $count -gt 0
end
