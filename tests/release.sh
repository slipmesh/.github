#!/usr/bin/env bash
# The GitHub Release step of release.yml, with gh and git-cliff replaced on PATH: the flags it
# creates the release with, and that a rerun uploads the assets again instead of failing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/release.yml github-release release) || { echo "FAIL: no step release"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# gh records its arguments; `gh release view` succeeds when $EXISTS is set.
cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ "$1 $2" != "release view" ] || [ -n "${EXISTS:-}" ]
SH
printf '#!/bin/sh\necho notes\n' > "$bin/git-cliff"
chmod +x "$bin/gh" "$bin/git-cliff"

# run <tag> <latest> <prerelease> <assets> [exists]: the gh calls other than `release view`
run() {
  log=$(mktemp)
  env PATH="$bin:$PATH" GH_LOG="$log" RUNNER_TEMP="$work" RELEASE_TAG="$1" LATEST="$2" \
    PRERELEASE="$3" ASSETS="$4" ${5:+EXISTS=1} bash -euo pipefail -c "$script" >/dev/null 2>&1
  grep -v '^release view' "$log" | sed "s|$work|\$RUNNER_TEMP|g"
}
check "stable, latest" \
  "release create v0.2.5 a b --verify-tag --title v0.2.5 --notes-file \$RUNNER_TEMP/notes.md --latest=true --prerelease=false" \
  "$(run v0.2.5 true false 'a b')"
check "line release, not latest" \
  "release create v1.14.6+sm.1 --verify-tag --title v1.14.6+sm.1 --notes-file \$RUNNER_TEMP/notes.md --latest=false --prerelease=false" \
  "$(run v1.14.6+sm.1 false false '')"
check "pre-release" \
  "release create v1.15.0-alpha.1+sm.1 --verify-tag --title v1.15.0-alpha.1+sm.1 --notes-file \$RUNNER_TEMP/notes.md --latest=false --prerelease=true" \
  "$(run v1.15.0-alpha.1+sm.1 false true '')"
check "rerun uploads the assets again" "release upload v0.2.5 a b --clobber" "$(run v0.2.5 true false 'a b' 1)"
check "rerun without assets"           ""                                   "$(run v0.2.5 true false '' 1)"
exit $fail
