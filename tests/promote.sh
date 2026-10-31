#!/usr/bin/env bash
# The retag step of promote.yml with docker replaced on PATH: which image it resolves and which tags
# it puts on that digest.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step .github/workflows/promote.yml promote retag) || { echo "FAIL: no step retag"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# docker: `imagetools inspect` answers with a fixed digest, or fails for an unknown image;
# `imagetools create` records its arguments.
cat > "$bin/docker" <<'SH'
#!/usr/bin/env bash
case "$2 $3" in
  "imagetools inspect")
    [ "$4" = "ghcr.io/o/r:sha-c0ffee" ] || exit 1
    echo '{"digest":"sha256:abc","mediaType":"application/vnd.oci.image.index.v1+json"}' ;;
  "imagetools create") shift 3; echo "$*" >> "$DOCKER_LOG" ;;
esac
SH
chmod +x "$bin/docker"

# run <release tag> <latest> [sha]: exit status, then what `imagetools create` was given
run() {
  log=$(mktemp)
  env PATH="$bin:$PATH" DOCKER_LOG="$log" IMAGE=ghcr.io/o/r GITHUB_SHA="${3:-c0ffee}" \
    RELEASE_TAG="$1" LATEST="$2" bash -euo pipefail -c "$script" >/dev/null 2>&1
  echo $?; cat "$log"
}
check "build metadata becomes -" "0 -t ghcr.io/o/r:v1.14.5-sm.2 ghcr.io/o/r@sha256:abc" \
  "$(run v1.14.5+sm.2 false | tr '\n' ' ' | sed 's/ $//')"
check "latest adds the tag" "0 -t ghcr.io/o/r:v0.2.5 -t ghcr.io/o/r:latest ghcr.io/o/r@sha256:abc" \
  "$(run v0.2.5 true | tr '\n' ' ' | sed 's/ $//')"
check "no image for the commit fails" "1" "$(run v0.2.5 false deadbeef | head -1)"
exit $fail
