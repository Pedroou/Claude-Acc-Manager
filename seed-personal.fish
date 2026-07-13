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
#   - Copies settings.json, settings.local.json, history.jsonl, plans/,
#     plugins/, and projects/ (session history + memory).
#   - Rewrites absolute plugin installPaths to point at the personal dir.
#   - Does NOT touch credentials, or work-org managed files
#     (remote-settings.json, policy-limits.json).

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

# 2. Copy configs
for f in settings.json settings.local.json history.jsonl
    test -e $work/$f; and cp -a $work/$f $pers/
end
test -d $work/plans; and rsync -a $work/plans $pers/
echo "  ✓ settings, history, plans copied"

# 3. Plugins (mirror + repoint absolute installPaths)
if test -d $work/plugins
    rsync -a --delete $work/plugins/ $pers/plugins/
    for j in $pers/plugins/*.json
        sed -i "s|$work/plugins|$pers/plugins|g" $j
    end
    echo "  ✓ plugins copied and paths rewritten"
end

# 4. Session history + per-project memory
if test -d $work/projects
    rsync -a $work/projects/ $pers/projects/
    echo "  ✓ projects (sessions + memory) copied"
end

# 5. Arm auto-sync. Until this marker exists the launcher refuses to sync in
#    either direction, because an unseeded profile holds first-run defaults:
#    newest on disk, but nearly empty, so mtime alone would let it win.
touch $pers/.profile-seeded
rm -f $pers/.autosync-declined # clear any earlier "don't ask me" choice
echo "  ✓ auto-sync armed (.profile-seeded)"

set -l email (jq -r '.oauthAccount.emailAddress // "unknown"' $pers/.claude.json)
echo
echo "Done. Personal profile seeded; logged-in account preserved: $email"
echo "Config drift between the profiles will now be reconciled on launch (newest wins)."
