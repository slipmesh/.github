#!/usr/bin/env bash
# The build step of image.yml with a real docker buildx, exporting to a local directory instead of
# pushing: the caller's Dockerfile is built as it is, and the notices land on top of it at
# /usr/share/licenses/<repo>/ whatever the caller's .dockerignore leaves out.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/image.yml build build) || { echo "FAIL: no step build"; exit 1; }
placeholders=$(step .github/workflows/image.yml build placeholders) || { echo "FAIL: no step placeholders"; exit 1; }
digest=$(step .github/workflows/image.yml build digest) || { echo "FAIL: no step digest"; exit 1; }

# A pull request's check builds from placeholders where the release build has binaries.
pw=$(mktemp -d)
(cd "$pw" && env ARCH=amd64 BINARIES="a b" bash -euo pipefail -c "$placeholders" >/dev/null 2>&1)
check "placeholders for the binaries and the notices" \
  "target/amd64/release/COPYRIGHT-musl target/amd64/release/COPYRIGHT-rust-std.html target/amd64/release/THIRD-PARTY-NOTICES target/amd64/release/a target/amd64/release/b" \
  "$(cd "$pw" && find target -type f | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$pw/target"
check "no binaries named fails" "1" \
  "$(cd "$pw" && env ARCH=amd64 BINARIES="" bash -euo pipefail -c "$placeholders" >/dev/null 2>&1; echo $?)"

docker buildx version >/dev/null 2>&1 || { echo "skip the build: no docker buildx here"; exit $fail; }

case $(uname -m) in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
work=$(mktemp -d); mkdir -p "$work/repo/target/$arch/release"
cd "$work/repo"
printf 'FROM scratch\nARG TARGETARCH\nCOPY target/${TARGETARCH}/release/app /app\n' > Dockerfile
printf '*\n!target/*/release/app\n' > .dockerignore
echo app > "target/$arch/release/app"
for n in THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl; do echo "$n" > "target/$arch/release/$n"; done
# What the artifact store leaves after image.yml restores the binaries' executable bit.
chmod +x target/"$arch"/release/*

# run: exit status
run() {
  env ARCH="$arch" REPO_NAME=demo OUTPUT="type=local,dest=$work/repo/out" RUNNER_TEMP="$work" \
    BUILDX_BAKE_ENTITLEMENTS_FS=1 \
    bash -euo pipefail -c "$script" >"$work/log" 2>&1
  local status=$?
  [ $status -eq 0 ] || tail -15 "$work/log" >&2
  echo $status
}
check "builds" "0" "$(run)"
check "the caller's image is kept" "app" "$(cat "$work/repo/out/app" 2>/dev/null)"
check "notices on top of it" "THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl" \
  "$(for n in THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl; do cat "$work/repo/out/usr/share/licenses/demo/$n" 2>/dev/null; done | tr '\n' ' ' | sed 's/ $//')"
check "notices are plain files" "644 644 644" \
  "$(for n in THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl; do stat -c %a "$work/repo/out/usr/share/licenses/demo/$n" 2>/dev/null; done | tr '\n' ' ' | sed 's/ $//')"
check "nothing else in the licenses directory" "3" "$(ls "$work/repo/out/usr/share/licenses/demo" 2>/dev/null | wc -l | tr -d ' ')"

# The release path, against a registry the test runs: push by digest, read the digest the way the
# export step does, and find the image under it.
if [ -n "${TEST_REGISTRY:-}" ]; then
  : > "$work/github-output"
  env ARCH="$arch" REPO_NAME=demo RUNNER_TEMP="$work" BUILDX_BAKE_ENTITLEMENTS_FS=1 \
    OUTPUT="type=image,name=$TEST_REGISTRY/demo,push-by-digest=true,name-canonical=true,push=true" \
    bash -euo pipefail -c "$script" >"$work/log" 2>&1
  check "pushes by digest" "0" "$?"
  (env RUNNER_TEMP="$work" bash -euo pipefail -c "$digest" >/dev/null 2>&1)
  check "exports the digest" "0" "$?"
  pushed=$(ls "$work/digests" 2>/dev/null)
  docker buildx imagetools inspect "$TEST_REGISTRY/demo@sha256:$pushed" >/dev/null 2>&1
  check "the digest names the pushed image" "0" "$?"
else
  echo "skip the push: no TEST_REGISTRY"
fi

rm -rf "$work/repo/out" "target/$arch/release/COPYRIGHT-musl"
check "a missing notice fails" "1" "$(run)"
exit $fail
