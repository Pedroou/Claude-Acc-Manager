# Shared by every suite. Each one runs the real functions against a throwaway
# $HOME, a throwaway /proc and a stand-in `claude`, then checks that the real
# profiles were never touched.
#
# MUST run with: fish --no-config

set -g REPO (dirname (dirname (realpath (status filename))))
set -p fish_function_path $REPO/functions
set -g PASS 0
set -g FAIL 0

# Tripwire. The real profiles change on their own - every live session writes
# to them - so this doesn't fingerprint their contents; it fingerprints what
# this suite could plausibly break: which entries exist and what kind they are
# (a directory quietly replaced by a link shows up), the settings files, and
# the state directory. Taken before anything moves $HOME: a hardcoded path, or
# one read afterwards, would leave the check guarding nothing.
function __real_fingerprint -a home
    # Collected with `set` first: a glob matching nothing is an error as a
    # command argument, and would abort the find - leaving nothing guarded.
    set -l profiles $home/.claude $home/.claude-*
    set -l settings $home/.claude/settings.json $home/.claude-*/settings.json
    begin
        find $profiles -mindepth 1 -maxdepth 1 -printf '%y %p\n' 2>/dev/null | sort
        cat $settings 2>/dev/null
        find $home/.local/state/claude-profiles -printf '%y %p %s\n' 2>/dev/null | sort
    end | md5sum
end
set -g REAL_HOME $HOME
set -g REAL_FP (__real_fingerprint $REAL_HOME)

function check -a name expected actual
    if test "$expected" = "$actual"
        set PASS (math $PASS + 1)
        echo "  ✓ $name"
    else
        set FAIL (math $FAIL + 1)
        echo "  ✗ $name"
        echo "      expected: [$expected]"
        echo "      actual:   [$actual]"
    end
end

function section -a title
    echo
    echo "═══ $title ═══"
    setup
end

# A fresh machine with a default profile and nothing else. The stand-in claude
# records the profile it was started in and its arguments, and answers --help
# with a slice of the real command list.
function setup
    set -g ROOT (mktemp -d)
    set -gx HOME $ROOT/home
    set -gx XDG_STATE_HOME $HOME/.local/state
    set -gx CLAUDE_PROFILES_PROC $ROOT/proc
    set -e CLAUDE_CONFIG_DIR
    mkdir -p $HOME/.claude $ROOT/proc $ROOT/bin
    echo '{"oauthAccount": {"emailAddress": "me@work.example"}}' >$HOME/.claude.json

    printf '%s\n' '#!/bin/sh' \
        'if [ "$1" = --help ]; then' \
        '  printf "Commands:\n  mcp                 Configure MCP servers\n  plugin|plugins      Manage plugins\n  doctor              Check the health\n"' \
        '  exit 0' \
        'fi' \
        'echo "${CLAUDE_CONFIG_DIR-unset}|$*" >"$HOME/launched"' \
        'exit ${CLAUDE_STUB_STATUS:-0}' >$ROOT/bin/claude
    chmod +x $ROOT/bin/claude
    contains -- $ROOT/bin $PATH; or set -gx PATH $ROOT/bin $PATH
end

# A second profile Claude Code has already started in.
function profile -a name email
    mkdir -p $HOME/.claude-$name
    if test -n "$email"
        jq -n --arg e $email '{oauthAccount: {emailAddress: $e}}' >$HOME/.claude-$name/.claude.json
    else
        echo '{}' >$HOME/.claude-$name/.claude.json
    end
end

# Pretend a session is running in `dir`: a record, and a process to match it.
function running -a dir pid
    mkdir -p $dir/sessions $CLAUDE_PROFILES_PROC/$pid
    echo "{\"pid\": $pid, \"procStart\": \"4242\"}" >$dir/sessions/$pid.json
    echo "$pid (claude) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 4242" >$CLAUDE_PROFILES_PROC/$pid/stat
end

function launched
    cat $HOME/launched 2>/dev/null
    rm -f $HOME/launched
end

function kind -a p
    if test -L $p
        echo link:(readlink $p)
    else if test -d $p
        echo dir
    else if test -f $p
        echo file
    else
        echo none
    end
end

function finish
    echo
    echo "═══ Tripwire: the real profiles are untouched ═══"
    check "real ~/.claude, ~/.claude-* and state unchanged" $REAL_FP (__real_fingerprint $REAL_HOME)
    echo
    echo "$PASS passed, $FAIL failed"
    test $FAIL -eq 0
end
