#!/usr/bin/env fish
# Install (or update) the Claude Sessions panel widget for the current user.
#
# Safe to re-run: it upgrades in place when the widget is already installed, and
# restarts plasmashell only when asked, since that closes any open popups.

set -l here (dirname (realpath (status filename)))
set -l package $here/package
set -l id (jq -r '.KPlugin.Id' $package/metadata.json)

for tool in kpackagetool6 jq fish
    if not command -q $tool
        echo "✗ $tool is required but not on \$PATH."
        exit 1
    end
end

if not test -x $package/contents/scripts/claude-sessions
    echo "✗ $package/contents/scripts/claude-sessions is not executable."
    echo "  Run: chmod +x $package/contents/scripts/claude-sessions"
    exit 1
end

# The widget shells out to this on every refresh; catching a broken collector
# here beats staring at an empty popup later.
if not $package/contents/scripts/claude-sessions >/dev/null
    echo "✗ The collector script failed to run. Fix that before installing."
    exit 1
end

# kpackagetool6 walks every installed plasmoid and complains about each one that
# isn't an applet — other people's widgets, nothing to do with this package. That
# one line is dropped; every other message still gets through.
function __kpt
    kpackagetool6 --type Plasma/Applet $argv 2>&1 \
        | string match -v -- '*does not match requested format*'
    return $pipestatus[1]
end

if contains -- $id (__kpt --list | string trim)
    echo "→ Updating $id"
    __kpt --upgrade $package
else
    echo "→ Installing $id"
    __kpt --install $package
end
or exit $status

echo
echo "✓ Installed."
echo
echo "  Add it: right-click the panel → Add or Manage Widgets… → search \"Claude Sessions\"."
echo
echo "  Already had it on the panel? Plasma caches the old QML, so reload the shell:"
echo "      systemctl --user restart plasma-plasmashell.service"
echo "  (Or: kquitapp6 plasmashell; and kstart plasmashell)"
