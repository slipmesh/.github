#!/usr/bin/env bash
# The steps of release.yml, with gh replaced on PATH: unpacking the binaries artifacts, the flags
# the release is created with, its notes and notices, and that a rerun uploads the assets again
# instead of failing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/release.yml github-release release) || { echo "FAIL: no step release"; exit 1; }
unpack=$(step .github/workflows/release.yml github-release unpack) || { echo "FAIL: no step unpack"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# gh records its arguments; `gh release view` succeeds when $EXISTS is set.
cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ "$1 $2" != "release view" ] || [ -n "${EXISTS:-}" ]
SH
chmod +x "$bin/gh"
# The checkout of the tag, with the CHANGELOG.md its release PR regenerated.
cat > "$work/CHANGELOG.md" <<'MD'
# Changelog

All notable changes to this project will be documented in this file.

## [1.15.0-alpha.1+sm.1] - 2026-11-03

- Pre-release

## [1.14.6+sm.1] - 2026-11-03

- Line release

## [0.2.5] - 2026-11-03

- Stable

## [1.14.5+sm.2] - 2026-11-03

### Bug fixes 🐛

- Second

## [1.14.5+sm.1] - 2026-11-02

### Features ✨

- First
MD

# run <tag> <latest> <prerelease> <assets> [exists]: the gh calls other than `release view`
run() {
  log=$(mktemp)
  (cd "$work" && env PATH="$bin:$PATH" GH_LOG="$log" RUNNER_TEMP="$work" RELEASE_TAG="$1" LATEST="$2" \
    PRERELEASE="$3" ASSETS="$4" DOWNLOAD_BINARIES="${DOWNLOAD:-false}" ${5:+EXISTS=1} bash -euo pipefail -c "$script" >/dev/null 2>&1)
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
run v1.14.5+sm.2 false false '' >/dev/null
check "notes are the tag's CHANGELOG.md section" \
  "$(printf '## [1.14.5+sm.2] - 2026-11-03\n\n### Bug fixes 🐛\n\n- Second')" \
  "$(cat "$work/notes.md")"
run v1.14.5+sm.1 false false '' >/dev/null
check "notes of a section below the top one" \
  "$(printf '## [1.14.5+sm.1] - 2026-11-02\n\n### Features ✨\n\n- First')" \
  "$(cat "$work/notes.md")"
check "no section for the tag, no release" "" "$(run v1.14.5+sm.3 false false '')"
# Unpacking: every arch's tar into binaries/, and the notices set aside where prepare cannot
# reach them.
for a in amd64 arm64; do
  mkdir -p "$work/staged/$a/release"; echo "$a" > "$work/staged/$a/release/tool"; chmod 0755 "$work/staged/$a/release/tool"
  for n in THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl; do echo "$n" > "$work/staged/$a/release/$n"; done
  mkdir -p "$work/artifacts"; tar -C "$work/staged" -cf "$work/artifacts/binaries-$a.tar" "$a"
done
(cd "$work" && env RUNNER_TEMP="$work" bash -euo pipefail -c "$unpack" >/dev/null 2>&1)
check "both arches unpacked, modes kept" "755 binaries/amd64/release/tool 755 binaries/arm64/release/tool" \
  "$(cd "$work" && stat -c '%a %n' binaries/*/release/tool | tr '\n' ' ' | sed 's/ $//')"
check "notices set aside" "COPYRIGHT-musl COPYRIGHT-rust-std.html THIRD-PARTY-NOTICES" \
  "$(ls "$work/notices" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"

n=\$RUNNER_TEMP/notices
check "downloaded binaries bring their notices" \
  "release create v0.2.5 a $n/THIRD-PARTY-NOTICES $n/COPYRIGHT-rust-std.html $n/COPYRIGHT-musl --verify-tag --title v0.2.5 --notes-file \$RUNNER_TEMP/notes.md --latest=true --prerelease=false" \
  "$(DOWNLOAD=true run v0.2.5 true false a)"
check "an asset named like a notice fails instead of clashing" "" \
  "$(DOWNLOAD=true run v0.2.5 true false dist/THIRD-PARTY-NOTICES)"
check "rerun uploads the assets again" "release upload v0.2.5 a b --clobber" "$(run v0.2.5 true false 'a b' 1)"
check "rerun without assets"           ""                                   "$(run v0.2.5 true false '' 1)"
exit $fail
