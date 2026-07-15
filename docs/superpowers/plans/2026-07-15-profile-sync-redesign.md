# Profile Config Sync Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the launch-time newest-wins auto-copy with a design that *shares* the permission allowlist, *ignores* volatile per-profile keys, and *syncs the rest only on demand*.

**Architecture:** All launcher logic lives in one fish file (`claude-profiles.fish`) sourced from `conf.d`. Config splits three ways — volatile keys (never synced), a symlink-shared `settings.local.json` (self-healing), and a shared-on-demand surface (`settings.json` non-volatile keys + plugin registry) reconciled by an explicit command. A launch-time `[Y/n]` prompt offers reconciliation on real drift, direction chosen from the previously-run profile.

**Tech Stack:** fish shell (3.2+), `jq`, `rsync`. Tests are fish sandbox scripts run under `fish --no-config`.

## Global Constraints

- fish 3.2+ (`$argv[2..]` slicing). `jq` and `rsync` required.
- Profile dirs are derived from `$HOME` **on every call** via `__claude_work_dir` / `__claude_pers_dir` — never cached in a global at source time (keeps code testable under a fake `$HOME`).
- **Volatile keys (never compared, never synced), verbatim:** `model`, `effortLevel`, `advisorModel`, `tui`.
- The jq expression for stripping them, verbatim: `del(.model, .effortLevel, .advisorModel, .tui)`.
- The **plugin cache is never copied or compared** — only the registry `plugins/installed_plugins.json`. `settings.local.json` is shared, so it is never compared for drift.
- Tests MUST be run with `fish --no-config` (otherwise fish loads the installed `conf.d/claude-profiles.fish` against the real `$HOME`). Every test file captures a fingerprint of the real `~/.claude` and asserts it is byte-identical at the end (tripwire). Never hardcode a home path — capture `$HOME` at script start before overriding it.
- Work on branch `redesign-profile-sync`. The live `conf.d` symlink resolves to the working-tree file, so **every commit must leave `claude-profiles.fish` loadable with a working `claude` launcher** — modify in place, never leave the file launcher-less between tasks.
- Every commit message ends with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

## File Structure

- `claude-profiles.fish` — **modified in place**. Starting point is the reverted v1 (helpers inline, `__claude_profile_divergence`, `claude-profiles-diff`, `claude-profiles-sync`, `__claude_run`, three launchers). Tasks add helper functions, rewrite four existing functions, and swap the launcher internals last. One responsibility: the launcher + reconcile logic.
- `tests/test-profiles.fish` — **new**. Sandbox suite. Replaces the deleted `tests/test-autosync.fish`.
- `seed-personal.fish` — **modified**. Drop the `settings.local.json` copy; establish the shared symlink instead.
- `install.fish` — **modified**. After symlinking, establish the shared `settings.local.json` symlink (idempotent).
- `README.md` — **rewritten** to describe v2.
- `tests/test-autosync.fish` — **deleted** (tests removed machinery; hardcodes `/home/pedro`).

---

### Task 1: Test harness + profile-dir helpers

**Files:**
- Modify: `claude-profiles.fish` (add two helper functions near the top, after the header comment block)
- Create: `tests/test-profiles.fish`

**Interfaces:**
- Produces: `__claude_work_dir` → echoes `$HOME/.claude`. `__claude_pers_dir` → echoes `$HOME/.claude-personal`. Test harness functions `setup`, `check name expected actual`, globals `$SCRIPT`, `$ROOT`, `$PASS`, `$FAIL`, `$REAL_HOME`, `$REAL_FP`.

- [ ] **Step 1: Write the failing test** — create `tests/test-profiles.fish`:

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — `__claude_work_dir`/`__claude_pers_dir` are unknown commands (they are new; v1 uses inline `$HOME/.claude`).

- [ ] **Step 3: Add the helpers** — in `claude-profiles.fish`, immediately after the header comment block (before `function __claude_profile_divergence`), insert:

```fish
# Profile dirs are derived from $HOME on every call, never cached in a global:
# a cached global is captured at load time and ignores a later $HOME, which
# makes the code untestable and would point sync at the wrong dirs.
function __claude_work_dir
    echo $HOME/.claude
end

function __claude_pers_dir
    echo $HOME/.claude-personal
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS (3 checks pass, tripwire passes).

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Add profile-dir helpers and v2 test harness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Drift detection ignoring volatile keys

**Files:**
- Modify: `claude-profiles.fish` (add `__claude_shared`, `__claude_plugin_keys`; rewrite `__claude_profile_divergence`)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Consumes: `__claude_work_dir`, `__claude_pers_dir`.
- Produces: `__claude_shared FILE` → compact canonical JSON of FILE with volatile keys removed (`{}` if unreadable). `__claude_plugin_keys DIR` → sorted comma-joined plugin key list of `DIR/plugins/installed_plugins.json` (empty if none). `__claude_profile_divergence` → newline-joined list of drifted artifacts (`settings.json`, `plugins`); empty when in sync. Ignores `settings.local.json` (it is shared) and the plugin cache.

- [ ] **Step 1: Write the failing test** — append to `tests/test-profiles.fish` *before* the TRIPWIRE block:

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — v1 `__claude_profile_divergence` compares raw files (so the model/tui diff is wrongly reported as drift), and `__claude_shared`/`__claude_plugin_keys` don't exist.

- [ ] **Step 3: Add helpers and rewrite divergence** — in `claude-profiles.fish`, add these two helpers (near the other helpers) and replace the entire `__claude_profile_divergence` function body with:

```fish
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
    if test -e $work/settings.json; or test -e $pers/settings.json
        if test (__claude_shared $work/settings.json) != (__claude_shared $pers/settings.json)
            set -a diffs settings.json
        end
    end

    # settings.local.json is shared via symlink (§4) — never compared here.

    # Plugin registry key list only; the cache is never inspected.
    if test (__claude_plugin_keys $work) != (__claude_plugin_keys $pers)
        set -a diffs plugins
    end

    string join \n $diffs
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS (all Task 1 + Task 2 checks + tripwire).

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Drift detection ignores volatile keys and the plugin cache

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `settings.json` key-merge preserving destination volatile keys

**Files:**
- Modify: `claude-profiles.fish` (add `__claude_merge_settings`)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Produces: `__claude_merge_settings SRCFILE DSTFILE` → prints merged JSON to stdout = SRC's non-volatile keys + DST's own volatile keys (`model`/`effortLevel`/`advisorModel`/`tui`). Missing files are treated as `{}`. Never writes; caller redirects.

- [ ] **Step 1: Write the failing test** — append before TRIPWIRE:

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — `__claude_merge_settings` is an unknown command.

- [ ] **Step 3: Add the function** — in `claude-profiles.fish`:

```fish
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Add settings.json key-merge that preserves dst volatile keys

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Plugin registry `installPath` rewrite

**Files:**
- Modify: `claude-profiles.fish` (add `__claude_rewrite_registry`)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Produces: `__claude_rewrite_registry REGFILE SRCPREFIX DSTPREFIX` → prints REGFILE with each plugin's `installPath` that starts with SRCPREFIX repointed to DSTPREFIX. Other values untouched. Prints to stdout; caller redirects.

- [ ] **Step 1: Write the failing test** — append before TRIPWIRE:

```fish
echo
echo "═══ Task 4: registry path rewrite ═══"
setup
source $SCRIPT
echo '{"plugins":{"p1":{"installPath":"/w/plugins/p1"},"p2":{"installPath":"/other/x"}}}' >$ROOT/reg.json
set -l r (__claude_rewrite_registry $ROOT/reg.json "/w/plugins" "/p/plugins" | jq -Sc .)
check "matching prefix repointed" '"/p/plugins/p1"' (echo $r | jq -c '.plugins.p1.installPath')
check "non-matching path untouched" '"/other/x"' (echo $r | jq -c '.plugins.p2.installPath')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — `__claude_rewrite_registry` unknown.

- [ ] **Step 3: Add the function** — in `claude-profiles.fish`:

```fish
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Add plugin-registry installPath rewrite helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rewrite `claude-profiles-sync`

**Files:**
- Modify: `claude-profiles.fish` (replace `claude-profiles-sync` entirely)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Consumes: `__claude_merge_settings`, `__claude_rewrite_registry`, `__claude_profile_divergence`, dir helpers.
- Produces: `claude-profiles-sync work-to-personal|personal-to-work` — key-merges `settings.json` (preserving dst volatile), reconciles the plugin *registry* (path-rewritten, cache untouched), backs up only the small JSONs under `$dst/backups/profile-sync-<stamp>/`, prints one line per artifact + the backup path. No arg → usage + drift summary, return 1.

- [ ] **Step 1: Write the failing test** — append before TRIPWIRE:

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — v1 sync prompts interactively (`read`) and rsyncs the whole plugins dir (would copy the sentinel), so several checks fail / it blocks. (If it blocks on the prompt, that itself confirms the rewrite is needed.)

- [ ] **Step 3: Replace the function** — replace the entire `claude-profiles-sync` function in `claude-profiles.fish` with:

```fish
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Rewrite claude-profiles-sync: key-merge + registry only, no cache copy

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Shared `settings.local.json` (symlink + self-heal)

**Files:**
- Modify: `claude-profiles.fish` (add `__claude_merge_permissions`, `__claude_share_settings_local`)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Produces: `__claude_merge_permissions FILE_A FILE_B` → prints JSON = A with `permissions.allow/deny/ask` unioned (deduped) with B's; empty arrays dropped. `__claude_share_settings_local` → makes `~/.claude-personal/settings.local.json` a symlink to `~/.claude/settings.local.json`, creating/merging as needed; no-op if already a symlink or if no personal dir exists. Idempotent, local, race-free.

- [ ] **Step 1: Write the failing test** — append before TRIPWIRE:

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — both functions unknown.

- [ ] **Step 3: Add the functions** — in `claude-profiles.fish`:

```fish
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Share settings.local.json via self-healing symlink

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Update `claude-profiles-diff` for the shared surface

**Files:**
- Modify: `claude-profiles.fish` (replace `claude-profiles-diff`)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Consumes: dir helpers, `__claude_shared`, `__claude_plugin_keys`.
- Produces: `claude-profiles-diff` — prints a human-readable diff of the shared surface: `settings.json` with volatile keys stripped, plugin registry key list; notes that `settings.local.json` is shared. Prints an in-sync message when there is no drift. Exit status is not asserted.

- [ ] **Step 1: Write the failing test** — append before TRIPWIRE:

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — v1 diff compares raw files, so it reports the `model` diff and prints `fable`.

- [ ] **Step 3: Replace the function** — replace the entire `claude-profiles-diff` function with:

```fish
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "claude-profiles-diff: shared surface only, hide volatile keys

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Launcher pre-flight + `[Y/n]` drift prompt (direction = last run)

**Files:**
- Modify: `claude-profiles.fish` (add `__claude_last_profile`, `__claude_prelaunch`; rewrite `__claude_run`; leave the three launcher functions calling `__claude_run`)
- Modify: `tests/test-profiles.fish` (append scenario)

**Interfaces:**
- Consumes: `__claude_share_settings_local`, `__claude_profile_divergence`, `claude-profiles-sync`.
- Produces:
  - `__claude_last_profile` → echoes `work` or `personal` from `~/.claude-last-profile` (default `work` if absent).
  - `__claude_prelaunch LAUNCHED LAST` → runs self-heal, computes drift; on drift prints the warning and, if interactive, a `[Y/n]` prompt that syncs `LAST`→other unless the reply starts with `n`; if non-interactive, prints a one-line hint and never blocks. Does NOT record last-profile and does NOT launch. `LAST` is the sync source; the other profile is the destination.
  - `__claude_run PROFILE ARGS...` → reads previous last-profile (defaulting to `PROFILE` when the file is absent), calls `__claude_prelaunch PROFILE LAST`, **then** records `PROFILE` to `~/.claude-last-profile`, then execs claude with the right `CLAUDE_CONFIG_DIR`.

- [ ] **Step 1: Write the failing test** — append before TRIPWIRE. (These target `__claude_prelaunch` only — never `__claude_run`, which would exec the real `claude` binary. Stdin is piped in the test, so `isatty stdin` is false and the prompt never blocks.)

```fish
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fish --no-config tests/test-profiles.fish`
Expected: FAIL — `__claude_last_profile` / `__claude_prelaunch` unknown.

- [ ] **Step 3: Add helpers and rewrite `__claude_run`** — add the two helpers and replace the entire `__claude_run` function (the three launcher functions `claude-work`, `claude-personal`, `claude` stay as they are — they already call `__claude_run`):

```fish
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fish --no-config tests/test-profiles.fish`
Expected: PASS.

- [ ] **Step 5: Verify the file still defines a working `claude` launcher** (guards the live symlink):

Run: `fish --no-config -c "source claude-profiles.fish; functions -q claude; and functions -q claude-work; and functions -q claude-personal; and echo OK"`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add claude-profiles.fish tests/test-profiles.fish
git commit -m "Launcher: [Y/n] drift prompt, direction from last profile run

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Update `seed-personal.fish`

**Files:**
- Modify: `seed-personal.fish`

**Interfaces:**
- Consumes: `__claude_share_settings_local` (by sourcing `claude-profiles.fish`).

- [ ] **Step 1: Drop `settings.local.json` from the copy loop** — change the copy loop (currently `for f in settings.json settings.local.json history.jsonl`) to exclude `settings.local.json`:

```fish
# 2. Copy configs (settings.local.json is handled by the shared symlink below)
for f in settings.json history.jsonl
    test -e $work/$f; and cp -a $work/$f $pers/
end
test -d $work/plans; and rsync -a $work/plans $pers/
echo "  ✓ settings, history, plans copied"
```

- [ ] **Step 2: Establish the shared symlink after the copies** — immediately before the final `set -l email ...` line, insert:

```fish
# Share the permission allowlist: make personal's settings.local.json a symlink
# to work's (merging any existing grants first). One file, no drift, no sync.
source (dirname (realpath (status filename)))/claude-profiles.fish
__claude_share_settings_local
echo "  ✓ settings.local.json now shared (personal → work symlink)"
```

- [ ] **Step 3: Verify the script parses**

Run: `fish -n seed-personal.fish; and echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add seed-personal.fish
git commit -m "seed-personal: share settings.local.json instead of copying it

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Update `install.fish`

**Files:**
- Modify: `install.fish`

**Interfaces:**
- Consumes: `__claude_share_settings_local` (by sourcing `claude-profiles.fish`).

- [ ] **Step 1: Establish the shared symlink after symlinking** — after the existing `echo "Installed: ..."` line and before the final `echo "Run 'exec fish' ..."`, insert:

```fish
# Establish the shared settings.local.json symlink if the personal profile
# already exists (idempotent; a no-op once linked or if personal isn't set up).
source $repo_dir/claude-profiles.fish
__claude_share_settings_local
echo "Shared settings.local.json ensured (personal → work, if personal exists)."
```

- [ ] **Step 2: Verify the script parses**

Run: `fish -n install.fish; and echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add install.fish
git commit -m "install: ensure shared settings.local.json symlink

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Rewrite README, delete stale test, final suite + tripwire

**Files:**
- Modify: `README.md`
- Delete: `tests/test-autosync.fish`

- [ ] **Step 1: Delete the stale test**

```bash
git rm tests/test-autosync.fish
```

- [ ] **Step 2: Rewrite the README** — replace `README.md` with:

```markdown
# Claude-Acc-Manager

Run two Claude Code accounts (e.g. a work Team seat and a personal Pro
subscription) side by side, permanently logged in, with zero `/login`
switching. Fish shell only.

## What you get

| Command | What it does |
|---|---|
| `claude-work` | Launches Claude Code with the **default** profile (`~/.claude` + `~/.claude.json`) — stock behavior, untouched |
| `claude-personal` | Launches with a second, independent profile (`~/.claude-personal`) via `CLAUDE_CONFIG_DIR` |
| `claude` | Sticky: reuses whichever profile you launched last (falls back to work) |
| `claude-profiles-diff` | Shows how the two profiles' *shared* config differs |
| `claude-profiles-sync work-to-personal` \| `personal-to-work` | Reconciles shared config one way (see below) |

All flags pass through (`claude-personal -r`, `claude -c`, ...).

## How config is treated

Profile config falls into three buckets:

- **Volatile / per-profile — never synced:** `model`, `effortLevel`,
  `advisorModel`, `tui`. Each profile keeps its own. (This is why running
  different models per account no longer shows up as constant "drift".)
- **Shared automatically:** `settings.local.json` (the permission allowlist) is
  a single file — personal's is a symlink to work's. An "always allow X" grant
  on either account is there for both. Zero sync, zero churn. If a write ever
  replaces the symlink with a plain file, the next launch merges its grants back
  and restores the link.
- **Shared on demand:** `settings.json`'s non-volatile keys (`hooks`,
  `enabledPlugins`, `permissions`, skip flags) and the plugin **registry**. These
  change only when you deliberately change them, so they are reconciled only when
  you ask — never automatically on launch.

On launch, if the shared-on-demand surface has genuinely drifted, you get a
one-line warning and a `[Y/n]` prompt to reconcile. The direction is chosen from
**the profile you ran last** (the likely source of the change) and is always
shown, e.g. `Sync work→personal now? [Y/n]`. Answer `n` to skip; the full diff
is available via `claude-profiles-diff`. Nothing is ever copied without your
confirmation, and the plugin cache (gigabytes of re-fetchable checkouts) is
never copied — only the registry.

"Work" here just means *whichever account lives in the default `~/.claude`
directory*. The names are labels; pick your own mapping and stay consistent.

## Requirements

- fish shell (3.2+)
- `jq` and `rsync`
- Claude Code installed as a real binary on `$PATH`

## Install (new machine)

```fish
git clone <this-repo> && cd Claude-Acc-Manager
./install.fish     # symlinks claude-profiles.fish into ~/.config/fish/conf.d/
exec fish
```

Then set up the two logins (once each):

1. **Default profile**: plain `claude` → `/login` with account #1.
2. **Second profile**: `claude-personal` → `/login` with account #2.
   Tip: don't let `/login` auto-open the browser — copy the URL and paste it
   into the Chrome profile logged into the right claude.ai account.
3. **Optional** — make the second profile inherit your settings, plugins, and
   session history instead of starting from first-run onboarding:

   ```fish
   ./seed-personal.fish
   ```

   Seeding also establishes the shared `settings.local.json` symlink.

## Browser side

Keep both claude.ai accounts logged in permanently using two Chrome **user
profiles** (avatar menu → Add profile). Each profile is a separate cookie jar,
so there's no logout/relogin fight.

## Tests

```fish
fish --no-config tests/test-profiles.fish
```

Must be run with `--no-config` so fish doesn't load the installed launcher
against your real `~/.claude`. The suite runs against a sandbox `$HOME` and
includes a tripwire asserting your real `~/.claude` is untouched.

## Gotchas learned the hard way

- **Never set `CLAUDE_CONFIG_DIR=~/.claude`** to mean "the default". Once set,
  Claude Code expects its state at `$CLAUDE_CONFIG_DIR/.claude.json`, but the
  default profile keeps it at `~/.claude.json` — so it re-runs onboarding. The
  work launcher runs with the variable explicitly **unset**.
- The plugin registry stores absolute `installPath`s; sync rewrites them.
- Anything launching the `claude` binary directly (IDE extensions, scripts)
  bypasses these fish functions and uses the default profile.
- `.claude.json`, credentials, session history, and caches are never compared
  or synced — they change every run.
```

- [ ] **Step 3: Run the full suite + verify launcher intact**

Run: `fish --no-config tests/test-profiles.fish; and echo SUITE_OK`
Expected: `PASS: N   FAIL: 0` then `SUITE_OK`.

Run: `fish --no-config -c "source claude-profiles.fish; and functions -q claude; and echo LAUNCHER_OK"`
Expected: `LAUNCHER_OK`.

- [ ] **Step 4: Commit**

```bash
git add README.md tests/test-autosync.fish claude-profiles.fish
git commit -m "Rewrite README for v2; remove stale auto-sync test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Empirical write-mode verification (informational)

Determines whether Claude Code writes `settings.local.json` in place (symlink
survives) or via atomic rename (self-heal restores it next launch). The design
is correct either way; this records which path actually runs so we know whether
self-heal ever fires. **Non-blocking** — if it can't be driven headlessly,
record that and rely on the self-heal already tested in Task 6.

**Files:**
- Modify: `docs/superpowers/specs/2026-07-15-profile-sync-redesign-design.md` (append a "Verified" note under §4)

- [ ] **Step 1: Probe the write mode in a throwaway dir**

```fish
set d (mktemp -d)
mkdir -p $d/real $d/prof
echo '{"permissions":{"allow":["Read(*)"]}}' >$d/real/settings.local.json
ln -s $d/real/settings.local.json $d/prof/settings.local.json
# Drive one real permission-adding write, e.g. run a tiny headless task in
# CLAUDE_CONFIG_DIR=$d/prof that approves a tool, or add a permission via the
# in-app settings UI once. Then inspect:
test -L $d/prof/settings.local.json; and echo "IN-PLACE (symlink survived)"; or echo "ATOMIC-RENAME (symlink replaced)"
```

If driving a real write headlessly isn't practical, do it once interactively
(launch `CLAUDE_CONFIG_DIR=$d/prof claude`, approve any "always allow", quit),
then run the `test -L` check.

- [ ] **Step 2: Record the result** — append under §4 of the spec:

```markdown
**Verified (2026-07-15):** Claude Code writes `settings.local.json`
<in place | via atomic rename>. Self-heal therefore <never fires | restores the
symlink on the next launch>. No change to the design.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-15-profile-sync-redesign-design.md
git commit -m "Record empirical settings.local.json write mode

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 three-way classification → Tasks 2 (drift ignores volatile), 3 (merge preserves volatile), 6 (shared local), 5 (on-demand sync). ✔
- §2 launch behavior (ordering, no auto-copy) → Task 8. ✔
- §2 `claude-profiles-sync` (key-merge, registry only, backups) → Task 5. ✔
- §3 `[Y/n]` prompt, direction = last run, timing → Task 8. ✔
- §4 shared `settings.local.json` + self-heal → Task 6; empirical → Task 12. ✔
- §5 drift detection → Task 2. ✔
- §6 `claude-profiles-diff` → Task 7. ✔
- Cleanup/migration (rewrite launcher, update seed/install, delete stale test) → Tasks 8/9/10/11. ✔
- Testing items 1–9 → distributed across Tasks 2,3,5,6,8,11 + tripwire in every run; item 6 (empirical) → Task 12. ✔
- Non-goals (no cache copy, no daemon, no launch-time copy) → enforced by Tasks 5 (registry only), 8 (prompt-gated), 2 (cache never compared). ✔

**Placeholder scan:** No TBD/TODO; all steps carry concrete code/commands. Task 12 is intentionally a manual verification with a documented fallback, not a placeholder.

**Type/name consistency:** `__claude_work_dir`, `__claude_pers_dir`, `__claude_shared`, `__claude_plugin_keys`, `__claude_profile_divergence`, `__claude_merge_settings`, `__claude_rewrite_registry`, `__claude_merge_permissions`, `__claude_share_settings_local`, `__claude_last_profile`, `__claude_prelaunch`, `__claude_run` — names used consistently across tasks. Sync directions are the literal strings `work-to-personal` / `personal-to-work` throughout. Volatile-key list identical in Tasks 2, 3, 7 and the Global Constraints.
