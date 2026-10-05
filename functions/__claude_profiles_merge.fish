# Keep settings.json the same in every profile, except for the settings that
# belong to an account. Runs before every launch; silent unless it changed a file.
#
# settings.json can't simply be shared like the rest, because a few of its
# keys depend on the account - the model your plan can run is the usual one.
# So each profile keeps its own file, and this merges them - three-way, the way
# git merges branches.
#
# The common ancestor is the shared part of settings.json as of the last merge,
# kept in the state directory. A setting one profile has changed since then is
# a change, and it goes to every profile. That is the whole rule, so there is
# no direction to pick and nothing to ask: nobody has to know where a change
# was made, because the ancestor already does. Changes to different settings,
# made in different profiles, simply both happen.
#
# The only thing left to decide is two profiles changing the *same* setting to
# different values. A list - permission rules, the hooks for one event - is
# merged as a set, so both sides' additions and removals survive, and an edited
# entry is one removal and one addition. Anything else goes to the newer file,
# and the other profile's copy is backed up first.
#
# The comparison is per setting, at any depth: an object is a folder of
# settings, while a value that is not an object (arrays included) is one
# setting. Empty objects count as no setting at all, so a key left empty by a
# deletion never reads as a change.
#
# A profile with no settings.json yet has nothing to say, and is simply given
# the shared settings. One whose settings.json doesn't parse stops the merge for
# everyone until it's fixed, rather than being taken as "every setting deleted".
function __claude_profiles_merge
    # What belongs to the account rather than to you: the models your plan can
    # run, and everything that says how this account logs in or which provider
    # it talks to. More can be added, as dotted paths:
    #   set -U claude_profiles_own env.MY_GATEWAY_TOKEN
    set -l own model effortLevel advisorModel \
        forceLoginMethod forceLoginOrgUUID forceLoginGatewayUrl apiKeyHelper \
        awsAuthRefresh awsCredentialExport \
        env.ANTHROPIC_API_KEY env.ANTHROPIC_AUTH_TOKEN env.CLAUDE_CODE_OAUTH_TOKEN \
        env.ANTHROPIC_BASE_URL env.ANTHROPIC_MODEL env.ANTHROPIC_SMALL_FAST_MODEL \
        env.ANTHROPIC_DEFAULT_OPUS_MODEL env.ANTHROPIC_DEFAULT_SONNET_MODEL \
        env.ANTHROPIC_DEFAULT_HAIKU_MODEL \
        env.CLAUDE_CODE_USE_BEDROCK env.CLAUDE_CODE_USE_VERTEX \
        env.AWS_PROFILE env.AWS_REGION env.CLOUD_ML_REGION env.ANTHROPIC_VERTEX_PROJECT_ID \
        $claude_profiles_own
    # As jq paths, [["model"], ["env", "AWS_PROFILE"], …], built without a fork.
    set own '['(string join , -- '["'(string replace -a . '","' -- $own)'"]')']'

    set -l base (__claude_profiles_state)/settings.json
    set -l names
    set -l files
    for line in (__claude_profiles_find)
        set -l profile (string split \t -- $line)
        set -a names $profile[1]
        set -a files $profile[2]/settings.json
    end
    set -l mtimes (__claude_profiles_mtimes $files)

    # Nothing has been written since the last merge: there is nothing to do,
    # and knowing that costs a stat per profile rather than a jq.
    set -l seen (string join ' ' -- $names $mtimes)
    test -f $base; and test "$seen" = (__claude_profiles_state seen; or echo)
    and return 0

    set -l args '{}'
    test -f $base; and set args (string collect <$base)
    for i in (seq (count $names))
        set -l text ''
        test -f $files[$i]; and set text (string collect <$files[$i])
        set -a args $names[$i] $mtimes[$i] "$text"
    end

    set -l out (jq -n -r --argjson own $own '
        # A document as {"[path…]": value}, one entry per setting.
        def settings: if type == "object" then delpaths($own) else {} end
            | [paths(type != "object") as $p | {key: ($p | tojson), value: getpath($p)}]
            | map(select(.key | fromjson | all(type == "string")))  # not inside an array
            | from_entries;

        $ARGS.positional as $a
        | ($a[0] | fromjson? // {} | settings) as $base
        | [range(1; $a | length; 3) as $i
           | {name: $a[$i], mtime: ($a[$i + 1] | tonumber), text: $a[$i + 2]}
           | .doc = (if .text == "" then null else (.text | fromjson? // "invalid") end)
          ] as $profiles

        | if any($profiles[]; .doc == "invalid") then
            $profiles[] | select(.doc == "invalid") | "invalid\t\(.name)"
          else
            [$profiles[] | select(.doc != null) | .flat = (.doc | settings)] as $opinions

            # Every setting anyone has, or had.
            | reduce ([$base | keys[]] + [$opinions[].flat | keys[]] | unique)[] as $k (
                {merged: {}, conflicts: []};
                # [value] when present and [] when absent, so that "deleted" and
                # "set to null" stay two different things.
                (if $base | has($k) then [$base[$k]] else [] end) as $was
                | [$opinions[] | {name, mtime, v: (if .flat | has($k) then [.flat[$k]] else [] end)}
                   | select(.v != $was)] as $changed
                | ([$changed[].v] | unique) as $versions
                | if ($versions | length) == 0 then
                    .merged += (if $was == [] then {} else {($k): $was[0]} end)
                  elif ($versions | length) == 1 then
                    .merged += (if $versions[0] == [] then {} else {($k): $versions[0][0]} end)
                  elif ($was | all(.[]; type == "array")) and all($versions[]; length == 1 and (.[0] | type == "array")) then
                    ($was[0] // []) as $old
                    | ([$versions[][0][] | select(. as $x | $old | index([$x]) | not)] | unique) as $added
                    | ([$old[] | select(. as $x | all($versions[][0]; index([$x]) != null) | not)]) as $removed
                    | .merged += {($k): ([$old[] | select(. as $x | $removed | index([$x]) | not)] + $added)}
                  else
                    ($changed | max_by(.mtime)) as $newest
                    | .merged += (if $newest.v == [] then {} else {($k): $newest.v[0]} end)
                    | .conflicts += [{path: ($k | fromjson | join(".")), kept: $newest.name,
                                      lost: [$changed[] | select(.v != $newest.v) | .name]}]
                  end)
            | . as {merged: $merged, conflicts: $conflicts}

            # Each profile gets the merged settings plus its own, edited in place
            # so that its key order - and anything we have no opinion on - stays put.
            | ($profiles[]
               | (.doc // {}) as $doc
               | ($doc | settings) as $mine
               | [$mine | keys[] | select(. as $k | $merged | has($k) | not)] as $gone
               | [$merged | to_entries[] | select(. as $e | $mine | has($e.key) and .[$e.key] == $e.value | not)] as $set
               | select(($gone | length) + ($set | length) > 0)
               | ([$gone[], $set[].key] | map(fromjson | .[0]) | unique | join(", ")) as $what
               | ($doc | delpaths([$gone[] | fromjson])
                  | reduce $set[] as $e (.; setpath($e.key | fromjson; $e.value))) as $new
               | "write\t\(.name)\t\($what)\t\($new | tojson)"),
              ($conflicts[] | "conflict\t\(.path)\t\(.kept)\t\(.lost | join(", "))"),
              (select($merged != $base)
               | "base\t\(reduce ($merged | to_entries[]) as $e ({}; setpath($e.key | fromjson; $e.value)) | tojson)")
          end' --args $args)
    or return 1

    set -l stamp (date +%Y%m%d-%H%M%S)
    set -l losers
    set -l new_base
    for line in $out
        set -l f (string split -m 3 \t -- $line)
        switch $f[1]
            case conflict
                echo "claude-profiles: $f[2] was changed in $f[3] and in $f[4]; kept $f[3]'s, the newer one." >&2
                set -a losers (string split ', ' -- $f[4])
            case invalid
                echo "claude-profiles: $f[2]'s settings.json isn't valid JSON, so settings aren't being" >&2
                echo "                 kept in step until it is. File: "(__claude_profiles_find $f[2])/settings.json >&2
                return 1
            case base
                set new_base $f[2]
        end
    end

    # Whether every profile now holds the merged settings. If one doesn't, the
    # ancestor must stay as it was: moving it on would turn that profile's
    # stale values into what looks like a fresh change, and undo the others'.
    set -l settled true
    for line in $out
        set -l f (string split -m 3 \t -- $line)
        test $f[1] = write; or continue
        set -l i (contains -i -- $f[2] $names)
        set -l file $files[$i]

        # A session may have written this file since it was read. If so, leave
        # it: its change is merged at the next launch, not lost now.
        if test (__claude_profiles_mtimes $file) != $mtimes[$i]
            set settled false
            continue
        end
        set -l dir (path dirname $file)
        if contains -- $f[2] $losers
            mkdir -p $dir/backups
            and cp -L $file $dir/backups/settings-$stamp.json
            and echo "                 $f[2]'s previous settings: $dir/backups/settings-$stamp.json" >&2
            or begin
                set settled false
                continue
            end
        end
        if not __claude_profiles_write $file $f[4]
            set settled false
            continue
        end
        echo "claude-profiles: updated $f[2]'s settings ($f[3])." >&2
    end

    test $settled = true; or return 1
    if set -q new_base[1]
        __claude_profiles_write $base $new_base; or return 1
    else if not test -f $base
        __claude_profiles_write $base '{}'; or return 1
    end
    __claude_profiles_state seen (string join ' ' -- $names (__claude_profiles_mtimes $files))
end

# Replace a JSON file's contents atomically, pretty-printed the way Claude Code
# writes it. A settings.json that is a symlink - into a dotfiles repository,
# say - is written through rather than replaced, and the file keeps its mode.
# The temporary file is this shell's own, so two launches at once can't mix.
function __claude_profiles_write -a file json
    set -l target (path resolve -- $file)
    set -l tmp $target.$fish_pid.tmp
    mkdir -p (path dirname $target); or return
    printf '%s' $json | jq --indent 2 . >$tmp
    and begin
        test -e $target; and chmod --reference=$target $tmp
        true
    end
    and mv $tmp $target
    or begin
        rm -f $tmp
        return 1
    end
end

# The modification time of each file, to the nanosecond, 0 for one that doesn't
# exist - one per argument, in order, following symlinks. Not `path mtime`, which counts whole
# seconds: a change made in the same second as a merge would look like no change.
function __claude_profiles_mtimes
    set -l existing (path filter -f -- $argv)
    set -l stamps
    set -q existing[1]; and set stamps (stat -L -c %.9Y -- $existing)
    for file in $argv
        if set -l i (contains -i -- $file $existing)
            echo $stamps[$i]
        else
            echo 0
        end
    end
end
