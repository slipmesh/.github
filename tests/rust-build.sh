#!/usr/bin/env bash
# The notices and stage steps of rust-build.yml, with cargo replaced on PATH: the notices are
# generated for the arch's own target, and staged next to the binaries the image and the release
# take them from.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
notices=$(step .github/workflows/rust-build.yml build notices) || { echo "FAIL: no step notices"; exit 1; }
stage=$(step .github/workflows/rust-build.yml build stage) || { echo "FAIL: no step stage"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# cargo records its arguments and writes the file `-o` names.
cat > "$bin/cargo" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$CARGO_LOG"
while [ $# -gt 0 ]; do [ "$1" = -o ] && { mkdir -p "$(dirname "$2")"; echo notices > "$2"; }; shift; done
SH
chmod +x "$bin/cargo"

target=x86_64-unknown-linux-musl
log=$work/cargo.log
(cd "$work" && env PATH="$bin:$PATH" CARGO_LOG="$log" RUST_TARGET=$target \
  bash -euo pipefail -c "$notices" >/dev/null 2>&1)
check "notices are generated for the arch's target" \
  "about generate --locked --workspace --fail --target $target -o target/$target/release/THIRD-PARTY-NOTICES about.hbs" \
  "$(cat "$log")"

# run_stage: exit status, then the staged files
run_stage() {
  (cd "$work" && env ARCH=amd64 RUST_TARGET=$target BINARIES="a b" \
    bash -euo pipefail -c "$stage" >/dev/null 2>&1)
  echo $?; (cd "$work" && find staged -type f | LC_ALL=C sort)
}
touch "$work/target/$target/release/a" "$work/target/$target/release/b"
check "binaries and notices staged at the TARGETARCH path" \
  "0 staged/amd64/release/THIRD-PARTY-NOTICES staged/amd64/release/a staged/amd64/release/b" \
  "$(run_stage | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$work/staged" "$work/target/$target/release/THIRD-PARTY-NOTICES"
check "no notices, no artifact" "1" "$(run_stage | head -1)"
exit $fail
