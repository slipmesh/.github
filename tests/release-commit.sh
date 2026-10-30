#!/usr/bin/env bash
# Which pushed commits release-commit.yml takes for a release, and with which version.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/release-commit.yml version version) || { echo "FAIL: no step version"; exit 1; }

remote=$(mktemp -d)
scratch_repo "$remote"
git -C "$remote" commit -q --allow-empty -m one; c1=$(git -C "$remote" rev-parse HEAD)
git -C "$remote" commit -q --allow-empty -m two; c2=$(git -C "$remote" rev-parse HEAD)

# version_step <commit message>: runs the step for c2, prints "<version> <prerelease>", or
# "failed" when the step fails
version_step() {
  out=$(mktemp)
  MESSAGE=$1 REMOTE=$remote GITHUB_SHA=$c2 GITHUB_OUTPUT=$out \
    bash -euo pipefail -c "$script" >/dev/null 2>&1 || { echo failed; return; }
  echo "$(sed -n 's/^version=//p' "$out") $(sed -n 's/^prerelease=//p' "$out")"
}
# expect <commit message> <version, or empty> <prerelease, or empty>
expect() { check "${1%%$'\n'*}" "$2 $3" "$(version_step "$1")"; }
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

# A release commit whose tag is already pushed was built and released by an earlier run; a run
# that sees it again (a branch cut from it, a full rerun) must not rebuild and re-release it.
git -C "$remote" tag -a v0.2.5 -m v0.2.5 "$c2"
check "already tagged on this commit"    " "      "$(version_step 'chore: release v0.2.5 (#9)')"
git -C "$remote" tag v0.2.6 "$c2"
check "lightweight tag on this commit"   " "      "$(version_step 'chore: release v0.2.6 (#10)')"
git -C "$remote" tag -a v0.2.7 -m v0.2.7 "$c1"
check "version tags another commit"      "failed" "$(version_step 'chore: release v0.2.7 (#11)')"
check "unreadable tags fail the version" "failed" "$(remote=$remote.missing version_step 'chore: release v0.2.8')"
git -C "$remote" tag -l | xargs -r git -C "$remote" tag -d >/dev/null

latest_script=$(step .github/workflows/release-commit.yml version latest) || { echo "FAIL: no step latest"; exit 1; }

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

out=$(mktemp)
VERSION=v1.14.5+sm.1 PRERELEASE=false REMOTE=$remote.missing GITHUB_OUTPUT=$out \
  bash -euo pipefail -c "$latest_script" >/dev/null 2>&1 && rc=passed || rc=failed
check "unreadable tags fail the step" "failed " "$rc $(sed -n 's/^latest=//p' "$out")"
exit $fail
