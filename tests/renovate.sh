#!/usr/bin/env bash
# The preset groups the way README.md says: Renovate runs in dry-run on a fixture repository with default.json
# from this tree, and the branches it would create are compared with the expected ones.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
preset=$(realpath "$(dirname "$0")/../default.json")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# branches <fixture dir>: the branch names Renovate would create there, sorted, one per line. Every fixture has
# an update to offer, so a Renovate that does not run or finds nothing - its github.com lookups go unanswered
# without a token - fails here with its log rather than reading as a fixture with no branches.
branches() {
  local log="$tmp/renovate.log"
  if ! (cd "$1" && LOG_LEVEL=debug LOG_FORMAT=json RENOVATE_CONFIG_FILE="$tmp/config.json" \
    RENOVATE_GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN:-${GITHUB_TOKEN:-}}" \
    npx --yes renovate@44 --platform=local --dry-run=lookup >"$log" 2>&1); then
    echo "renovate did not run:" >&2
    tail -n 20 "$log" >&2
    return 1
  fi
  local found
  found=$(jq -rR 'fromjson? | select(.branch?) | .branch' "$log" | sort -u)
  if [ -z "$found" ]; then
    echo "renovate found no update; is GITHUB_COM_TOKEN set?" >&2
    jq -rR 'fromjson? | select(.level >= 40) | .msg' "$log" | tail -n 20 >&2
    return 1
  fi
  echo "$found"
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
got=$(branches "$tmp/sliplib") || { echo "FAIL sliplib crates share one branch: no result"; exit 1; }
check "sliplib crates share one branch" "renovate/sliplib" "$(paste -sd' ' <<<"$got")"

# kube pins the k8s-openapi minor it builds against. A kube major needs a k8s-openapi minor; in two branches,
# neither builds alone.
scratch_repo "$tmp/kube"
cat >"$tmp/kube/Cargo.toml" <<'EOF2'
[package]
name = "fixture"
version = "0.1.0"
edition = "2024"

[dependencies]
kube = "4.2.0"
k8s-openapi = "0.28.0"
EOF2
git -C "$tmp/kube" add Cargo.toml && git -C "$tmp/kube" commit -qm fixture
got=$(branches "$tmp/kube") || { echo "FAIL kube and k8s-openapi share one branch: no result"; exit 1; }
check "kube and k8s-openapi share one branch" "renovate/kube" "$(paste -sd' ' <<<"$got")"

exit $fail
