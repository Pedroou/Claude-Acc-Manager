#!/usr/bin/env fish
# settings.json: the three-way merge that keeps profiles in step.
# MUST run with: fish --no-config
source (dirname (realpath (status filename)))/helpers.fish

function settings -a name json
    set -l dir $HOME/.claude
    test $name = default; or set dir $HOME/.claude-$name
    mkdir -p $dir
    echo $json | jq . >$dir/settings.json
end

function get -a name filter
    set -l dir $HOME/.claude
    test $name = default; or set dir $HOME/.claude-$name
    jq -c $filter $dir/settings.json
end

# Makes a file look older, so a later write is unambiguously the newer one.
function age -a name
    set -l dir $HOME/.claude
    test $name = default; or set dir $HOME/.claude-$name
    touch -d '1 hour ago' $dir/settings.json
end

# Two profiles that have been merged once already: the usual state of things.
function merged_pair
    profile personal
    settings default '{"model": "opus[1m]", "theme": "dark", "hooks": {"Stop": ["a"]}}'
    settings personal '{"model": "sonnet", "theme": "dark", "hooks": {"Stop": ["a"]}}'
    __claude_profiles_merge 2>/dev/null
    age default
    age personal
end

section "Profiles that already agree are left alone, silently"
merged_pair
set -l before (cat $HOME/.claude/settings.json $HOME/.claude-personal/settings.json | md5sum)
set -l said (__claude_profiles_merge 2>&1)
check "nothing said" "" "$said"
check "nothing written" "$before" (cat $HOME/.claude/settings.json $HOME/.claude-personal/settings.json | md5sum)

section "A change made in one profile reaches the other"
merged_pair
settings personal '{"model": "sonnet", "theme": "light", "hooks": {"Stop": ["a"]}}'
set -l said (__claude_profiles_merge 2>&1)
check "the default gets it" '"light"' (get default .theme)
check "and keeps its own model" '"opus[1m]"' (get default .model)
check "says what it did" "claude-profiles: updated default's settings (theme)." "$said"

section "The same works in the other direction, with no direction given"
merged_pair
settings default '{"model": "opus[1m]", "theme": "dark", "hooks": {"Stop": ["b"]}}'
__claude_profiles_merge 2>/dev/null
check "personal gets the default's change" '["b"]' (get personal .hooks.Stop)
check "and keeps its own model" '"sonnet"' (get personal .model)

section "A model change is the account's own business"
merged_pair
settings personal '{"model": "haiku", "effortLevel": "low", "theme": "dark", "hooks": {"Stop": ["a"]}}'
set -l said (__claude_profiles_merge 2>&1)
check "the default's model is untouched" '"opus[1m]"' (get default .model)
check "effortLevel doesn't travel either" null (get default .effortLevel)
check "and nothing is said" "" "$said"

section "Changes to different settings in different profiles both happen"
merged_pair
settings default '{"model": "opus[1m]", "theme": "light", "hooks": {"Stop": ["a"]}}'
settings personal '{"model": "sonnet", "theme": "dark", "hooks": {"Stop": ["a"]}, "tui": "fullscreen"}'
__claude_profiles_merge 2>/dev/null
check "default's theme reached personal" '"light"' (get personal .theme)
check "personal's tui reached default" '"fullscreen"' (get default .tui)
check "the default kept its own theme change" '"light"' (get default .theme)

section "A deletion is a change like any other"
merged_pair
settings personal '{"model": "sonnet", "theme": "dark"}'
__claude_profiles_merge 2>/dev/null
check "the hook is gone from the default too" null (get default .hooks.Stop)
set -l said (__claude_profiles_merge 2>&1)
check "and the empty object it leaves behind isn't a change" "" "$said"

section "Settings are compared at any depth"
merged_pair
settings default '{"model": "opus[1m]", "theme": "dark", "hooks": {"Stop": ["a"], "Notification": ["n"]}}'
settings personal '{"model": "sonnet", "theme": "dark", "hooks": {"Stop": ["z"]}}'
__claude_profiles_merge 2>/dev/null
check "one side's new hook and the other's edited hook both land" \
    '{"Stop":["z"],"Notification":["n"]}' (get default .hooks)
check "on both sides" '{"Stop":["z"],"Notification":["n"]}' (get personal .hooks)

section "Two changes to the same setting: the newer file wins, the other is backed up"
merged_pair
settings default '{"model": "opus[1m]", "theme": "solarized", "hooks": {"Stop": ["a"]}}'
age default
settings personal '{"model": "sonnet", "theme": "light", "hooks": {"Stop": ["a"]}}'
set -l said (__claude_profiles_merge 2>&1)
check "personal's, the newer, is kept" '"light"' (get default .theme)
check "it says so" 1 (count (string match '*theme was changed in personal and in default*' -- $said))
set -l backup $HOME/.claude/backups/settings-*.json
check "the default's version is backed up" '"solarized"' (jq -c .theme $backup)

section "Lists of strings are merged as sets"
profile personal
settings default '{"permissions": {"allow": ["Bash(ls)", "Bash(cat)"]}}'
settings personal '{"permissions": {"allow": ["Bash(ls)", "Bash(cat)"]}}'
__claude_profiles_merge 2>/dev/null
settings default '{"permissions": {"allow": ["Bash(ls)", "Bash(cat)", "Bash(git)"]}}'
settings personal '{"permissions": {"allow": ["Bash(ls)", "Read"]}}'
set -l said (__claude_profiles_merge 2>&1)
check "both additions and the removal survive" '["Bash(ls)","Bash(git)","Read"]' (get default .permissions.allow)
check "on both sides" '["Bash(ls)","Bash(git)","Read"]' (get personal .permissions.allow)
check "and it isn't a conflict" 0 (count (string match '*changed in*' -- $said))

section "The first merge ever is a union"
profile personal
settings default '{"model": "opus", "theme": "dark"}'
settings personal '{"model": "sonnet", "tui": "fullscreen"}'
__claude_profiles_merge 2>/dev/null
check "default gains personal's settings" '{"model":"opus","theme":"dark","tui":"fullscreen"}' (get default .)
check "and personal the default's" '{"model":"sonnet","tui":"fullscreen","theme":"dark"}' (get personal .)

section "A profile with no settings yet is simply given the shared ones"
merged_pair
profile fresh
__claude_profiles_merge 2>/dev/null
check "shared settings, and no model of anyone else's" '{"hooks":{"Stop":["a"]},"theme":"dark"}' (get fresh .)
check "the others are unchanged" '"dark"' (get default .theme)

section "Settings that don't parse stop the merge for everyone"
merged_pair
echo '{"theme": "light",' >$HOME/.claude-personal/settings.json
set -l before (md5sum $HOME/.claude/settings.json)
set -l said (__claude_profiles_merge 2>&1)
check "nothing is written" "$before" (md5sum $HOME/.claude/settings.json)
check "and it says which file" 1 (count (string match "*$HOME/.claude-personal/settings.json*" -- $said))

section "Only the settings that changed are touched"
merged_pair
printf '%s\n' '{' '  "zeta": 1,' '  "model": "opus[1m]",' '  "theme": "dark",' '  "hooks": {"Stop": ["a"]}' '}' \
    >$HOME/.claude/settings.json
__claude_profiles_merge 2>/dev/null
settings personal '{"model": "sonnet", "theme": "light", "hooks": {"Stop": ["a"]}, "zeta": 1}'
__claude_profiles_merge 2>/dev/null
check "the default's key order is kept" '["zeta","model","theme","hooks"]' (get default keys_unsorted)

section "A profile that couldn't be written holds the ancestor back"
merged_pair
settings default '{"model": "opus[1m]", "theme": "light", "hooks": {"Stop": ["a"]}}'
chmod a-w $HOME/.claude-personal
__claude_profiles_merge 2>/dev/null
chmod u+w $HOME/.claude-personal
check "personal missed the change" '"dark"' (get personal .theme)
__claude_profiles_merge 2>/dev/null
check "so the next merge still sees it as the default's change, not personal's" '"light"' (get personal .theme)
check "and doesn't undo it in the default" '"light"' (get default .theme)

section "A settings.json that is a symlink is written through, mode and all"
merged_pair
mkdir -p $ROOT/dotfiles
mv $HOME/.claude-personal/settings.json $ROOT/dotfiles/settings.json
chmod 600 $ROOT/dotfiles/settings.json
ln -s $ROOT/dotfiles/settings.json $HOME/.claude-personal/settings.json
settings default '{"model": "opus[1m]", "theme": "light", "hooks": {"Stop": ["a"]}}'
__claude_profiles_merge 2>/dev/null
check "still a link" link:$ROOT/dotfiles/settings.json (kind $HOME/.claude-personal/settings.json)
check "and the file it points to has the change" '"light"' (jq .theme $ROOT/dotfiles/settings.json)
check "with its mode kept" 600 (stat -c %a $ROOT/dotfiles/settings.json)
echo '{"model": "sonnet", "theme": "solarized", "hooks": {"Stop": ["a"]}}' >$ROOT/dotfiles/settings.json
__claude_profiles_merge 2>/dev/null
check "an edit made through the link is seen" '"solarized"' (get default .theme)

section "A credential in env belongs to its account"
merged_pair
settings personal '{"model": "sonnet", "theme": "dark", "hooks": {"Stop": ["a"]},
                    "env": {"ANTHROPIC_API_KEY": "sk-personal", "EDITOR": "vim"}}'
__claude_profiles_merge 2>/dev/null
check "the key stays where it was set" null (get default .env.ANTHROPIC_API_KEY)
check "the rest of env is shared as usual" '"vim"' (get default .env.EDITOR)

section "Hooks for the same event, changed on both sides, both land"
profile personal
set -l lint '{"matcher": "Edit", "hooks": [{"type": "command", "command": "lint"}]}'
set -l guard '{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard"}]}'
set -l guard2 '{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard --strict"}]}'
set -l fmt '{"matcher": "Write", "hooks": [{"type": "command", "command": "fmt"}]}'
settings default "{\"hooks\": {\"PreToolUse\": [$lint, $guard]}}"
settings personal "{\"hooks\": {\"PreToolUse\": [$lint, $guard]}}"
__claude_profiles_merge 2>/dev/null
settings default "{\"hooks\": {\"PreToolUse\": [$lint, $guard2]}}"
settings personal "{\"hooks\": {\"PreToolUse\": [$lint, $guard, $fmt]}}"
set -l said (__claude_profiles_merge 2>&1)
check "one side's edit and the other's new hook" "fmt guard --strict lint" \
    (get default '[.hooks.PreToolUse[].hooks[].command] | sort | join(" ")' | string trim -c '"')
check "on both sides" "fmt guard --strict lint" \
    (get personal '[.hooks.PreToolUse[].hooks[].command] | sort | join(" ")' | string trim -c '"')
check "and it isn't a conflict" 0 (count (string match '*changed in*' -- $said))

section "Which provider an account talks to is its own"
merged_pair
settings personal '{"model": "sonnet", "theme": "dark", "hooks": {"Stop": ["a"]},
                    "env": {"CLAUDE_CODE_USE_BEDROCK": "1", "AWS_PROFILE": "work"}, "awsAuthRefresh": "aws sso login"}'
__claude_profiles_merge 2>/dev/null
check "none of it reaches the other profile" '{}' (get default '{env, awsAuthRefresh} | with_entries(select(.value != null))')

section "More settings can be made per-account"
merged_pair
set -g claude_profiles_own env.MY_GATEWAY
settings personal '{"model": "sonnet", "theme": "dark", "hooks": {"Stop": ["a"]}, "env": {"MY_GATEWAY": "x"}}'
__claude_profiles_merge 2>/dev/null
check "one named in claude_profiles_own stays put" null (get default .env.MY_GATEWAY)
set -e claude_profiles_own

section "No second profile: nothing to do"
settings default '{"theme": "dark"}'
set -l said (__claude_profiles_merge 2>&1)
check "silent" "" "$said"
check "untouched" '{"theme":"dark"}' (get default .)

finish
