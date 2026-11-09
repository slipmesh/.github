#!/usr/bin/env bash
# image.yml's steps with a real docker buildx. A release build unpacks the binaries artifact,
# bakes the caller's Dockerfile as it is with the notices laid on top at /usr/share/licenses/<repo>/
# whatever its .dockerignore leaves out, and pushes by digest. A pull request's check bakes the same
# from placeholders, pushing nothing, and fails where the release would.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
yml=.github/workflows/image.yml
unpack=$(step $yml build unpack) || { echo "FAIL: no step unpack"; exit 1; }
placeholders=$(step $yml build placeholders) || { echo "FAIL: no step placeholders"; exit 1; }
script=$(step $yml build build) || { echo "FAIL: no step build"; exit 1; }
digest=$(step $yml build digest) || { echo "FAIL: no step digest"; exit 1; }
notices="THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl"

# Placeholders: a file at every path the release build stages.
pw=$(mktemp -d)
(cd "$pw" && env ARCH=amd64 BINARIES="a b" bash -euo pipefail -c "$placeholders" >/dev/null 2>&1)
check "placeholders for the binaries and the notices" \
  "target/amd64/release/COPYRIGHT-musl target/amd64/release/COPYRIGHT-rust-std.html target/amd64/release/THIRD-PARTY-NOTICES target/amd64/release/a target/amd64/release/b" \
  "$(cd "$pw" && find target -type f | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$pw/target"
check "no binaries named fails" "1" \
  "$(cd "$pw" && env ARCH=amd64 BINARIES="" bash -euo pipefail -c "$placeholders" >/dev/null 2>&1; echo $?)"

case $(uname -m) in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
work=$(mktemp -d)

# The artifact rust-build.yml uploads: a tar keeping the modes the build staged.
mkdir -p "$work/staged/$arch/release" "$work/artifact"
echo app > "$work/staged/$arch/release/app"; chmod 0755 "$work/staged/$arch/release/app"
for n in $notices; do echo "$n" > "$work/staged/$arch/release/$n"; chmod 0644 "$work/staged/$arch/release/$n"; done
tar -C "$work/staged" -cf "$work/artifact/binaries-$arch.tar" "$arch"

# fixture <dir> <.dockerignore>: a caller whose Dockerfile copies `app`.
fixture() {
  mkdir -p "$1"
  printf 'FROM scratch\nARG TARGETARCH\nCOPY target/${TARGETARCH}/release/app /app\n' > "$1/Dockerfile"
  printf '%b' "$2" > "$1/.dockerignore"
}
fixture "$work/repo" '*\n!target/*/release/app\n'
(cd "$work/repo" && env ARCH="$arch" RUNNER_TEMP="$work" bash -euo pipefail -c "$unpack" >/dev/null 2>&1)
check "unpacking keeps the staged modes" "644 COPYRIGHT-musl 644 COPYRIGHT-rust-std.html 644 THIRD-PARTY-NOTICES 755 app" \
  "$(cd "$work/repo/target/$arch/release" 2>/dev/null && stat -c '%a %n' * | LC_ALL=C sort -k2 | tr '\n' ' ' | sed 's/ $//')"

docker buildx version >/dev/null 2>&1 || { echo "skip the builds: no docker buildx here"; exit $fail; }

# bake <repo dir> <output>: exit status of the build step, with bake's log on failure.
bake() {
  (cd "$1" && env ARCH="$arch" GITHUB_REPOSITORY=o/demo OUTPUT="$2" RUNNER_TEMP="$work" \
    BUILDX_BAKE_ENTITLEMENTS_FS=1 bash -euo pipefail -c "$script" >"$work/log" 2>&1)
  local status=$?
  [ $status -eq 0 ] || tail -15 "$work/log" >&2
  echo $status
}

check "builds" "0" "$(bake "$work/repo" "type=local,dest=$work/repo/out")"
check "the image is the caller's files and the notices, nothing else" \
  "$(printf '%s\n' '755 app' '755 usr' '755 usr/share' '755 usr/share/licenses' '755 usr/share/licenses/demo' \
    '644 usr/share/licenses/demo/COPYRIGHT-musl' '644 usr/share/licenses/demo/COPYRIGHT-rust-std.html' \
    '644 usr/share/licenses/demo/THIRD-PARTY-NOTICES')" \
  "$(cd "$work/repo/out" 2>/dev/null && find . -mindepth 1 -printf '%m %P\n' | LC_ALL=C sort -k2)"
check "notices carry the staged content" "$notices" \
  "$(for n in $notices; do cat "$work/repo/out/usr/share/licenses/demo/$n" 2>/dev/null; done | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$work/repo/out"

# The release path, against a registry the test runs: push by digest, read the digest the way the
# export step does, and find the image under it.
if [ -n "${TEST_REGISTRY:-}" ]; then
  check "pushes by digest" "0" \
    "$(bake "$work/repo" "type=image,name=$TEST_REGISTRY/demo,push-by-digest=true,name-canonical=true,push=true")"
  (env RUNNER_TEMP="$work" bash -euo pipefail -c "$digest" >/dev/null 2>&1)
  check "exports the digest" "0" "$?"
  pushed=$(ls "$work/digests" 2>/dev/null)
  docker buildx imagetools inspect "$TEST_REGISTRY/demo@sha256:$pushed" >/dev/null 2>&1
  check "the digest names the pushed image" "0" "$?"
else
  echo "skip the push: no TEST_REGISTRY"
fi

# The pull request's check: placeholders, then the same bake with nothing exported.
fixture "$work/check" '*\n!target/*/release/app\n'
(cd "$work/check" && env ARCH="$arch" BINARIES=app bash -euo pipefail -c "$placeholders" >/dev/null 2>&1)
check "a check builds from placeholders" "0" "$(bake "$work/check" type=cacheonly)"
fixture "$work/check" '*\n'
check "a check fails on a .dockerignore the release would fail on" "1" "$(bake "$work/check" type=cacheonly 2>/dev/null)"

rm "$work/repo/target/$arch/release/COPYRIGHT-musl"
check "a missing notice fails" "1" "$(bake "$work/repo" "type=local,dest=$work/repo/out" 2>/dev/null)"
exit $fail
