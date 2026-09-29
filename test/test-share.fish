#!/usr/bin/env fish
# What profiles share, and how a profile's own copy joins the shared one.
# MUST run with: fish --no-config
source (dirname (realpath (status filename)))/helpers.fish

set -g P $HOME/.claude-personal # reassigned per section, since $HOME moves
function share
    __claude_profiles_share $HOME/.claude-personal
end

section "A new profile links to everything shared that exists"
set P $HOME/.claude-personal
profile personal
mkdir -p $HOME/.claude/projects $HOME/.claude/skills $HOME/.claude/plugins
echo "# mine" >$HOME/.claude/CLAUDE.md
touch $HOME/.claude/history.jsonl
set -l said (share 2>&1)
for entry in projects skills plugins CLAUDE.md history.jsonl
    check "$entry is shared" link:$HOME/.claude/$entry (kind $P/$entry)
end
check "what doesn't exist isn't linked" none (kind $P/agents)
check "the account's own files aren't touched" file (kind $P/.claude.json)
check "and nothing is said" "" "$said"
check "a second run changes nothing" "" (share 2>&1)

section "A profile's own copy moves over when there is no shared one"
set P $HOME/.claude-personal
profile personal
mkdir -p $P/agents
echo reviewer >$P/agents/reviewer.md
share 2>/dev/null
check "it becomes the shared copy" reviewer (cat $HOME/.claude/agents/reviewer.md)
check "and is linked back" link:$HOME/.claude/agents (kind $P/agents)

section "...even while a session is running there"
set P $HOME/.claude-personal
profile personal
running $P 101
mkdir -p $P/commands
share 2>/dev/null
check "a move is safe mid-session" link:$HOME/.claude/commands (kind $P/commands)

section "Two copies of a directory are merged, and every losing version is kept"
set P $HOME/.claude-personal
profile personal
mkdir -p $HOME/.claude/projects/-p $P/projects/-p
echo shared-only >$HOME/.claude/projects/-p/a.jsonl
echo personal-only >$P/projects/-p/b.jsonl
echo old-shared >$HOME/.claude/projects/-p/c.jsonl
echo new-personal >$P/projects/-p/c.jsonl
touch -d '1 day ago' $HOME/.claude/projects/-p/c.jsonl
echo new-shared >$HOME/.claude/projects/-p/d.jsonl
echo old-personal >$P/projects/-p/d.jsonl
touch -d '1 day ago' $P/projects/-p/d.jsonl
echo same >$HOME/.claude/projects/-p/e.jsonl
cp -p $HOME/.claude/projects/-p/e.jsonl $P/projects/-p/e.jsonl
set -l said (share 2>&1)
set -l s $HOME/.claude/projects/-p
check "shared-only file kept" shared-only (cat $s/a.jsonl)
check "personal-only file brought over" personal-only (cat $s/b.jsonl)
check "personal's newer version wins" new-personal (cat $s/c.jsonl)
check "the shared newer version wins" new-shared (cat $s/d.jsonl)
check "now linked" link:$HOME/.claude/projects (kind $P/projects)
set -l backup $HOME/.claude/backups/profiles-*-personal/projects/-p
check "the shared version that lost is backed up" old-shared (cat $backup/c.jsonl)
check "so is personal's" old-personal (cat $backup/d.jsonl)
check "identical files aren't" none (kind $backup/e.jsonl)
check "it says what it merged" 1 (count (string match '*merged personal*own projects*' -- $said))

section "...but not while a session is running in the profile"
set P $HOME/.claude-personal
profile personal
mkdir -p $HOME/.claude/projects $P/projects $HOME/.claude/skills
running $P 202
set -l said (share 2>&1)
check "the merge waits" dir (kind $P/projects)
check "while plain links still happen" link:$HOME/.claude/skills (kind $P/skills)
check "and it says it's waiting" 1 (count (string match '*next time nothing is running*' -- $said))
rm $P/sessions/202.json
share 2>/dev/null
check "once it's idle, it goes ahead" link:$HOME/.claude/projects (kind $P/projects)

section "A record left by a killed session doesn't count as running"
set P $HOME/.claude-personal
profile personal
running $P 303
echo "303 (claude) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 9999" >$CLAUDE_PROFILES_PROC/303/stat
mkdir -p $HOME/.claude/todos $P/todos
share 2>/dev/null
check "a recycled pid is not the session" link:$HOME/.claude/todos (kind $P/todos)
running $P 304
rm -r $CLAUDE_PROFILES_PROC/304
check "nor is a pid that's gone" 0 (__claude_profiles_running $P)

section "Prompt history is merged line by line, in time order"
set P $HOME/.claude-personal
profile personal
printf '%s\n' '{"display":"one","timestamp":1}' '{"display":"three","timestamp":3}' >$HOME/.claude/history.jsonl
printf '%s\n' '{"display":"two","timestamp":2}' '{"display":"three","timestamp":3}' >$P/history.jsonl
share 2>/dev/null
check "both halves, once each, in order" "one two three" (jq -r .display $HOME/.claude/history.jsonl | string join ' ')
check "linked" link:$HOME/.claude/history.jsonl (kind $P/history.jsonl)

section "Two copies of a file: the newer is kept, the other backed up"
set P $HOME/.claude-personal
profile personal
echo "old rules" >$HOME/.claude/CLAUDE.md
touch -d '1 day ago' $HOME/.claude/CLAUDE.md
echo "new rules" >$P/CLAUDE.md
share 2>/dev/null
check "the newer one is shared" "new rules" (cat $HOME/.claude/CLAUDE.md)
check "the older is backed up" "old rules" (cat $HOME/.claude/backups/profiles-*-personal/CLAUDE.md)
profile other
echo same >$HOME/.claude/keybindings.json
echo same >$HOME/.claude-other/keybindings.json
__claude_profiles_share $HOME/.claude-other 2>/dev/null
check "identical copies need no backup" 0 (count $HOME/.claude/backups/profiles-*-other)

section "A link you made yourself is left alone"
set P $HOME/.claude-personal
profile personal
mkdir -p $ROOT/elsewhere $HOME/.claude/skills
ln -s $ROOT/elsewhere $P/skills
share 2>/dev/null
check "still points where you pointed it" link:$ROOT/elsewhere (kind $P/skills)

section "Plugins: what can't be fetched again is kept, the cache is not"
set P $HOME/.claude-personal
profile personal
set -l hub $HOME/.claude/plugins
mkdir -p $hub/cache/mp/both/2.0 $hub/marketplaces/mp $hub/data/both
mkdir -p $P/plugins/cache/mp/both/1.0 $P/plugins/cache/mp/mine/1.0 $P/plugins/marketplaces/mp $P/plugins/marketplaces/extra
mkdir -p $P/plugins/data/both $P/plugins/data/mine
echo mine >$P/plugins/cache/mp/mine/1.0/plugin.json
echo shared-data >$hub/data/both/state
echo personal-data >$P/plugins/data/both/state
touch -d '1 day ago' $P/plugins/data/both/state
echo mine-data >$P/plugins/data/mine/state
jq -n --arg h $hub '{version: 2, plugins: {"both@mp": [{installPath: "\($h)/cache/mp/both/2.0", version: "2.0"}]}}' \
    >$hub/installed_plugins.json
jq -n --arg h $P/plugins '{version: 2, plugins: {
        "both@mp": [{installPath: "\($h)/cache/mp/both/1.0", version: "1.0"}],
        "mine@mp": [{installPath: "\($h)/cache/mp/mine/1.0", version: "1.0"}]}}' \
    >$P/plugins/installed_plugins.json
jq -n --arg h $hub '{mp: {installLocation: "\($h)/marketplaces/mp"}}' >$hub/known_marketplaces.json
jq -n --arg h $P/plugins '{mp: {installLocation: "\($h)/marketplaces/mp"},
                           extra: {installLocation: "\($h)/marketplaces/extra"}}' >$P/plugins/known_marketplaces.json
share 2>/dev/null
set -l reg $hub/installed_plugins.json
check "a plugin installed on both keeps the shared entry" "$hub/cache/mp/both/2.0" (jq -r '.plugins["both@mp"][0].installPath' $reg)
check "one only personal had joins the registry, repointed" "$hub/cache/mp/mine/1.0" (jq -r '.plugins["mine@mp"][0].installPath' $reg)
check "with its files" mine (cat $hub/cache/mp/mine/1.0/plugin.json)
check "the registry keeps its version" 2 (jq .version $reg)
check "a marketplace only personal had joins too" "$hub/marketplaces/extra" (jq -r .extra.installLocation $hub/known_marketplaces.json)
check "personal's stale cached version isn't copied" none (kind $hub/cache/mp/both/1.0)
check "plugin data is merged: the newer version is kept" shared-data (cat $hub/data/both/state)
check "and the older one backed up" personal-data (cat $HOME/.claude/backups/profiles-*-personal/plugins/data/both/state)
check "plugin data only personal had is brought over" mine-data (cat $hub/data/mine/state)
check "and plugins are shared from now on" link:$hub (kind $P/plugins)

finish
