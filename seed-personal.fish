#!/usr/bin/env fish
# Bootstraps the personal profile (~/.claude-personal) from the default profile
# (~/.claude + ~/.claude.json) so a freshly logged-in second account doesn't
# start at first-run defaults: no settings, no plugins, onboarding wizard again.
#
# Run it once, after:
#   1. The default profile is set up (you've been using plain `claude`).
#   2. You've run `claude-personal` and completed /login there at least once
#      (that creates its .credentials.json and .claude.json with YOUR identity).
#
# Safe to re-run: nothing here overwrites a value the personal profile chose for
# itself. Re-running is simply redundant once seeded.
#
# The only thing this script does by itself is merge the state file
# (~/.claude.json) — nothing else in the project touches it. Everything else is
# delegated to the same functions the launcher and `claude-profiles-sync` use,
# so seeding can never drift from normal operation:
#
#   __claude_share_settings_local  → shared permission allowlist (symlink)
#   __claude_share_sessions        → shared projects/, file-history/, history.jsonl
#   claude-profiles-sync           → settings.json key-merge + plugin registry
#
# It never touches credentials, the plugin cache, or work-org managed files
# (remote-settings.json, policy-limits.json).

set -l repo (dirname (realpath (status filename)))
if not test -f $repo/claude-profiles.fish
    echo "Error: claude-profiles.fish not found next to this script ($repo)."
    exit 1
end
source $repo/claude-profiles.fish

set -l pers (__claude_pers_dir)

for dep in jq rsync
    if not command -q $dep
        echo "Error: '$dep' is required. Install it first."
        exit 1
    end
end

if not test -f $HOME/.claude.json
    echo "Error: ~/.claude.json not found — the default profile isn't set up yet."
    exit 1
end
if not test -f $pers/.credentials.json; or not test -f $pers/.claude.json
    echo "Error: personal profile not initialized."
    echo "Run 'claude-personal' and complete /login once, then re-run this script."
    exit 1
end

echo "Seeding $pers ..."

# 1. State file — the one job unique to this script.
#
# Overlay the default profile's *non-identity* keys onto the personal profile's
# own state: work wins on keys both hold (that is the point of seeding), keys
# only the personal profile has are preserved, and its identity is untouched
# because those keys are stripped from the work side. Merging the other way
# round — work as the base — would silently drop personal-only state whenever
# this script is re-run.
set -l identity '.oauthAccount, .userID, .modelAccessCache, .orgModelDefaultCache, .passesEligibilityCache, .claudeCodeFirstTokenDate, .firstStartTime'
cp -a $pers/.claude.json $pers/.claude.json.pre-seed.bak
jq -s "(.[1]) * (.[0] | del($identity))" $HOME/.claude.json $pers/.claude.json >$pers/.claude.json.new
and mv $pers/.claude.json.new $pers/.claude.json
and chmod 600 $pers/.claude.json
or begin
    rm -f $pers/.claude.json.new
    echo "Error: state-file merge failed; personal profile left unchanged."
    exit 1
end
echo "  ✓ state file merged, personal identity preserved (backup: .claude.json.pre-seed.bak)"

# 2. Shared surfaces. The launcher does this on every start anyway; doing it here
#    means a seeded profile is fully set up without needing a launch first.
__claude_share_settings_local
or begin
    echo "Error: could not establish the shared settings.local.json."
    exit 1
end
__claude_share_sessions
or begin
    echo "Error: could not share session history."
    exit 1
end
echo "  ✓ allowlist and session history shared with the default profile"

# 3. Shared-on-demand surface. Reuses the sync command wholesale, so seeding
#    inherits its key-merge (the personal profile keeps its own model, effort,
#    advisor and tui) and its backups.
echo
if not claude-profiles-sync work-to-personal
    echo
    echo "Error: sync reported the profiles are still out of step (see above)."
    exit 1
end

set -l email (jq -r '.oauthAccount.emailAddress // "unknown"' $pers/.claude.json)
echo
echo "Done. Logged-in account preserved: $email"
echo "Note: 'model' is per-profile and never copied, so a freshly seeded profile"
echo "uses the default model until you set one with /model."
