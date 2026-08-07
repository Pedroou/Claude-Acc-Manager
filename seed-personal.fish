#!/usr/bin/env fish
# Seeds the personal profile (~/.claude-personal) from the default profile
# (~/.claude + ~/.claude.json) so it doesn't start as a blank first-run setup.
#
# Run this ONCE, on a machine where:
#   1. The default profile is already set up (you've been using plain `claude`).
#   2. You've run `claude-personal` and completed /login in it at least once
#      (that creates its .credentials.json and .claude.json with YOUR identity).
#
# What it does:
#   - Merges ~/.claude.json into ~/.claude-personal/.claude.json, keeping the
#     personal account's identity (oauthAccount, userID, model-access caches)
#     but taking everything else (onboarding flags, tips, per-project state).
#   - Copies settings.json and plans/.
#   - Copies the plugin *registry*, repointing installPaths at the personal dir.
#
# What it deliberately does NOT do:
#   - Copy the plugins/ cache. It is gigabytes of re-fetchable git checkouts and
#     holds per-instance state (.in_use markers); Claude re-fetches what it needs.
#   - Copy settings.local.json, history.jsonl, projects/ or file-history/. Those
#     are *shared* between profiles — the next launch of `claude` replaces them
#     with symlinks into the work profile, so copying them here is pointless
#     work that the launcher would immediately undo.
#   - Touch credentials, or work-org managed files (remote-settings.json,
#     policy-limits.json).

set -l work $HOME/.claude
set -l pers $HOME/.claude-personal

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

echo "Seeding $pers from $work ..."

# 1. Merge state file, preserving the personal account's identity fields
cp -a $pers/.claude.json $pers/.claude.json.pre-seed.bak
jq -s '.[0] * (.[1] | with_entries(select(.key | IN("oauthAccount","userID","modelAccessCache","orgModelDefaultCache","passesEligibilityCache","claudeCodeFirstTokenDate","firstStartTime"))))' \
    $HOME/.claude.json $pers/.claude.json >$pers/.claude.json.new
and mv $pers/.claude.json.new $pers/.claude.json
and chmod 600 $pers/.claude.json
or begin
    echo "Error: state-file merge failed; personal profile left unchanged."
    exit 1
end
echo "  ✓ state file merged (backup: .claude.json.pre-seed.bak)"

# 2. Copy settings.json and plans/. settings.local.json and history.jsonl are
#    shared via symlink by the launcher, so they are not copied here.
test -e $work/settings.json; and cp -a $work/settings.json $pers/
test -d $work/plans; and rsync -a $work/plans $pers/
echo "  ✓ settings.json and plans copied"

# 3. Plugin registry only — repoint absolute installPaths at the personal dir.
#    The cache is never copied; Claude re-fetches any missing checkout once.
set -l reg plugins/installed_plugins.json
if test -e $work/$reg
    mkdir -p $pers/plugins
    jq --arg s "$work/plugins" --arg d "$pers/plugins" '
        .plugins |= with_entries(
            if (.value | type == "object")
               and ((.value.installPath? // "") | startswith($s))
            then .value.installPath = ($d + (.value.installPath[($s | length):]))
            else . end)
    ' $work/$reg >$pers/$reg.tmp
    and mv $pers/$reg.tmp $pers/$reg
    or begin
        rm -f $pers/$reg.tmp
        echo "Error: plugin registry copy failed."
        exit 1
    end
    echo "  ✓ plugin registry copied (cache re-fetched on demand)"
end

set -l email (jq -r '.oauthAccount.emailAddress // "unknown"' $pers/.claude.json)
echo
echo "Done. Personal profile seeded; logged-in account preserved: $email"
echo "Run 'claude' once to establish the shared settings.local.json and session history."
