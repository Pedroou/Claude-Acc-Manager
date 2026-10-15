#!/usr/bin/env fish
# claude-profiles: list, add, remove, rename - and install.fish.
# MUST run with: fish --no-config
source (dirname (realpath (status filename)))/helpers.fish

# The listing without its colours (fish 3 resets them with \e(B\e[m, fish 4
# with \e[m), one line per profile - and without the
# pointer to claude-help under it.
function listing
    claude-profiles | string replace -ra '\e(\[[0-9;]*m|\(B)' '' | string match -rv '^$|claude-help'
end

section "The list: every profile, its account, and the one claude opens"
profile personal me@home.example
profile unused
__claude_profiles_state last personal
running $HOME/.claude 11
running $HOME/.claude 12
set -l rows (listing)
check "one row per profile, default first" 3 (count $rows)
check "the default, its account, and what's running" 1 \
    (count (string match -r '^  default +me@work\.example +~/\.claude +2 running$' -- $rows[1]))
check "the remembered one is marked" 1 \
    (count (string match -r '^● personal +me@home\.example +~/\.claude-personal *$' -- $rows[2]))
check "a profile nobody has logged into says so" 1 (count (string match '*unused*not logged in*' -- $rows[3]))
__claude_profiles_state last gone
check "with nothing valid remembered, the default is marked" 1 (count (string match '● default*' -- (listing)[1]))
set -l said (claude-profiles | string replace -ra '\e(\[[0-9;]*m|\(B)' '')
check "and under it, where the rest of the commands are" "Run 'claude-help' to see all commands." "$said[-1]"

section "add: a new profile, set up like the others, logged into nothing"
mkdir -p $HOME/.claude/skills
echo '{"theme": "dark", "model": "opus"}' >$HOME/.claude/settings.json
jq -n '{oauthAccount: {emailAddress: "me@work.example"}, userID: "u1",
        hasCompletedOnboarding: true, theme: "dark",
        projects: {"/code/app": {hasTrustDialogAccepted: true, lastCost: 3}}}' >$HOME/.claude.json
set -l said (claude-profiles add personal)
set -l state $HOME/.claude-personal/.claude.json
check "it exists, and is a profile" $HOME/.claude-personal (__claude_profiles_find personal)
check "onboarding is already done" true (jq .hasCompletedOnboarding $state)
check "trusted folders stay trusted" true (jq '.projects["/code/app"].hasTrustDialogAccepted' $state)
check "but nothing else about a project comes along" null (jq '.projects["/code/app"].lastCost' $state)
check "and nothing about the account" null (jq -c '[.oauthAccount, .userID] | map(select(. != null)) | first' $state)
check "the state file is private" 600 (stat -c %a $state)
check "what's shared is linked" link:$HOME/.claude/skills (kind $HOME/.claude-personal/skills)
check "the shared settings are there, not the model" '{"theme":"dark"}' (jq -c . $HOME/.claude-personal/settings.json)
check "it says how to log in" 1 (count (string match '*claude personal, then /login*' -- $said))

section "add refuses names that can't work"
profile taken
claude-profiles add Personal 2>/dev/null
check "not lowercase" 1 $status
claude-profiles add ../x 2>/dev/null
check "not a path" 1 $status
claude-profiles add taken 2>/dev/null
check "not one that exists" 1 $status
claude-profiles add default 2>/dev/null
check "not the default's" 1 $status
set -l said (claude-profiles add plugins 2>&1)
check "not one of Claude Code's commands, asked of Claude Code" 1 \
    (count (string match "*one of Claude Code's own commands*" -- $said))
claude-profiles add help 2>/dev/null
check "not help, which is claude-help" 1 $status
claude-profiles add profiles 2>/dev/null
check "nor profiles, which is claude-profiles" 1 $status
claude-profiles add
check "and a name is needed" 2 $status

section "remove: the login goes, nothing shared does"
profile personal
mkdir -p $HOME/.claude/projects/-p
echo transcript >$HOME/.claude/projects/-p/s.jsonl
__claude_profiles_share $HOME/.claude-personal
__claude_profiles_state last personal
echo n | claude-profiles remove personal >/dev/null
check "answering no keeps it" dir (kind $HOME/.claude-personal)
echo y | claude-profiles remove personal >/dev/null
check "answering yes removes it" none (kind $HOME/.claude-personal)
check "and says where the rest went" 1 (count $HOME/.claude/backups/removed-personal-*)
check "the shared transcripts are still there" transcript (cat $HOME/.claude/projects/-p/s.jsonl)
check "claude goes back to the default" default (__claude_profiles_state last)

section "remove won't take the default, or a profile in use"
profile busy
running $HOME/.claude-busy 55
echo y | claude-profiles remove busy 2>/dev/null
check "a running profile stays" dir (kind $HOME/.claude-busy)
echo y | claude-profiles remove default 2>/dev/null
check "the default stays" dir (kind $HOME/.claude)
echo y | claude-profiles remove nobody 2>/dev/null
check "no such profile is an error" 1 $status

section "remove keeps everything but the login"
profile personal
mkdir -p $HOME/.claude/projects
echo '{"theme": "dark"}' >$HOME/.claude/settings.json
__claude_profiles_share $HOME/.claude-personal
__claude_profiles_merge 2>/dev/null
mkdir -p $HOME/.claude-personal/skills/mine
echo skill >$HOME/.claude-personal/skills/mine/SKILL.md
echo '{"theme": "light"}' >$HOME/.claude-personal/settings.json
echo secret >$HOME/.claude-personal/.credentials.json
echo y | claude-profiles remove personal >/dev/null 2>&1
check "its own skill joins the shared copy" skill (cat $HOME/.claude/skills/mine/SKILL.md)
check "a setting it changed since its last launch is merged" '"light"' (jq .theme $HOME/.claude/settings.json)
set -l kept $HOME/.claude/backups/removed-personal-*
check "what's left is kept aside" file (kind $kept/.claude.json)
check "except the login" none (kind $kept/.credentials.json)
check "and the links into the shared copy" none (kind $kept/projects)
check "while the shared copy itself is untouched" dir (kind $HOME/.claude/projects)

section "rename"
profile personal
__claude_profiles_state last personal
claude-profiles rename personal home >/dev/null
check "the directory moves" dir (kind $HOME/.claude-home)
check "the old one is gone" none (kind $HOME/.claude-personal)
check "and claude still opens it" home (__claude_profiles_state last)
set -l hub $HOME/.claude/plugins
mkdir -p $hub
jq -n --arg p $HOME/.claude-home/plugins '{plugins: {"a@mp": [{installPath: "\($p)/cache/a"}]}}' >$hub/installed_plugins.json
claude-profiles rename home other >/dev/null
check "plugin paths recorded through the old name are pointed at the shared copy" "$hub/cache/a" \
    (jq -r '.plugins["a@mp"][0].installPath' $hub/installed_plugins.json)
claude-profiles rename other home >/dev/null
claude-profiles rename default work >/dev/null
check "the default can be renamed" $HOME/.claude (__claude_profiles_find work)
check "which is only a name: ~/.claude stays put" dir (kind $HOME/.claude)
claude-profiles rename work home 2>/dev/null
check "not to a name that's taken" 1 $status

section "claude-<profile>: one per profile, kept up by add, remove and rename"
profile personal
__claude_profiles_state default-name work
__claude_profiles_shortcuts
check "one for each profile, the default by its name" "claude-work claude-personal" "$__claude_profiles_shortcuts"
claude-personal -r
check "claude-personal is claude personal" "$HOME/.claude-personal|-r" (launched)
claude-work
check "claude-work is the default" "unset|" (launched)
claude-profiles add home >/dev/null
check "add makes one" 0 (functions -q claude-home; echo $status)
claude-profiles rename home away >/dev/null
check "rename moves it" "1 0" "$(functions -q claude-home; echo $status) $(functions -q claude-away; echo $status)"
echo y | claude-profiles remove away >/dev/null
check "remove takes it away" 1 (functions -q claude-away; echo $status)
check "claude-profiles itself is never replaced" 1 (count (functions claude-profiles | string match '*__claude_profiles_list*'))
function claude-taken; echo mine; end
profile taken
__claude_profiles_shortcuts
check "nor a claude-<name> that was there first" mine (claude-taken)
functions -e claude-taken
profile gone
__claude_profiles_shortcuts
rm -r $HOME/.claude-gone # removed by another shell
set -l said (claude-gone 2>&1)
check "one to a profile removed elsewhere says so" 1 $status
check "rather than starting Claude Code" "" (launched)
check "and why" 1 (count (string match "*no profile called 'gone'*" -- $said))

section "install.fish, including an upgrade from the version before names"
set -l cfg $HOME/.config
mkdir -p $cfg/fish/conf.d
ln -s $ROOT/gone/claude-profiles.fish $cfg/fish/conf.d/claude-profiles.fish # v1's link, dangling
echo personal >$HOME/.claude-last-profile
profile personal
ln -s $HOME/.claude/settings.local.json $HOME/.claude-personal/settings.local.json
env HOME=$HOME XDG_CONFIG_HOME=$cfg XDG_STATE_HOME=$XDG_STATE_HOME fish --no-config $REPO/install.fish >/dev/null
check "functions are linked" link:$REPO/functions/claude.fish (kind $cfg/fish/functions/claude.fish)
check "completions are linked" link:$REPO/completions/claude-profiles.fish (kind $cfg/fish/completions/claude-profiles.fish)
check "the old conf.d link is replaced" link:$REPO/conf.d/claude-profiles.fish (kind $cfg/fish/conf.d/claude-profiles.fish)
check "the default keeps the name it had" work (__claude_profiles_state default-name)
check "and the last profile is remembered" personal (__claude_profiles_state last)
check "the old marker is gone" none (kind $HOME/.claude-last-profile)
check "and so is the link Claude Code never read" none (kind $HOME/.claude-personal/settings.local.json)
env HOME=$HOME XDG_CONFIG_HOME=$cfg XDG_STATE_HOME=$XDG_STATE_HOME fish --no-config $REPO/install.fish >/dev/null
check "running it again is fine" 0 $status

finish
