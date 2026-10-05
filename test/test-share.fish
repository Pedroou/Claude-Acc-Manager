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

section "Two copies of a session directory are merged, and every losing version is kept"
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

section "Anything else both sides have is set aside, not guessed at"
set P $HOME/.claude-personal
profile personal
echo "shared rules" >$HOME/.claude/CLAUDE.md
echo "personal rules" >$P/CLAUDE.md
printf '%s\n' '{"display":"one"}' >$HOME/.claude/history.jsonl
printf '%s\n' '{"display":"two"}' >$P/history.jsonl
mkdir -p $HOME/.claude/skills/a $P/skills/b
set -l said (share 2>&1)
check "the shared CLAUDE.md stands" "shared rules" (cat $HOME/.claude/CLAUDE.md)
check "personal's is in the backup" "personal rules" (cat $HOME/.claude/backups/profiles-*-personal/CLAUDE.md)
check "so is its history" '{"display":"two"}' (cat $HOME/.claude/backups/profiles-*-personal/history.jsonl)
check "and its skills" dir (kind $HOME/.claude/backups/profiles-*-personal/skills/b)
check "all three are linked now" "link:$HOME/.claude/CLAUDE.md link:$HOME/.claude/history.jsonl link:$HOME/.claude/skills" \
    (string join ' ' (kind $P/CLAUDE.md) (kind $P/history.jsonl) (kind $P/skills))
check "it says what it set aside, and where" 2 (count (string match -r 'had its own|backups/profiles-' -- $said))

section "A link you made yourself is left alone"
set P $HOME/.claude-personal
profile personal
mkdir -p $ROOT/elsewhere $HOME/.claude/skills
ln -s $ROOT/elsewhere $P/skills
share 2>/dev/null
check "still points where you pointed it" link:$ROOT/elsewhere (kind $P/skills)

section "A profile's own plugins are set aside, and the shared ones used"
set P $HOME/.claude-personal
profile personal
mkdir -p $HOME/.claude/plugins/cache/mp/a/2.0 $P/plugins/cache/mp/a/1.0
share 2>/dev/null
check "plugins are shared" link:$HOME/.claude/plugins (kind $P/plugins)
check "the profile's own copy is in the backup" dir (kind $HOME/.claude/backups/profiles-*-personal/plugins/cache/mp/a/1.0)

section "Plugin paths recorded through a profile are pointed at the shared copy"
set P $HOME/.claude-personal
profile personal
set -l hub $HOME/.claude/plugins
mkdir -p $hub
ln -s $hub $P/plugins
jq -n --arg p $P/plugins --arg h $hub '{version: 2, plugins: {
        "a@mp": [{installPath: "\($p)/cache/mp/a/1.0"}],
        "b@mp": [{installPath: "\($h)/cache/mp/b/1.0"}]}}' >$hub/installed_plugins.json
jq -n --arg p $P/plugins '{mp: {installLocation: "\($p)/marketplaces/mp"}}' >$hub/known_marketplaces.json
share 2>/dev/null
check "an installed plugin's path" "$hub/cache/mp/a/1.0" (jq -r '.plugins["a@mp"][0].installPath' $hub/installed_plugins.json)
check "one already right is left as it is" "$hub/cache/mp/b/1.0" (jq -r '.plugins["b@mp"][0].installPath' $hub/installed_plugins.json)
check "a marketplace's path" "$hub/marketplaces/mp" (jq -r .mp.installLocation $hub/known_marketplaces.json)
check "the registry keeps its version" 2 (jq .version $hub/installed_plugins.json)
set -l before (stat -c %Y.%N $hub/installed_plugins.json)
share 2>/dev/null
check "and once right, the file isn't rewritten" "$before" (stat -c %Y.%N $hub/installed_plugins.json)

finish
