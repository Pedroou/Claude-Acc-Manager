#!/usr/bin/env fish
# Install (or update) claude-profiles for the current user.
#
# Links the functions, completions and conf.d snippet into ~/.config/fish, so a
# `git pull` is an update. Safe to re-run. (With fisher, `fisher install
# Pedroou/claude-profiles` does the same job and this script isn't needed.)

set -l here (dirname (realpath (status filename)))
set -l fish_config $HOME/.config/fish
set -q __fish_config_dir[1]; and set fish_config $__fish_config_dir

# Tested for directly rather than by parsing a version string: the `path`
# builtin (fish 3.5) is the thing that would break, and an old fish would
# otherwise fail later with a bare "path: unknown command" on every launch.
if not builtin --names | string match -q path
    echo "✗ This fish is too old: claude-profiles needs the `path` builtin (fish 3.5+)."
    echo "  Yours is $version."
    exit 1
end
for tool in jq rsync
    if not command -q $tool
        echo "✗ $tool is required but not on \$PATH."
        exit 1
    end
end
command -q claude; or echo "! Claude Code isn't on \$PATH yet. Install it, then use `claude` as usual."

for kind in functions completions conf.d
    mkdir -p $fish_config/$kind
    for file in $here/$kind/*.fish
        set -l target $fish_config/$kind/(path basename $file)
        if test -e $target -a ! -L $target
            set -l aside $target.bak
            test -e $aside; and set aside $target.(date +%Y%m%d-%H%M%S).bak
            mv $target $aside
            echo "→ Moved your own $target aside, to $aside"
        end
        ln -sf $file $target
    end
end
echo "→ Linked into $fish_config"

# Upgrading from the version before profiles had names: it called the default
# profile "work" and the other one "personal", remembered the last one in
# ~/.claude-last-profile, and linked a settings.local.json into the second
# profile - which Claude Code never read, since it only looks for that file
# inside a project.
if test -f $HOME/.claude-last-profile
    source $here/functions/__claude_profiles_state.fish
    __claude_profiles_state default-name >/dev/null; or __claude_profiles_state default-name work
    __claude_profiles_state last (string trim <$HOME/.claude-last-profile)
    rm $HOME/.claude-last-profile
    test -L $HOME/.claude-personal/settings.local.json; and rm $HOME/.claude-personal/settings.local.json
    echo "→ Carried over your profiles from the previous version: work (~/.claude) and personal."
end

echo
echo "✓ Installed. Open a new shell, or run: exec fish"
echo
echo "  claude                  Claude Code, in the profile you used last"
echo "  claude <profile> …      in that profile"
echo "  claude-profiles         your profiles, and how to add more"
