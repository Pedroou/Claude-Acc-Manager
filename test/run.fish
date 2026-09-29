#!/usr/bin/env fish
# Every suite, one after the other; fails if any of them does.
# Usage: fish --no-config test/run.fish [-q]    (-q: failures and totals only)
set -l here (dirname (realpath (status filename)))
set -l failed 0
for suite in $here/test-*.fish
    echo "━━━ "(path basename $suite)
    if contains -- -q $argv
        fish --no-config $suite 2>&1 | string match -r -- '^  ✗.*|^      .*|^\d+ passed.*'
        test $pipestatus[1] -eq 0; or set failed (math $failed + 1)
    else
        fish --no-config $suite; or set failed (math $failed + 1)
    end
end
echo
test $failed -eq 0; and echo "All suites passed."; or echo "$failed suite(s) failed."
test $failed -eq 0
