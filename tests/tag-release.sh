#!/usr/bin/env bash
# tag-release.yml against a scratch repository and its bare origin: it tags once, a rerun is a
# no-op, and a version that already tags another commit fails.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
yml=$(pwd)/.github/workflows/tag-release.yml
script=$(step "$yml" tag tag) || { echo "FAIL: no step tag"; exit 1; }

work=$(mktemp -d)
git init -q --bare "$work/origin.git"
scratch_repo "$work/repo"; cd "$work/repo"
git remote add origin "$work/origin.git"
git commit -q --allow-empty -m one; c1=$(git rev-parse HEAD)
git commit -q --allow-empty -m two; c2=$(git rev-parse HEAD)
git push -q origin main

# run <version>: exit status of the step for c2
run() { VERSION=$1 GITHUB_SHA=$c2 bash -euo pipefail -c "$script" >/dev/null 2>&1; echo $?; }
tagged() { git ls-remote origin "refs/tags/$1" "refs/tags/$1^{}" | tail -1 | cut -f1; }

check "tags a new version"            "0 $c2" "$(run v1.0.0+sm.1) $(tagged v1.0.0+sm.1)"
check "creates an annotated tag"      "tag"   "$(git -C "$work/origin.git" cat-file -t v1.0.0+sm.1 2>/dev/null)"
check "rerun on the same commit"      "0 $c2" "$(run v1.0.0+sm.1) $(tagged v1.0.0+sm.1)"
git tag v1.0.0+sm.2 "$c1" && git push -q origin v1.0.0+sm.2
check "version tags another commit"   "1 $c1" "$(run v1.0.0+sm.2) $(tagged v1.0.0+sm.2)"
git tag v1.0.0+sm.3 "$c2" && git push -q origin v1.0.0+sm.3
check "lightweight tag on the commit" "0 $c2" "$(run v1.0.0+sm.3) $(tagged v1.0.0+sm.3)"
exit $fail
