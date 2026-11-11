#!/usr/bin/env bash
# The preset groups the way README.md says: Renovate runs in dry-run on a fixture repository with default.json
# from this tree, and the branches it would create are compared with the expected ones.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
preset=$(realpath "$(dirname "$0")/../default.json")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# branches <fixture dir>: the branch names Renovate would create there, sorted, one per line.
branches() {
  (cd "$1" && LOG_LEVEL=debug LOG_FORMAT=json RENOVATE_CONFIG_FILE="$tmp/config.json" \
    RENOVATE_GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN:-${GITHUB_TOKEN:-}}" \
    npx --yes renovate@44 --platform=local --dry-run=lookup 2>/dev/null) |
    jq -r 'select(.branch) | .branch' | sort -u
}

"${PYTHON:-python3}" - "$preset" "$tmp/config.json" <<'EOF'
import json, sys
preset = json.load(open(sys.argv[1]))
preset.pop("$schema", None)
preset["onboarding"] = False
preset["requireConfig"] = "ignored"
json.dump(preset, open(sys.argv[2], "w"))
EOF

# sliplib's crates come from one workspace at one tag; moved one at a time, two copies of a crate meet in one
# build and their types no longer match.
scratch_repo "$tmp/sliplib"
cat >"$tmp/sliplib/Cargo.toml" <<'EOF'
[package]
name = "fixture"
version = "0.1.0"
edition = "2024"

[dependencies]
sliplib-net = { git = "https://github.com/slipmesh/sliplib", tag = "v0.11.0" }
sliplib-yaml = { git = "https://github.com/slipmesh/sliplib", tag = "v0.11.0" }
EOF
git -C "$tmp/sliplib" add Cargo.toml && git -C "$tmp/sliplib" commit -qm fixture
check "sliplib crates share one branch" "renovate/sliplib" "$(branches "$tmp/sliplib" | paste -sd' ')"

exit $fail
