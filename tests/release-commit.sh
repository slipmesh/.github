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
exit $fail
