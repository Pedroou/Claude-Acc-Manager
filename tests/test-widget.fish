#!/usr/bin/env fish
# Sandbox tests for the panel widget's collector (plasmoid .../scripts/claude-sessions).
# MUST run with: fish --no-config
set -g REPO (dirname (dirname (realpath (status filename))))
set -g COLLECT $REPO/plasmoid/package/contents/scripts/claude-sessions
set -g ROOT (mktemp -d)/sandbox
set -g PASS 0
set -g FAIL 0

# Tripwire: this suite must never write into the real session registry. Its
# mtimes move on their own — every live Claude Code session rewrites its record
# every few seconds — so the check is that none of the pids this suite invents
# ever turn up there. Captured before `setup` overrides $HOME; never hardcode a
# home path, or the check has nothing to look at.
function __registry_records -a home
    find $home/.claude/sessions $home/.claude-personal/sessions \
        -name '*.json' -printf '%f\n' 2>/dev/null | sort | string join ' '
end
set -g REAL_HOME $HOME
set -g REAL_BEFORE (__registry_records $REAL_HOME)

function check -a name expected actual
    if test "$expected" = "$actual"
        set PASS (math $PASS + 1); echo "  ✓ $name"
    else
        set FAIL (math $FAIL + 1); echo "  ✗ $name"
        echo "      expected: [$expected]"
        echo "      actual:   [$actual]"
    end
end

function setup
    rm -rf $ROOT
    set -g HOME $ROOT
    set -gx CLAUDE_SESSIONS_PROC $ROOT/proc
    mkdir -p $ROOT/.claude/sessions $ROOT/.claude-personal/sessions $ROOT/proc
end

# A believable /proc/<pid>/stat: field 2 is the comm in parentheses, field 22 the
# start time in clock ticks. Fields 3..21 are placeholders.
function fake_proc -a pid starttime comm
    test -n "$comm"; or set comm claude
    mkdir -p $CLAUDE_SESSIONS_PROC/$pid
    set -l pad
    for i in (seq 18)
        set -a pad 0
    end
    echo "$pid ($comm) S "(string join ' ' $pad)" $starttime" >$CLAUDE_SESSIONS_PROC/$pid/stat
end

# Write a session record. Extra JSON fields are merged in from $argv[6..].
function record -a profile pid sstatus name cwd
    set -l dir $ROOT/.claude
    test "$profile" = personal; and set dir $ROOT/.claude-personal
    set -l extra '{}'
    test (count $argv) -ge 6; and set extra $argv[6]
    jq -n --argjson pid $pid --arg status $sstatus --arg name $name --arg cwd $cwd \
        --argjson extra $extra '
        {
            pid: $pid, sessionId: "sid-\($pid)", cwd: $cwd, name: $name,
            kind: "interactive", status: $status, version: "2.1.260",
            startedAt: 1788540000000, updatedAt: 1788543000000,
            statusUpdatedAt: 1788543000000, procStart: "\($pid)00"
        } + $extra' >$dir/sessions/$pid.json
end

function collect
    $COLLECT
end

echo "═══ Task 1: nothing running ═══"
setup
set -l out (collect)
check "total is zero" 0 (echo $out | jq '.counts.total')
check "sessions is an empty array" 0 (echo $out | jq '.sessions | length')
check "both profile dirs reported present" "work personal" (echo $out | jq -r '.profiles | join(" ")')
check "generatedAt is a millisecond stamp" 13 (echo $out | jq -r '.generatedAt | tostring | length')
# The machine running this suite normally has real sessions of its own. An empty
# sandbox reporting zero is what proves the collector honours $HOME.
check "real sessions on this machine are not reported" 0 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 2: a live session is reported ═══"
setup
record work 4001 busy proj-a /home/u/work/proj-a
fake_proc 4001 400100
set out (collect)
check "one session" 1 (echo $out | jq '.sessions | length')
check "status passed through" busy (echo $out | jq -r '.sessions[0].status')
check "state is working" working (echo $out | jq -r '.sessions[0].state')
check "label is Working" Working (echo $out | jq -r '.sessions[0].label')
check "profile is work" work (echo $out | jq -r '.sessions[0].profile')
check "directory basename extracted" proj-a (echo $out | jq -r '.sessions[0].dir')
check "counted as working" 1 (echo $out | jq '.counts.working')
check "counted in total" 1 (echo $out | jq '.counts.total')

echo
echo "═══ Task 3: dead and recycled pids are dropped ═══"
setup
record work 4002 busy gone /home/u/gone      # no /proc entry at all
record work 4003 busy recycled /home/u/recyc # /proc entry, different start time
fake_proc 4003 999999
record work 4004 idle alive /home/u/alive
fake_proc 4004 400400
set out (collect)
check "only the live session survives" 1 (echo $out | jq '.sessions | length')
check "and it is the right one" alive (echo $out | jq -r '.sessions[0].name')

echo
echo "═══ Task 4: a record with no recorded start time falls back to pid existence ═══"
setup
record work 4005 busy legacy /home/u/legacy '{"procStart": null}'
fake_proc 4005 400500
set out (collect)
check "legacy record kept" 1 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 5: comm containing spaces and parens still parses ═══"
setup
record work 4006 busy weird /home/u/weird
fake_proc 4006 400600 'cla) ude'
set out (collect)
check "start time read from after the last paren" 1 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 6: every status maps to a state, and unknown ones survive ═══"
setup
record work 4010 waiting w /home/u/w '{"waitingFor": "input needed"}'
record work 4011 busy b /home/u/b
record work 4012 shell s /home/u/s
record work 4013 idle i /home/u/i
record work 4014 hibernating h /home/u/h
for pid in 4010 4011 4012 4013 4014
    fake_proc $pid {$pid}00
end
set out (collect)
check "waiting → waiting" waiting (echo $out | jq -r '.sessions[] | select(.pid==4010) | .state')
check "busy → working" working (echo $out | jq -r '.sessions[] | select(.pid==4011) | .state')
check "shell → shell" shell (echo $out | jq -r '.sessions[] | select(.pid==4012) | .state')
check "idle → done" done (echo $out | jq -r '.sessions[] | select(.pid==4013) | .state')
check "idle reads as Done" Done (echo $out | jq -r '.sessions[] | select(.pid==4013) | .label')
check "unrecognised status kept as unknown" unknown (echo $out | jq -r '.sessions[] | select(.pid==4014) | .state')
check "unrecognised status is title-cased for display" Hibernating (echo $out | jq -r '.sessions[] | select(.pid==4014) | .label')
check "counts cover every state" "1 1 1 1 1 5" (echo $out | jq -r '.counts | "\(.waiting) \(.working) \(.shell) \(.done) \(.unknown) \(.total)"')

echo
echo "═══ Task 7: waiting sessions sort first, newest activity first within a state ═══"
setup
record work 4020 idle old-done /home/u/a '{"statusUpdatedAt": 1788543000000}'
record work 4021 busy older-work /home/u/b '{"statusUpdatedAt": 1788543000000}'
record work 4022 busy newer-work /home/u/c '{"statusUpdatedAt": 1788543999000}'
record work 4023 waiting needs-me /home/u/d '{"statusUpdatedAt": 1788542000000}'
for pid in 4020 4021 4022 4023
    fake_proc $pid {$pid}00
end
set out (collect)
check "order is waiting, newest working, older working, done" \
    "needs-me newer-work older-work old-done" \
    (echo $out | jq -r '[.sessions[].name] | join(" ")')

echo
echo "═══ Task 8: the reason a session is waiting is carried through ═══"
setup
record work 4030 waiting perm /home/u/p '{"waitingFor": "dialog open", "needs": "choose: allow or deny the Bash command"}'
record work 4031 waiting plain /home/u/q '{"waitingFor": "input needed"}'
fake_proc 4030 403000
fake_proc 4031 403100
set out (collect)
check "the specific need wins over the generic one" "choose: allow or deny the Bash command" \
    (echo $out | jq -r '.sessions[] | select(.pid==4030) | .detail')
check "falls back to waitingFor" "input needed" \
    (echo $out | jq -r '.sessions[] | select(.pid==4031) | .detail')

echo
echo "═══ Task 9: both profiles are read ═══"
setup
record work 4040 busy from-work /home/u/w
record personal 4041 idle from-personal /home/u/p
fake_proc 4040 404000
fake_proc 4041 404100
set out (collect)
check "two sessions" 2 (echo $out | jq '.sessions | length')
check "work session labelled work" work (echo $out | jq -r '.sessions[] | select(.pid==4040) | .profile')
check "personal session labelled personal" personal (echo $out | jq -r '.sessions[] | select(.pid==4041) | .profile')

echo
echo "═══ Task 10: a profile that was never created is simply absent ═══"
setup
rm -rf $ROOT/.claude-personal
record work 4050 busy solo /home/u/s
fake_proc 4050 405000
set out (collect)
check "only work reported present" work (echo $out | jq -r '.profiles | join(" ")')
check "session still reported" 1 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 11: junk in the registry never breaks the panel ═══"
setup
record work 4060 busy good /home/u/g
fake_proc 4060 406000
echo -n '{"pid": 4061, "status": "bu' >$ROOT/.claude/sessions/4061.json # torn write
fake_proc 4061 406100
echo '{"pid": 0}' >$ROOT/.claude/sessions/notapid.json # non-numeric name
echo '' >$ROOT/.claude/sessions/4062.json # empty file
fake_proc 4062 406200
set out (collect)
check "the healthy session still lands" 1 (echo $out | jq '.sessions | length')
check "and it is the good one" good (echo $out | jq -r '.sessions[0].name')
check "counts agree" 1 (echo $out | jq '.counts.total')

echo
echo "═══ Task 12: a record missing its name falls back to the directory ═══"
setup
record work 4070 busy placeholder /home/u/some/deep/path
jq 'del(.name)' $ROOT/.claude/sessions/4070.json >$ROOT/.claude/sessions/4070.tmp
mv $ROOT/.claude/sessions/4070.tmp $ROOT/.claude/sessions/4070.json
fake_proc 4070 407000
set out (collect)
check "name falls back to the working directory" path (echo $out | jq -r '.sessions[0].name')

echo
echo "═══ Tripwire: the real session registry was untouched ═══"
set -g HOME $REAL_HOME
set -l leaked (__registry_records $REAL_HOME | string match -r '40[0-9]{2}\.json' | string join ' ')
check "no sandbox pid was written to the real registry" "" "$leaked"
check "no real record was deleted" "" (
    for f in (string split ' ' -- "$REAL_BEFORE")
        test -n "$f"; and not test -e $REAL_HOME/.claude/sessions/$f; and echo $f
    end | string join ' ')

echo
echo "════════════════════════════"
echo "PASS: $PASS  FAIL: $FAIL"
rm -rf (dirname $ROOT)
test $FAIL -eq 0
