#!/usr/bin/env fish
# Symlinks claude-profiles.fish into fish's conf.d so it loads in every shell.
# Safe to re-run; backs up any existing regular file first.

set -l repo_dir (dirname (realpath (status filename)))
set -l target $HOME/.config/fish/conf.d/claude-profiles.fish

mkdir -p $HOME/.config/fish/conf.d

if test -f $target; and not test -L $target
    mv $target $target.pre-install.bak
    echo "Backed up existing file to $target.pre-install.bak"
end

ln -sf $repo_dir/claude-profiles.fish $target
echo "Installed: $target → $repo_dir/claude-profiles.fish"
echo "Run 'exec fish' (or open a new terminal) to load it."
echo
echo "Panel widget (optional): ./plasmoid/install.fish"
