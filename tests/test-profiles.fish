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
echo "═══ Task 2: drift ignores volatile keys ═══"
setup
source $SCRIPT
# Same shared surface, differing model+tui only → NOT drift.
echo '{"model":"opus","tui":{"theme":"dark"},"hooks":{"x":1}}'  >$ROOT/.claude/settings.json
echo '{"model":"fable","tui":{"theme":"light"},"hooks":{"x":1}}' >$ROOT/.claude-personal/settings.json
echo '{"plugins":{"p1":{}}}' >$ROOT/.claude/plugins/installed_plugins.json
echo '{"plugins":{"p1":{}}}' >$ROOT/.claude-personal/plugins/installed_plugins.json
check "model/tui-only diff is NOT drift" "" (__claude_profile_divergence)

# Differing hooks → drift on settings.json.
echo '{"model":"fable","hooks":{"x":2}}' >$ROOT/.claude-personal/settings.json
check "hooks diff IS drift" "settings.json" (__claude_profile_divergence)

# Differing plugin set → drift on plugins.
echo '{"model":"opus","hooks":{"x":1}}' >$ROOT/.claude/settings.json
echo '{"model":"fable","hooks":{"x":1}}' >$ROOT/.claude-personal/settings.json
echo '{"plugins":{"p1":{},"p2":{}}}' >$ROOT/.claude-personal/plugins/installed_plugins.json
check "plugin-set diff IS drift" "plugins" (__claude_profile_divergence)

# Regression: no plugin registry on either side must NOT be drift, and must not crash.
rm -f $ROOT/.claude/plugins/installed_plugins.json $ROOT/.claude-personal/plugins/installed_plugins.json
echo '{"hooks":{"a":1}}' >$ROOT/.claude/settings.json
echo '{"hooks":{"a":1}}' >$ROOT/.claude-personal/settings.json
check "no plugin registry on either side is NOT drift" "" (__claude_profile_divergence)
# Regression: registry present on one side only → drift, no crash.
echo '{"plugins":{"p1":{}}}' >$ROOT/.claude/plugins/installed_plugins.json
check "registry on one side only IS drift" "plugins" (__claude_profile_divergence)

echo
echo "═══ Task 3: key-merge preserves dst volatile ═══"
setup
source $SCRIPT
echo '{"model":"opus","hooks":{"a":1},"tui":{"theme":"dark"}}'  >$ROOT/src.json
echo '{"model":"fable","hooks":{"a":0},"tui":{"theme":"light"}}' >$ROOT/dst.json
set -l m (__claude_merge_settings $ROOT/src.json $ROOT/dst.json | jq -Sc .)
check "shared key taken from src" 1 (echo $m | jq '.hooks.a')
check "dst model preserved"      '"fable"' (echo $m | jq -c '.model')
check "dst tui preserved"        '"light"' (echo $m | jq -c '.tui.theme')
# Missing dst → src shared surface only, no volatile leaks in.
set -l m2 (__claude_merge_settings $ROOT/src.json $ROOT/nonexistent.json)
check "no dst → src model dropped (volatile never imported)" "null" (echo $m2 | jq -c '.model')
check "no dst → src hooks kept" 1 (echo $m2 | jq '.hooks.a')

echo
echo "═══ Task 4: registry path rewrite ═══"
setup
source $SCRIPT
echo '{"plugins":{"p1":{"installPath":"/w/plugins/p1"},"p2":{"installPath":"/other/x"}}}' >$ROOT/reg.json
set -l r (__claude_rewrite_registry $ROOT/reg.json "/w/plugins" "/p/plugins" | jq -Sc .)
check "matching prefix repointed" '"/p/plugins/p1"' (echo $r | jq -c '.plugins.p1.installPath')
check "non-matching path untouched" '"/other/x"' (echo $r | jq -c '.plugins.p2.installPath')

echo
echo "═══ Task 5: claude-profiles-sync ═══"
setup
source $SCRIPT
# work is source; personal keeps its own model, gains work's hooks + plugins.
echo '{"model":"opus","hooks":{"deploy":1}}'  >$ROOT/.claude/settings.json
echo '{"model":"fable"}'                        >$ROOT/.claude-personal/settings.json
echo (string replace /W $ROOT/.claude '{"plugins":{"p1":{"installPath":"/W/plugins/p1"},"p2":{}}}') >$ROOT/.claude/plugins/installed_plugins.json
echo '{"plugins":{}}' >$ROOT/.claude-personal/plugins/installed_plugins.json
# sentinel cache file that must NOT be copied
echo SENTINEL >$ROOT/.claude/plugins/BIG_CACHE_FILE
claude-profiles-sync work-to-personal >/dev/null
check "hooks propagated to personal" 1 (jq '.hooks.deploy' $ROOT/.claude-personal/settings.json)
check "personal model preserved"     '"fable"' (jq -c '.model' $ROOT/.claude-personal/settings.json)
check "plugin registry reconciled"   "p1,p2" (__claude_plugin_keys $ROOT/.claude-personal)
check "installPath repointed to personal" "$ROOT/.claude-personal/plugins/p1" (jq -r '.plugins.p1.installPath' $ROOT/.claude-personal/plugins/installed_plugins.json)
check "cache file NOT copied" false (test -e $ROOT/.claude-personal/plugins/BIG_CACHE_FILE; and echo true; or echo false)
check "in sync afterwards" "" (__claude_profile_divergence)
check "backup written" true (count $ROOT/.claude-personal/backups/profile-sync-*/settings.json >/dev/null 2>&1; and test -e (echo $ROOT/.claude-personal/backups/profile-sync-*/settings.json)[1]; and echo true; or echo false)

echo
echo "═══ Task 6: shared settings.local.json + self-heal ═══"
setup
source $SCRIPT
# Both start as regular files with different grants → union into work, symlink personal.
echo '{"permissions":{"allow":["Bash(git*)"]}}'  >$ROOT/.claude/settings.local.json
echo '{"permissions":{"allow":["Read(*)"]}}'       >$ROOT/.claude-personal/settings.local.json
__claude_share_settings_local
check "personal is now a symlink" true (test -L $ROOT/.claude-personal/settings.local.json; and echo true; or echo false)
check "symlink points at work" "$ROOT/.claude/settings.local.json" (readlink $ROOT/.claude-personal/settings.local.json)
check "work grants unioned (git*)" true (jq -e '.permissions.allow | index("Bash(git*)") != null' $ROOT/.claude/settings.local.json >/dev/null; and echo true; or echo false)
check "work grants unioned (Read)" true (jq -e '.permissions.allow | index("Read(*)") != null' $ROOT/.claude/settings.local.json >/dev/null; and echo true; or echo false)
check "grant visible through personal symlink" true (jq -e '.permissions.allow | index("Read(*)") != null' $ROOT/.claude-personal/settings.local.json >/dev/null; and echo true; or echo false)
# Idempotent: second call is a no-op, still a symlink.
__claude_share_settings_local
check "still a symlink after 2nd call" true (test -L $ROOT/.claude-personal/settings.local.json; and echo true; or echo false)
# Self-heal: an atomic-rename write replaced the symlink with a regular file holding a new grant.
rm $ROOT/.claude-personal/settings.local.json
echo '{"permissions":{"allow":["WebFetch"]}}' >$ROOT/.claude-personal/settings.local.json
__claude_share_settings_local
check "self-heal restored symlink" true (test -L $ROOT/.claude-personal/settings.local.json; and echo true; or echo false)
check "self-heal merged new grant into work" true (jq -e '.permissions.allow | index("WebFetch") != null' $ROOT/.claude/settings.local.json >/dev/null; and echo true; or echo false)

echo
echo "═══ Task 7: diff hides volatile keys ═══"
setup
source $SCRIPT
echo '{"model":"opus","hooks":{"a":1}}'  >$ROOT/.claude/settings.json
echo '{"model":"fable","hooks":{"a":1}}' >$ROOT/.claude-personal/settings.json
echo '{"plugins":{"p1":{}}}' >$ROOT/.claude/plugins/installed_plugins.json
echo '{"plugins":{"p1":{}}}' >$ROOT/.claude-personal/plugins/installed_plugins.json
set -l out (claude-profiles-diff | string collect)
check "in-sync reported (model diff hidden)" true (string match -q '*in sync*' -- "$out"; and echo true; or echo false)
check "model value not shown as a diff" false (string match -q '*fable*' -- "$out"; and echo true; or echo false)

echo
echo "═══ Task 8: prelaunch direction + non-interactive safety ═══"
setup
source $SCRIPT
# Drift present; last run = work → hint must say work-to-personal, and must NOT sync.
echo '{"model":"opus","hooks":{"a":1}}'  >$ROOT/.claude/settings.json
echo '{"model":"fable","hooks":{"a":2}}' >$ROOT/.claude-personal/settings.json
echo '{"plugins":{}}' >$ROOT/.claude/plugins/installed_plugins.json
echo '{"plugins":{}}' >$ROOT/.claude-personal/plugins/installed_plugins.json
set -l out (__claude_prelaunch work work </dev/null 2>&1 | string collect)
check "hint shows work→personal direction" true (string match -q '*work-to-personal*' -- "$out"; and echo true; or echo false)
check "non-interactive did NOT sync (personal hooks untouched)" 2 (jq '.hooks.a' $ROOT/.claude-personal/settings.json)
# last run = personal → direction flips.
set -l out2 (__claude_prelaunch work personal </dev/null 2>&1 | string collect)
check "hint shows personal→work direction" true (string match -q '*personal-to-work*' -- "$out2"; and echo true; or echo false)
# In sync → prelaunch prints nothing about drift.
echo '{"model":"fable","hooks":{"a":1}}' >$ROOT/.claude-personal/settings.json
set -l out3 (__claude_prelaunch work work </dev/null 2>&1 | string collect)
check "no drift → no warning" false (string match -q '*drifted*' -- "$out3"; and echo true; or echo false)

echo
echo "═══ TRIPWIRE ═══"
set -l after (find $REAL_HOME/.claude/settings.json $REAL_HOME/.claude/settings.local.json \
    $REAL_HOME/.claude/plugins/installed_plugins.json -printf '%T@ %s %p\n' 2>/dev/null | sort | md5sum)
check "real ~/.claude byte-identical" "$REAL_FP" "$after"

echo
echo "───────────────"
echo "PASS: $PASS   FAIL: $FAIL"
test $FAIL -eq 0
