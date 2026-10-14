#!/usr/bin/env fish
# Which profile `claude` starts, and what it hands Claude Code.
# MUST run with: fish --no-config
source (dirname (realpath (status filename)))/helpers.fish

section "Nothing remembered: the default profile, with CLAUDE_CONFIG_DIR unset"
set -gx CLAUDE_CONFIG_DIR $HOME/.claude-leftover
set -e CLAUDE_CONFIG_DIR
claude
check "runs with the variable unset, not set to ~/.claude" "unset|" (launched)

section "A profile named first is started, and remembered"
profile personal
claude personal -r
check "starts personal, with only the rest as arguments" "$HOME/.claude-personal|-r" (launched)
check "remembers it" personal (__claude_profiles_state last)
claude -c
check "the next bare claude starts it again" "$HOME/.claude-personal|-c" (launched)
claude default
check "the default can be named too" "unset|" (launched)
claude
check "and is then the one remembered" "unset|" (launched)

section "Anything that isn't a profile goes to Claude Code as it is"
profile personal
claude personal
claude "fix the tests"
check "a prompt runs in the remembered profile" "$HOME/.claude-personal|fix the tests" (launched)
mkdir $HOME/.claude-junk
claude junk
check "a ~/.claude-* Claude Code never started in isn't a profile" "$HOME/.claude-personal|junk" (launched)
claude ../etc
check "nor is a path" "$HOME/.claude-personal|../etc" (launched)

section "claude help and claude profiles, but only in those exact shapes"
profile personal
check "claude help is claude-help" "$(claude-help)" "$(claude help)"
check "and starts nothing" "" (launched)
claude help me with this
check "help with anything after it is a prompt" "unset|help me with this" (launched)
set -l said (claude profiles | string replace -ra '\e\[[0-9;]*m' '')
check "claude profiles lists them" 1 (count (string match '*personal*' -- $said))
claude profiles add other >/dev/null
check "and takes claude-profiles' commands" $HOME/.claude-other (__claude_profiles_find other)
claude profiles are slow
check "anything else after it is a prompt" "unset|profiles are slow" (launched)
check "and none of it changed what's remembered" 1 (__claude_profiles_state last >/dev/null; echo $status)

section "A renamed default is found by its name"
profile personal
__claude_profiles_state default-name work
claude work --resume abc
check "work is ~/.claude" "unset|--resume abc" (launched)
claude default
check "and 'default' is no longer special" "unset|default" (launched)

section "An explicit CLAUDE_CONFIG_DIR wins over the remembered profile"
profile personal
profile other
__claude_profiles_state last other
CLAUDE_CONFIG_DIR=$HOME/.claude-personal claude --resume abc
check "a copied resume command means what it says" "$HOME/.claude-personal|--resume abc" (launched)
check "without changing what's remembered" other (__claude_profiles_state last)
CLAUDE_CONFIG_DIR=$HOME/.claude claude
check "set to ~/.claude, it is unset instead" "unset|" (launched)
CLAUDE_CONFIG_DIR=$HOME/.claude-personal claude other
check "but naming a profile is more explicit still" "$HOME/.claude-other|" (launched)

section "A remembered profile that no longer exists falls back to the default"
__claude_profiles_state last gone
claude
check "starts the default" "unset|" (launched)

section "Claude Code's exit status comes back out"
set -gx CLAUDE_STUB_STATUS 3
claude
check "status" 3 $status
set -e CLAUDE_STUB_STATUS

section "The launch event"
profile personal
function __on_launch --on-event claude_profiles_launch
    set -g SEEN $argv
end
claude personal
check "fires with the profile's directory" $HOME/.claude-personal "$SEEN"
functions -e __on_launch

section "Profiles are brought into line before the launch"
profile personal
mkdir -p $HOME/.claude/skills
echo '{"theme": "dark"}' >$HOME/.claude/settings.json
claude personal
check "shared entries are linked" link:$HOME/.claude/skills (kind $HOME/.claude-personal/skills)
check "settings are merged" dark (jq -r .theme $HOME/.claude-personal/settings.json)
set -l t0 (date +%s%N)
claude personal
set -l ms (math "($(date +%s%N) - $t0) / 1000000")
echo "  (a launch with nothing to do took $ms ms)"

finish
