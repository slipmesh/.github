#!/usr/bin/env bash
# The notices and stage steps of rust-build.yml, with cargo and rustc replaced on PATH: the crates'
# notices cover both arches' dependency graphs, the toolchain's own notices sit next to them, and
# all of it is staged next to the binaries the image and the release take it from.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
notices=$(step .github/workflows/rust-build.yml build notices) || { echo "FAIL: no step notices"; exit 1; }
stage=$(step .github/workflows/rust-build.yml build stage) || { echo "FAIL: no step stage"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# cargo records its arguments and writes the file `-o` names; rustc names a fake sysroot.
cat > "$bin/cargo" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$CARGO_LOG"
while [ $# -gt 0 ]; do [ "$1" = -o ] && { mkdir -p "$(dirname "$2")"; echo notices > "$2"; }; shift; done
SH
cat > "$bin/rustc" <<'SH'
#!/usr/bin/env bash
[ "$*" = "--print sysroot" ] && echo "$SYSROOT"
SH
chmod +x "$bin/cargo" "$bin/rustc"
mkdir -p "$work/sysroot/share/doc/rust"
echo std > "$work/sysroot/share/doc/rust/COPYRIGHT-library.html"
echo musl > "$work/musl-copyright"

target=x86_64-unknown-linux-musl
out=target/$target/release
# run_notices: exit status
run_notices() {
  (cd "$work" && env PATH="$bin:$PATH" CARGO_LOG="$work/cargo.log" SYSROOT="$work/sysroot" \
    MUSL_COPYRIGHT="$work/musl-copyright" RUST_TARGET=$target \
    NOTICE_TARGETS="x86_64-unknown-linux-musl aarch64-unknown-linux-musl" \
    bash -euo pipefail -c "$notices" >/dev/null 2>&1)
  echo $?
}
check "notices step succeeds" "0" "$(run_notices)"
check "crate notices cover both arches' graphs" \
  "about generate --locked --workspace --fail --target=x86_64-unknown-linux-musl --target=aarch64-unknown-linux-musl -o $out/THIRD-PARTY-NOTICES about.hbs" \
  "$(cat "$work/cargo.log")"
check "std notices from the toolchain" "std" "$(cat "$work/$out/COPYRIGHT-rust-std.html")"
check "musl notices from the musl package" "musl" "$(cat "$work/$out/COPYRIGHT-musl")"

# run_stage: exit status, then the staged files
run_stage() {
  (cd "$work" && env ARCH=amd64 RUST_TARGET=$target BINARIES="a b" \
    bash -euo pipefail -c "$stage" >/dev/null 2>&1)
  echo $?; (cd "$work" && find staged -type f | LC_ALL=C sort)
}
touch "$work/$out/a" "$work/$out/b"
check "binaries and notices staged at the TARGETARCH path" \
  "0 staged/amd64/release/COPYRIGHT-musl staged/amd64/release/COPYRIGHT-rust-std.html staged/amd64/release/THIRD-PARTY-NOTICES staged/amd64/release/a staged/amd64/release/b" \
  "$(run_stage | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$work/staged" "$work/$out/THIRD-PARTY-NOTICES"
check "no notices, no artifact" "1" "$(run_stage | head -1)"

rm -f "$work/sysroot/share/doc/rust/COPYRIGHT-library.html"
check "a toolchain without std notices fails" "1" "$(run_notices)"
exit $fail
