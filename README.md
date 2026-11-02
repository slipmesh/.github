# slipmesh/.github

Shared configuration for the slipmesh repositories: the reusable workflows under
[`.github/workflows/`](.github/workflows/), and the Renovate preset described below.

## Renovate preset

[`default.json`](default.json) is the Renovate preset these repositories share. Renovate runs self-hosted, hourly
from 08:00 to 18:00 UTC, and only on a repository that carries its own configuration: one without is skipped, and
no onboarding pull request is ever opened. It opens pull requests and never merges them. It works on the default
branch only; a dependency reaches a `release-*` branch as a deliberate backport.

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
- **No dependency dashboard issue, no pull request caps.** Open pull requests are the list of what is pending, and
  each run opens one for every update published since the last.

The Rust repositories commit `Cargo.lock`, so an update inside a `Cargo.toml` range arrives as a lock file change,
and Renovate refreshes the lock file in every pull request it opens.

Repositories whose pins move only in lockstep with checksums - `versions.env` in `talos-kernel` and
`talos-installer` - carry no `renovate.json`.

A repository changes any of this for itself by adding keys next to `extends` in its own `renovate.json`.
