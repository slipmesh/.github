#!/usr/bin/env bash
# Exercises the source-commit resolution in promote.yml against a scratch history, with docker
# and sleep replaced on PATH.
# Usage: tests/promote-source.sh .github/workflows/promote.yml
set -uo pipefail
yml=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
script=$("${PYTHON:-python3}" -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["promote"]["steps"]
print(next(s["run"] for s in steps if s.get("id") == "source"))
' "$yml") || { echo "FAIL: no step with id source"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# `docker buildx imagetools inspect <ref>` succeeds when <ref>'s commit is listed in $IMAGES.
cat > "$bin/docker" <<'SH'
#!/usr/bin/env bash
ref=${@: -1}; sha=${ref##*:sha-}
[[ " $IMAGES " == *" $sha "* ]]
SH
printf '#!/bin/sh\n:\n' > "$bin/sleep"
chmod +x "$bin/docker" "$bin/sleep"

cd "$work" && git init -q -b main repo && cd repo
git config user.email t@example.com; git config user.name t; git config core.hooksPath /dev/null  # fixtures, never published
commit() { for f in "$@"; do mkdir -p "$(dirname "$f")"; echo "$RANDOM" >> "$f"; done; git add -A; git commit -qm c; git rev-parse HEAD; }
c1=$(commit main.c)                          # code
c2=$(commit README.md)                       # docs only
c3=$(commit docs/RELEASING.md CHANGELOG.md)  # docs only
c4=$(commit main.c README.md)                # code and docs
c5=$(commit CHANGELOG.md)                    # docs only
c6=$(commit docs/notes.txt)                  # not Markdown: built like code
c7=$(commit README.md)                       # docs only

fail=0
# expect <tagged commit> <expected source, or FAIL> <commits that have an image...>
expect() {
  local head=$1 want=$2; shift 2
  out=$(mktemp)
  git checkout -q "$head"
  PATH="$bin:$PATH" IMAGES="$*" IMAGE=registry.example/x GITHUB_SHA=$head GITHUB_OUTPUT=$out \
    bash -euo pipefail -c "$script" >/dev/null 2>&1
  got=$(sed -n 's/^source=//p' "$out"); got=${got:-FAIL}
  if [ "$got" = "$want" ]; then echo "ok   ${head:0:7} -> ${want:0:7}"
  else echo "FAIL ${head:0:7}: want ${want:0:7}, got ${got:0:7}"; fail=1; fi
}
expect "$c5" "$c4" "$c1 $c4"   # release commit over a built commit
expect "$c3" "$c1" "$c1"       # two docs-only commits over a built one
expect "$c4" "$c4" "$c1 $c4"   # the tagged commit has its own image
expect "$c4" FAIL  "$c1"       # code changed and its image never appears
expect "$c5" FAIL  "$c1"       # docs-only over an unbuilt code commit
expect "$c7" "$c6" "$c1 $c4 $c6"  # a non-Markdown file under docs/ is built
expect "$c7" FAIL  "$c1 $c4"   # ... so an older image is not released for it
expect "$c1" FAIL              # root commit without an image
exit $fail
