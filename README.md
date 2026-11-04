# slipmesh/.github

Shared configuration for the slipmesh repositories: the reusable workflows under
[`.github/workflows/`](.github/workflows/), and the Renovate preset described below.

## Renovate preset

[`default.json`](default.json) is the Renovate preset these repositories share. Renovate runs self-hosted, hourly
from 08:00 to 18:00 UTC, and only on a repository that carries its own configuration: one without is skipped, and
no onboarding pull request is ever opened. It opens pull requests and never merges them.

A repository opts in with a `renovate.json` at its root:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>slipmesh/.github"]
}
```

What the preset sets on top of `config:recommended`:

- **Conventional subjects that are not release subjects.** Every update is `build(deps): ...`, and a GitHub Actions
  one `ci(deps): ...`. Pull requests are squash-merged with their title as the subject, so that is what
  `git-cliff` files in the changelog, and nothing Renovate opens takes the `chore: release vX` shape.
- **The shared workflows stay put.** A caller's `uses: slipmesh/.github/...@vX` is left alone: it moves by hand,
  in step with a release of this repository.
- **`kube` and `k8s-openapi` move together.** `kube` pins the `k8s-openapi` minor it builds against, so they
  arrive as one pull request instead of two that each fail to build.
- **Every release branch, fixes only.** Renovate works on the default branch and on each `release-X.Y` branch,
  every one checked on its own. A release branch gets patch and digest updates and no minor or major one, so a
  dependency tagged by Talos line stays on the line of the branch it is on. A newer patch is offered even where a
  newer minor exists, in a branch of its own. Its pull requests carry the branch in the title, `... (release-X.Y)`,
  and their branches are named `renovate/release-X.Y-...`; the configuration is read from the default branch only.
- **Requirements follow the lock file.** An update raises the requirement to the version it brings, `"0.23.0"` to
  `"0.23.1"`, so `Cargo.toml` names what `Cargo.lock` resolves. A requirement that lags its lock file is raised to
  it in a pull request of its own, and a short one becomes full, `"0.10"` to `"0.10.7"`. A library that must not
  raise its consumers' minimum sets `"rangeStrategy": "update-lockfile"` for its `dependencies`.
- **No dependency dashboard issue, no pull request caps.** Open pull requests are the list of what is pending, and
  each run opens one for every update published since the last.

The Rust repositories commit `Cargo.lock`, and Renovate refreshes it in every pull request it opens.

Repositories whose pins move only in lockstep with checksums - `versions.env` in `talos-kernel` and
`talos-installer` - carry no `renovate.json`.

A repository changes any of this for itself by adding keys next to `extends` in its own `renovate.json`.
