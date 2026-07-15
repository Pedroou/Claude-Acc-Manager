#!/usr/bin/env fish
# Sandbox tests for claude-profiles.fish (v2). MUST run with: fish --no-config
set -g SCRIPT (dirname (dirname (realpath (status filename))))/claude-profiles.fish
set -g REAL_HOME $HOME
set -g REAL_FP (find $REAL_HOME/.claude/settings.json $REAL_HOME/.claude/settings.local.json \
    $REAL_HOME/.claude/plugins/installed_plugins.json -printf '%T@ %s %p\n' 2>/dev/null | sort | md5sum)
set -g ROOT (mktemp -d)/sandbox
set -g PASS 0
set -g FAIL 0

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
    mkdir -p $ROOT/.claude/plugins $ROOT/.claude-personal/plugins
end

echo "═══ Task 1: dir helpers ═══"
setup
source $SCRIPT
check "work dir derives from HOME" "$ROOT/.claude" (__claude_work_dir)
check "pers dir derives from HOME" "$ROOT/.claude-personal" (__claude_pers_dir)

echo
echo "═══ TRIPWIRE ═══"
set -l after (find $REAL_HOME/.claude/settings.json $REAL_HOME/.claude/settings.local.json \
    $REAL_HOME/.claude/plugins/installed_plugins.json -printf '%T@ %s %p\n' 2>/dev/null | sort | md5sum)
check "real ~/.claude byte-identical" "$REAL_FP" "$after"

echo
echo "───────────────"
echo "PASS: $PASS   FAIL: $FAIL"
test $FAIL -eq 0
