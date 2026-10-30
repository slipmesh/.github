#!/usr/bin/env bash
# Which pushed commits release-commit.yml takes for a release, and with which version.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/release-commit.yml version version) || { echo "FAIL: no step version"; exit 1; }

# expect <commit message> <version, or empty> <prerelease, or empty>
expect() {
  out=$(mktemp)
  MESSAGE=$1 GITHUB_OUTPUT=$out bash -euo pipefail -c "$script" >/dev/null
  check "${1%%$'\n'*}" "$2 $3" "$(sed -n 's/^version=//p' "$out") $(sed -n 's/^prerelease=//p' "$out")"
}
expect 'chore: release v1.14.6+sm.1 (#25)'        v1.14.6+sm.1         false
expect 'chore: release v1.14.6+sm.1'              v1.14.6+sm.1         false
expect 'chore: release v0.2.5 (#9)'               v0.2.5               false
expect 'chore: release v1.15.0-alpha.1+sm.1 (#3)' v1.15.0-alpha.1+sm.1 true
expect 'chore: release v0.3.0-rc.1'               v0.3.0-rc.1          true
expect $'chore: release v1.14.6+sm.2 (#30)\n\nbody text' v1.14.6+sm.2  false
expect 'feat: build against Talos v1.14.6 (#24)'  '' ''
expect 'chore(deps): release v1.2.3'              '' ''
expect 'chore: release notes for v1.2.3'          '' ''
expect 'chore: release v1.2.3 and more'           '' ''
expect 'Revert "chore: release v1.2.3"'           '' ''

latest_script=$(step .github/workflows/release-commit.yml version latest) || { echo "FAIL: no step latest"; exit 1; }
remote=$(mktemp -d)
scratch_repo "$remote"
git -C "$remote" commit -q --allow-empty -m init

# latest <tags already pushed> <version> <prerelease> <latest, or empty>
latest() {
  git -C "$remote" tag -l | xargs -r git -C "$remote" tag -d >/dev/null
  for t in $1; do git -C "$remote" tag "$t"; done
  out=$(mktemp)
  VERSION=$2 PRERELEASE=$3 REMOTE=$remote GITHUB_OUTPUT=$out \
    bash -euo pipefail -c "$latest_script" >/dev/null
  check "$2 over [$1]" "$4" "$(sed -n 's/^latest=//p' "$out")"
}
latest 'v0.4.0'                                  v1.14.5+sm.1  false true
latest 'v1.14.5+sm.2'                            v1.14.5+sm.10 false true
latest 'v1.15.0+sm.1 v1.14.5+sm.1'               v1.14.5+sm.2  false false
latest 'v1.15.0-alpha.1+sm.1 v1.14.5+sm.1'       v1.14.5+sm.2  false true
latest 'v1.14.5+sm.2'                            v1.14.5+sm.2  false true
latest 'v1.14.5+sm.1'                   v1.15.0-beta.1+sm.1    true  false
latest 'v0.1.9'                                  v0.1.10       false true
latest 'v0.1.10'                                 v0.1.9        false false
latest ''                                        v0.1.0        false true
latest 'v1.14.5+sm.1'                            ''            ''    ''
exit $fail
