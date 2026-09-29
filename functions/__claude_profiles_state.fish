# The little this tool remembers between runs, one file per key under
# $XDG_STATE_HOME/claude-profiles:
#
#   last           the profile `claude` opens when you don't name one
#   default-name   what the default profile (~/.claude) is called
#   settings.json  the shared settings as of the last merge - the common
#                  ancestor __claude_profiles_merge compares against
#   seen           when each profile's settings.json was last written, as of
#                  that merge, so a launch with nothing new can skip it
#
#   __claude_profiles_state              prints the directory
#   __claude_profiles_state <key>        prints the value, or fails if unset
#   __claude_profiles_state <key> <val>  stores it
#
# Worked out from $HOME on every call rather than cached at load time: the test
# suites move $HOME, and a cached path would quietly keep pointing at the real one.
function __claude_profiles_state -a key value
    set -l dir $HOME/.local/state/claude-profiles
    set -q XDG_STATE_HOME[1]; and set dir $XDG_STATE_HOME/claude-profiles

    if not set -q argv[1]
        echo $dir
    else if set -q argv[2]
        test -d $dir; or mkdir -p $dir
        echo $value >$dir/$key
    else
        test -f $dir/$key; or return 1
        # Not `string trim` on its own: it fails when there was nothing to trim.
        set -l stored (string trim <$dir/$key)
        test -n "$stored"; and echo $stored
    end
end
