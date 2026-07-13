#!/usr/bin/env fish
# Sandbox tests for claude-profiles.fish auto-sync guards.
# Each scenario builds a fake $HOME with a work + personal profile, runs the
# real auto-sync code against it, and asserts what survived.

# MUST be run with `fish --no-config`, otherwise fish loads the installed
# conf.d/claude-profiles.fish at startup against the REAL $HOME.
set -g SCRIPT (dirname (dirname (realpath (status filename))))/claude-profiles.fish
set -g ROOT (mktemp -d)/sandbox
set -g PASS 0
set -g FAIL 0

# Tripwire: the real profile must be byte-identical before and after the suite.
set -g REAL_HOME /home/pedro
set -g REAL_FINGERPRINT (find $REAL_HOME/.claude/settings.json $REAL_HOME/.claude/settings.local.json \
    $REAL_HOME/.claude/plugins/installed_plugins.json -printf '%T@ %s %p\n' 2>/dev/null | sort | md5sum)
set -g REAL_PERS_EXISTS (test -e $REAL_HOME/.claude-personal; and echo yes; or echo no)

# A realistic 10-key settings.json and a 5-plugin registry.
set -g FULL_SETTINGS '{"model":"opus","theme":"dark","a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8}'
set -g FULL_PLUGINS '{"plugins":{"p1":{"installPath":"WORKDIR/plugins/p1"},"p2":{},"p3":{},"p4":{},"p5":{}}}'

function setup -a scenario
    rm -rf $ROOT
    set -g HOME $ROOT
    mkdir -p $ROOT/.claude/plugins $ROOT/.claude-personal/plugins

    # Work: the mature, real profile. Deliberately given an OLD mtime.
    echo $FULL_SETTINGS >$ROOT/.claude/settings.json
    echo '{"permissions":{"allow":["Bash"]},"x":1}' >$ROOT/.claude/settings.local.json
    echo (string replace WORKDIR $ROOT/.claude $FULL_PLUGINS) >$ROOT/.claude/plugins/installed_plugins.json
    echo '{"oauthAccount":{"emailAddress":"work@x.com"}}' >$ROOT/.claude.json
    touch -d '3 days ago' $ROOT/.claude/settings.json $ROOT/.claude/settings.local.json \
        $ROOT/.claude/plugins/installed_plugins.json
end

function seed_personal
    # Mark personal as logged-in + seeded (what seed-personal.fish produces).
    echo '{}' >$ROOT/.claude-personal/.credentials.json
    echo '{"oauthAccount":{"emailAddress":"personal@x.com"}}' >$ROOT/.claude-personal/.claude.json
    touch $ROOT/.claude-personal/.profile-seeded
end

function check -a name expected actual
    if test "$expected" = "$actual"
        set -g PASS (math $PASS + 1)
        echo "  ✓ $name"
    else
        set -g FAIL (math $FAIL + 1)
        echo "  ✗ $name"
        echo "      expected: $expected"
        echo "      actual:   $actual"
    end
end

function work_keys
    jq 'keys|length' $ROOT/.claude/settings.json 2>/dev/null; or echo ERR
end
function work_plugin_count
    jq '.plugins|length' $ROOT/.claude/plugins/installed_plugins.json 2>/dev/null; or echo ERR
end

echo
echo "═══ SCENARIO A: Pedro's case — fresh unseeded personal profile ═══"
echo "    (personal just created by first login: empty config, NEWEST mtime)"
setup
echo '{}' >$ROOT/.claude-personal/settings.json # fresh onboarding stub, brand new
echo '{}' >$ROOT/.claude-personal/.credentials.json
echo '{"oauthAccount":{"emailAddress":"personal@x.com"}}' >$ROOT/.claude-personal/.claude.json
# NOTE: no .profile-seeded marker
source $SCRIPT
check "gate refuses to arm auto-sync" false (__claude_profiles_seeded; and echo true; or echo false)
__claude_autosync >/dev/null 2>&1 # even if forced, must not destroy work
check "work settings.json survives intact (10 keys)" 10 (work_keys)
check "work plugins survive intact (5 plugins)" 5 (work_plugin_count)

echo
echo "═══ SCENARIO B: seeded, personal genuinely newer and complete ═══"
setup
seed_personal
echo '{"model":"opus","theme":"light","a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"NEW":9}' >$ROOT/.claude-personal/settings.json
source $SCRIPT
check "gate arms auto-sync" true (__claude_profiles_seeded; and echo true; or echo false)
__claude_autosync >/dev/null 2>&1
check "personal → work applied (11 keys)" 11 (work_keys)
check "new key propagated" 9 (jq '.NEW' $ROOT/.claude/settings.json)

echo
echo "═══ SCENARIO C: seeded, personal newer but EMPTY {} ═══"
setup
seed_personal
echo '{}' >$ROOT/.claude-personal/settings.json # newest, but hollow
source $SCRIPT
set -l out (__claude_autosync 2>&1 | string collect)
check "work settings.json NOT wiped (still 10 keys)" 10 (work_keys)
check "refusal reported" true (string match -q '*auto-sync skipped*' -- "$out"; and echo true; or echo false)
echo "    → $(string match -r '⚠.*' -- "$out")"

echo
echo "═══ SCENARIO D: seeded, personal newer but SHRUNK (3 keys vs 10) ═══"
setup
seed_personal
echo '{"model":"opus","a":1,"b":2}' >$ROOT/.claude-personal/settings.json
source $SCRIPT
set -l out (__claude_autosync 2>&1 | string collect)
check "shrink guard blocks it (work still 10 keys)" 10 (work_keys)
echo "    → $(string match -r '⚠.*' -- "$out")"

echo
echo "═══ SCENARIO E: seeded, personal newer, modest shrink (6 keys vs 10) ═══"
echo "    (a legitimate cleanup — must be ALLOWED, 6*2 >= 10)"
setup
seed_personal
echo '{"model":"opus","a":1,"b":2,"c":3,"d":4,"e":5}' >$ROOT/.claude-personal/settings.json
source $SCRIPT
__claude_autosync >/dev/null 2>&1
check "allowed through (work now 6 keys)" 6 (work_keys)

echo
echo "═══ SCENARIO F: seeded, personal newer but plugin list EMPTY ═══"
setup
seed_personal
echo '{"plugins":{}}' >$ROOT/.claude-personal/plugins/installed_plugins.json
source $SCRIPT
set -l out (__claude_autosync 2>&1 | string collect)
check "work's 5 plugins NOT wiped" 5 (work_plugin_count)
echo "    → $(string match -r '⚠.*plugins.*' -- "$out")"

echo
echo "═══ SCENARIO G: seeded, identical mtimes but different content ═══"
setup
seed_personal
echo '{"model":"haiku","zzz":1}' >$ROOT/.claude-personal/settings.json
touch -d '3 days ago' $ROOT/.claude-personal/settings.json # tie with work
source $SCRIPT
set -l out (__claude_autosync 2>&1 | string collect)
check "tie refused, work untouched" 10 (work_keys)
echo "    → $(string match -r '⚠.*' -- "$out")"

echo
echo "═══ SCENARIO H: backup written before a legitimate overwrite ═══"
setup
seed_personal
echo '{"model":"opus","theme":"light","a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"NEW":9}' >$ROOT/.claude-personal/settings.json
source $SCRIPT
__claude_autosync >/dev/null 2>&1
set -l baks $ROOT/.claude/backups/profile-sync-*/settings.json
check "old work settings.json preserved in backup" 10 (jq 'keys|length' $baks[1] 2>/dev/null; or echo MISSING)

echo
echo "═══ SCENARIO I: offer-seed — personal exists but NOT logged in ═══"
setup
mkdir -p $ROOT/.claude-personal # exists, but no credentials
source $SCRIPT
set -l out (__claude_maybe_offer_seed 2>&1 </dev/null | string collect)
check "tells user to /login, does not seed" true (string match -q "*isn't logged in*" -- "$out"; and echo true; or echo false)
check "no .profile-seeded created" false (test -f $ROOT/.claude-personal/.profile-seeded; and echo true; or echo false)

echo
echo "═══ SCENARIO J: offer-seed — declined earlier, stays silent ═══"
setup
seed_personal
rm $ROOT/.claude-personal/.profile-seeded # logged in, not seeded
touch $ROOT/.claude-personal/.autosync-declined
source $SCRIPT
set -l out (__claude_maybe_offer_seed 2>&1 </dev/null | string collect)
check "no output when declined" "" "$out"

echo
echo "═══ SCENARIO K: offer-seed — non-interactive shell never blocks ═══"
setup
seed_personal
rm $ROOT/.claude-personal/.profile-seeded
source $SCRIPT
# stdin is not a tty here (piped), so it must print a hint and return, not hang
set -l out (__claude_maybe_offer_seed 2>&1 </dev/null | string collect)
check "prints hint, no prompt, no hang" true (string match -q "*not seeded*" -- "$out"; and echo true; or echo false)
check "did not create decline marker" false (test -f $ROOT/.claude-personal/.autosync-declined; and echo true; or echo false)

echo
echo "═══ SCENARIO L: repo dir resolves so seed script is findable ═══"
setup
source $SCRIPT
check "seed-personal.fish exists at resolved repo dir" true (test -f $__claude_profiles_dir/seed-personal.fish; and echo true; or echo false)

echo
echo "═══ TRIPWIRE: the real ~/.claude must be untouched by this suite ═══"
set -l after (find $REAL_HOME/.claude/settings.json $REAL_HOME/.claude/settings.local.json \
    $REAL_HOME/.claude/plugins/installed_plugins.json -printf '%T@ %s %p\n' 2>/dev/null | sort | md5sum)
check "real profile byte-identical (mtime+size)" "$REAL_FINGERPRINT" "$after"
check "real ~/.claude-personal not created by tests" $REAL_PERS_EXISTS (test -e $REAL_HOME/.claude-personal; and echo yes; or echo no)

echo
echo "───────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
test $FAIL -eq 0
