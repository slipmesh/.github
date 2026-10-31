#!/usr/bin/env bash
# The step of release-pr.yml that opens the release PR, against a bare origin, with gh and git-cliff
# replaced on PATH: which versions it accepts, and that a rerun updates the PR instead of failing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step "$(pwd)/.github/workflows/release-pr.yml" release-pr open) || { echo "FAIL: no step open"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
# gh records its arguments. `gh pr view` fails when $PR_STATE is unset (no PR for the branch), and
# otherwise prints what its `--jq 'select(.state == "OPEN")'` filter would: the state, or nothing.
cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ "$1 $2" = "pr view" ] || exit 0
[ -n "${PR_STATE:-}" ] || exit 1
[ "$PR_STATE" != OPEN ] || echo '{"state":"OPEN"}'
SH
# git-cliff: --bumped-version prints $NEXT, -o writes the changelog, anything else prints notes.
cat > "$bin/git-cliff" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" --bumped-version "*) echo "$NEXT" ;;
  *" -o "*) echo "changelog" > CHANGELOG.md ;;
  *) echo notes ;;
esac
SH
# cargo: `update --workspace` marks Cargo.lock and records that it ran.
cat > "$bin/cargo" <<'SH'
#!/usr/bin/env bash
echo "cargo $*" >> "$CARGO_LOG"
[ "$*" != "update --workspace" ] || echo "# workspace at $VERSION_NUMBER" >> Cargo.lock
SH
chmod +x "$bin/gh" "$bin/git-cliff" "$bin/cargo"
export CARGO_LOG=$work/cargo.log

git init -q --bare -b main "$work/origin.git"
scratch_repo "$work/seed"
echo 0.2.0 > "$work/seed/VERSION"
git -C "$work/seed" add VERSION
git -C "$work/seed" commit -q -m "feat: one"
git -C "$work/seed" remote add origin "$work/origin.git"
git -C "$work/seed" push -q origin main
git -C "$work/seed" tag -a v0.2.0 -m v0.2.0 && git -C "$work/seed" push -q origin v0.2.0

# run <requested version> [state of an existing PR]: runs the step in a fresh clone of main, as a
# rerun would, a minute after the previous run so its commit differs; prints its exit status, then
# the gh calls other than `pr view`. It runs in a subshell, so the run count lives in a file.
echo 0 > "$work/runs"
run() {
  local n=$(( $(cat "$work/runs") + 1 )); echo $n > "$work/runs"
  export GIT_AUTHOR_DATE="2026-01-01T00:$(printf %02d $n):00Z" GIT_COMMITTER_DATE="2026-01-01T00:$(printf %02d $n):00Z"
  clone=$(mktemp -d)/repo; log=$(mktemp)
  git clone -q "$work/origin.git" "$clone"
  git -C "$clone" config core.hooksPath /dev/null
  (cd "$clone" && env PATH="$bin:$PATH" GH_LOG="$log" NEXT="${NEXT-v0.3.0}" ${2:+PR_STATE=$2} \
    GITHUB_REF_NAME=main REQUESTED="$1" BUMP='echo "$VERSION_NUMBER" > VERSION' \
    bash -euo pipefail -c "$script" >/dev/null 2>&1)
  echo $?
  grep -v '^pr view' "$log"
}
branch_file() { git -C "$work/origin.git" show "refs/heads/chore/release-$1:$2" 2>/dev/null; }
branch_subject() { git -C "$work/origin.git" log -1 --format=%s "refs/heads/chore/release-$1" 2>/dev/null; }

check "computed version opens the PR" \
  "0 pr create --base main --head chore/release-v0.3.0 --title chore: release v0.3.0 --body notes" \
  "$(run '' | tr '\n' ' ' | sed 's/ $//')"
check "bump gets the version number" "0.3.0"                  "$(branch_file v0.3.0 VERSION)"
check "release commit subject"       "chore: release v0.3.0"  "$(branch_subject v0.3.0)"
check "rerun with the PR open edits it" \
  "0 pr edit chore/release-v0.3.0 --body notes" \
  "$(run '' OPEN | tr '\n' ' ' | sed 's/ $//')"
check "rerun after the PR was closed opens a new one" \
  "0 pr create --base main --head chore/release-v0.3.0 --title chore: release v0.3.0 --body notes" \
  "$(run '' CLOSED | tr '\n' ' ' | sed 's/ $//')"
check "rerun after a failed pr create opens it" \
  "0 pr create --base main --head chore/release-v0.3.0 --title chore: release v0.3.0 --body notes" \
  "$(run '' | tr '\n' ' ' | sed 's/ $//')"
check "pre-release with build metadata" "0" "$(run v1.15.0-alpha.1+sm.1 | head -1)"
check "already tagged"                  "1" "$(run v0.2.0 | head -1)"
for bad in 1.2.3 v1.2 v01.2.3 'v1.2.3 x' 'v1.2.3;id' 'v1.2.3+' 'v1.2.3-'; do
  check "rejects '$bad'" "1" "$(run "$bad" | head -1)"
done
check "no Cargo.lock, no cargo" "" "$(cat "$CARGO_LOG" 2>/dev/null)"

# A repository that commits Cargo.lock: the bump moves the workspace's own versions, which the
# lockfile records too, so without an update the release commit fails `cargo build --locked`.
echo "# lock" > "$work/seed/Cargo.lock"
git -C "$work/seed" add Cargo.lock && git -C "$work/seed" commit -q -m "build: commit Cargo.lock"
git -C "$work/seed" push -q origin main
check "Cargo.lock: release PR opens" "0" "$(run v0.4.0 | head -1)"
check "Cargo.lock: workspace updated" "cargo update --workspace" "$(cat "$CARGO_LOG")"
check "Cargo.lock: update committed" "# workspace at 0.4.0" "$(branch_file v0.4.0 Cargo.lock | tail -1)"
check "rejects an empty computed version" "1" "$(NEXT='' run '' | head -1)"
exit $fail
