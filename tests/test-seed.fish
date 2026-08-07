#!/usr/bin/env fish
# Sandbox tests for seed-personal.fish.
# MUST run with: fish --no-config
set -g REPO (dirname (dirname (realpath (status filename))))
set -g SEED $REPO/seed-personal.fish
set -g ROOT (mktemp -d)/sandbox
set -g PASS 0
set -g FAIL 0

# Tripwire: the real profile must be untouched. Captured before $HOME is
# overridden — never hardcode a home path, or the fingerprints come out empty
# on both sides and the check guards nothing.
function __fingerprint -a home
    find $home/.claude $home/.claude-personal -maxdepth 1 \
        -printf '%y %T@ %s %p\n' 2>/dev/null | sort | md5sum
end
set -g REAL_HOME $HOME
set -g REAL_FP (__fingerprint $REAL_HOME)

function check -a name expected actual
    if test "$expected" = "$actual"
        set PASS (math $PASS + 1); echo "  ✓ $name"
    else
        set FAIL (math $FAIL + 1); echo "  ✗ $name"
        echo "      expected: [$expected]"
        echo "      actual:   [$actual]"
    end
end

function is_link -a p
    test -L $p; and echo yes; or echo no
end

function exists -a p
    test -e $p; and echo yes; or echo no
end

# A default profile with real content, plus a logged-in but empty personal one.
function setup
    rm -rf $ROOT
    set -g HOME $ROOT
    mkdir -p $ROOT/.claude/plugins/p1 $ROOT/.claude/projects/proj-a \
        $ROOT/.claude/file-history $ROOT/.claude-personal
    echo '{"tipsHistory":{"t":1},"oauthAccount":{"emailAddress":"work@x.com"}}' >$ROOT/.claude.json
    echo '{"model":"opus","hooks":{"PreToolUse":"echo hi"},"enabledPlugins":["p1"]}' >$ROOT/.claude/settings.json
    echo '{"permissions":{"allow":["Bash(ls)"]}}' >$ROOT/.claude/settings.local.json
    echo '{"ts":1,"prompt":"work-line"}' >$ROOT/.claude/history.jsonl
    echo '{"plugins":{"p1":{"installPath":"'$ROOT'/.claude/plugins/p1"}}}' \
        >$ROOT/.claude/plugins/installed_plugins.json
    # Sentinel: proves the multi-gigabyte plugin cache is never copied.
    echo CACHE-SENTINEL >$ROOT/.claude/plugins/p1/cache-blob.txt
    echo '{}' >$ROOT/.claude-personal/.credentials.json
end

function run_seed
    env HOME=$ROOT fish --no-config $SEED >/dev/null 2>&1
end

echo "═══ Task 1: refuses to run on an uninitialized profile ═══"
setup
rm $ROOT/.claude-personal/.credentials.json
run_seed
check "exits nonzero without credentials" 1 $status
check "state file not created" no (exists $ROOT/.claude-personal/.claude.json)

echo "═══ Task 2: fresh profile inherits shared state, keeps its identity ═══"
setup
echo '{"oauthAccount":{"emailAddress":"me@personal.com"},"userID":"u-p"}' >$ROOT/.claude-personal/.claude.json
run_seed
check "exits 0" 0 $status
check "personal identity preserved" me@personal.com \
    (jq -r '.oauthAccount.emailAddress' $ROOT/.claude-personal/.claude.json)
check "work onboarding state inherited" '{"t":1}' \
    (jq -c '.tipsHistory' $ROOT/.claude-personal/.claude.json)
check "pre-seed backup written" yes (exists $ROOT/.claude-personal/.claude.json.pre-seed.bak)
check "hooks propagated" '{"PreToolUse":"echo hi"}' \
    (jq -c '.hooks' $ROOT/.claude-personal/settings.json)

echo "═══ Task 3: volatile keys never cross profiles ═══"
check "model not copied from work" null (jq -r '.model' $ROOT/.claude-personal/settings.json)

echo "═══ Task 4: plugin registry only, never the cache ═══"
check "installPath repointed at personal" $ROOT/.claude-personal/plugins/p1 \
    (jq -r '.plugins.p1.installPath' $ROOT/.claude-personal/plugins/installed_plugins.json)
check "cache sentinel not copied" no (exists $ROOT/.claude-personal/plugins/p1/cache-blob.txt)

echo "═══ Task 5: shared surfaces established without needing a launch ═══"
check "settings.local.json is a symlink" yes (is_link $ROOT/.claude-personal/settings.local.json)
check "projects is a symlink" yes (is_link $ROOT/.claude-personal/projects)
check "file-history is a symlink" yes (is_link $ROOT/.claude-personal/file-history)
check "history.jsonl is a symlink" yes (is_link $ROOT/.claude-personal/history.jsonl)

echo "═══ Task 6: safe to re-run — no personal state is clobbered ═══"
setup
echo '{"oauthAccount":{"emailAddress":"me@personal.com"},"personalOnly":"KEEPME"}' \
    >$ROOT/.claude-personal/.claude.json
run_seed
# The personal profile now makes its own choices, then seeding runs again.
echo '{"model":"claude-fable-5","hooks":{"PreToolUse":"echo hi"},"enabledPlugins":["p1"]}' \
    >$ROOT/.claude-personal/settings.json
run_seed
check "re-run exits 0" 0 $status
check "personal model survives" claude-fable-5 (jq -r '.model' $ROOT/.claude-personal/settings.json)
check "personal-only state key survives" KEEPME (jq -r '.personalOnly' $ROOT/.claude-personal/.claude.json)
check "identity still intact" me@personal.com \
    (jq -r '.oauthAccount.emailAddress' $ROOT/.claude-personal/.claude.json)
check "symlink share is idempotent" yes (is_link $ROOT/.claude-personal/projects)

echo "═══ Task 7: a failed sync is reported, not swallowed ═══"
setup
echo '{"oauthAccount":{"emailAddress":"me@personal.com"}}' >$ROOT/.claude-personal/.claude.json
echo '{"hooks":{"x":1}}' >$ROOT/.claude-personal/settings.json
echo 'NOT VALID JSON' >$ROOT/.claude/settings.json
run_seed
check "exits nonzero when profiles stay drifted" 1 $status

echo
echo "═══ TRIPWIRE ═══"
check "real profile untouched" "$REAL_FP" (__fingerprint $REAL_HOME)

echo
echo "───────────────"
echo "PASS: $PASS   FAIL: $FAIL"
rm -rf (dirname $ROOT)
test $FAIL -eq 0
