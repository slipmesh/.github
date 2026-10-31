#!/usr/bin/env bash
# Every workflow parses: GitHub reports a file it cannot parse only as a failed run of that file.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
for f in .github/workflows/*.yml; do
  "${PYTHON:-python3}" -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f" 2>/dev/null \
    && got=parses || got=broken
  check "$f" parses "$got"
done
exit $fail
