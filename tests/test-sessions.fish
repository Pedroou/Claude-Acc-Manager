#!/usr/bin/env fish
# Sandbox tests for session/history sharing (__claude_share_sessions).
# MUST run with: fish --no-config
set -g SCRIPT (dirname (dirname (realpath (status filename))))/claude-profiles.fish
set -g ROOT (mktemp -d)/sandbox
set -g PASS 0
set -g FAIL 0

# Tripwire: the real session dirs must be untouched by this suite. Captured here,
# before `setup` overrides $HOME with the sandbox — never hardcode a home path,
# or both fingerprints come out empty and the check guards nothing.
# %y is included so a directory silently replaced by a symlink is caught.
function __session_fingerprint -a home
    find $home/.claude/projects $home/.claude/file-history $home/.claude/history.jsonl \
        $home/.claude-personal/projects $home/.claude-personal/file-history \
        $home/.claude-personal/history.jsonl \
        -maxdepth 0 -printf '%y %T@ %s %p\n' 2>/dev/null | sort | md5sum
end
set -g REAL_HOME $HOME
set -g REAL_FP (__session_fingerprint $REAL_HOME)

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
    mkdir -p $ROOT/.claude $ROOT/.claude-personal
end

function is_link -a p
    test -L $p; and echo yes; or echo no
end

echo "═══ Task 1: first share merges projects and symlinks ═══"
setup
source $SCRIPT
mkdir -p $ROOT/.claude/projects/-proj $ROOT/.claude-personal/projects/-proj
echo work-a >$ROOT/.claude/projects/-proj/a.jsonl
echo pers-b >$ROOT/.claude-personal/projects/-proj/b.jsonl
# conflict where personal is newer → personal wins, work copy backed up
echo old-work >$ROOT/.claude/projects/-proj/c.jsonl
echo new-pers >$ROOT/.claude-personal/projects/-proj/c.jsonl
touch -d '2 days ago' $ROOT/.claude/projects/-proj/c.jsonl
# conflict where work is newer → work wins
echo new-work >$ROOT/.claude/projects/-proj/d.jsonl
echo old-pers >$ROOT/.claude-personal/projects/-proj/d.jsonl
touch -d '2 days ago' $ROOT/.claude-personal/projects/-proj/d.jsonl
__claude_share_sessions
check "pers projects is now a symlink" yes (is_link $ROOT/.claude-personal/projects)
check "symlink points at work projects" $ROOT/.claude/projects (readlink $ROOT/.claude-personal/projects)
check "work-only file kept" work-a (cat $ROOT/.claude/projects/-proj/a.jsonl)
check "personal-only file merged in" pers-b (cat $ROOT/.claude/projects/-proj/b.jsonl)
check "newer personal file wins conflict" new-pers (cat $ROOT/.claude/projects/-proj/c.jsonl)
check "newer work file survives conflict" new-work (cat $ROOT/.claude/projects/-proj/d.jsonl)
check "overwritten work file backed up" old-work (cat $ROOT/.claude/backups/projects-overwritten-*/-proj/c.jsonl)
check "merged personal dir kept as backup" new-pers (cat $ROOT/.claude-personal/backups/projects-merged-*/-proj/c.jsonl)
check "reading via personal path sees everything" pers-b (cat $ROOT/.claude-personal/projects/-proj/b.jsonl)

echo
echo "═══ Task 2: already shared → no-op ═══"
__claude_share_sessions
check "still a symlink" yes (is_link $ROOT/.claude-personal/projects)
check "content untouched" work-a (cat $ROOT/.claude/projects/-proj/a.jsonl)
check "no second merged-backup created" 1 (count $ROOT/.claude-personal/backups/projects-merged-*)

echo
echo "═══ Task 3: self-heal after symlink replaced by real dir ═══"
rm $ROOT/.claude-personal/projects
mkdir -p $ROOT/.claude-personal/projects/-proj
echo fresh-e >$ROOT/.claude-personal/projects/-proj/e.jsonl
__claude_share_sessions
check "symlink restored" yes (is_link $ROOT/.claude-personal/projects)
check "orphaned session merged back" fresh-e (cat $ROOT/.claude/projects/-proj/e.jsonl)

echo
echo "═══ Task 4: history.jsonl union, deduped, timestamp-ordered ═══"
setup
source $SCRIPT
printf '%s\n' '{"display":"one","timestamp":100}' '{"display":"both","timestamp":200}' >$ROOT/.claude/history.jsonl
printf '%s\n' '{"display":"both","timestamp":200}' '{"display":"three","timestamp":150}' >$ROOT/.claude-personal/history.jsonl
__claude_share_sessions
check "pers history is now a symlink" yes (is_link $ROOT/.claude-personal/history.jsonl)
check "union deduped to 3 entries" 3 (wc -l <$ROOT/.claude/history.jsonl | string trim)
check "entries ordered by timestamp" 'one three both' (jq -r .display $ROOT/.claude/history.jsonl | string join ' ')

echo
echo "═══ Task 5: history self-heal after symlink replaced ═══"
rm $ROOT/.claude-personal/history.jsonl
echo '{"display":"orphan","timestamp":300}' >$ROOT/.claude-personal/history.jsonl
__claude_share_sessions
check "history symlink restored" yes (is_link $ROOT/.claude-personal/history.jsonl)
check "orphaned entry merged, 4 total" 4 (wc -l <$ROOT/.claude/history.jsonl | string trim)

echo
echo "═══ Task 6: file-history shared like projects ═══"
setup
source $SCRIPT
mkdir -p $ROOT/.claude/file-history/s1 $ROOT/.claude-personal/file-history/s2
echo w >$ROOT/.claude/file-history/s1/f
echo p >$ROOT/.claude-personal/file-history/s2/f
__claude_share_sessions
check "pers file-history is a symlink" yes (is_link $ROOT/.claude-personal/file-history)
check "both sessions' checkpoints present" 'p w' (cat $ROOT/.claude/file-history/s2/f $ROOT/.claude/file-history/s1/f | sort | string join ' ')

echo
echo "═══ Task 7: degenerate cases ═══"
setup
source $SCRIPT
rm -rf $ROOT/.claude-personal
__claude_share_sessions
check "no personal profile → no-op, exit 0" 0 $status
check "nothing invented under work" no (test -e $ROOT/.claude/projects; and echo yes; or echo no)
setup
source $SCRIPT
# personal exists but has no projects/history yet → link to (created) work targets
__claude_share_sessions
check "empty personal still gets projects link" yes (is_link $ROOT/.claude-personal/projects)
check "empty personal still gets history link" yes (is_link $ROOT/.claude-personal/history.jsonl)

echo
echo "═══ TRIPWIRE ═══"
check "real session dirs untouched" "$REAL_FP" (__session_fingerprint $REAL_HOME)

echo
echo "════════════════════════════"
echo "PASS: $PASS  FAIL: $FAIL"
rm -rf (dirname $ROOT)
test $FAIL = 0
