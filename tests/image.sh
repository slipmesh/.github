#!/usr/bin/env bash
# The build step of image.yml with a real docker buildx, exporting to a local directory instead of
# pushing: the caller's Dockerfile is built as it is, and the notices land on top of it at
# /usr/share/licenses/<repo>/ whatever the caller's .dockerignore leaves out.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/image.yml build build) || { echo "FAIL: no step build"; exit 1; }
placeholders=$(step .github/workflows/image.yml build placeholders) || { echo "FAIL: no step placeholders"; exit 1; }

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

# run: exit status
run() {
  env ARCH="$arch" REPO_NAME=demo OUTPUT="type=local,dest=$work/out" RUNNER_TEMP="$work" \
    bash -euo pipefail -c "$script" >"$work/log" 2>&1
  echo $?
}
check "builds" "0" "$(run)"
check "the caller's image is kept" "app" "$(cat "$work/out/app" 2>/dev/null)"
check "notices on top of it" "THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl" \
  "$(for n in THIRD-PARTY-NOTICES COPYRIGHT-rust-std.html COPYRIGHT-musl; do cat "$work/out/usr/share/licenses/demo/$n" 2>/dev/null; done | tr '\n' ' ' | sed 's/ $//')"
check "nothing else in the licenses directory" "3" "$(ls "$work/out/usr/share/licenses/demo" 2>/dev/null | wc -l | tr -d ' ')"

rm -rf "$work/out" "target/$arch/release/COPYRIGHT-musl"
check "a missing notice fails" "1" "$(run)"
exit $fail
