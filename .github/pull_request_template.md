<!--
  Keep PRs small and focused: one logical change. See CONTRIBUTING.md and CLAUDE.md.
  Do NOT include AI-attribution trailers in commits.
-->

## What & why

<!-- What does this change, and what problem does it solve? -->

## Type of change

- [ ] Fix (backward-compatible) — PATCH
- [ ] New add-on capability (option/feature) — MINOR
- [ ] Breaking change (config/default/access model) — MAJOR
- [ ] Docs / CI / tooling only (no shipped behavior change)

## Checklist

- [ ] Added a note under `## Unreleased` in `claude-terminal/CHANGELOG.md`
      (skip only for docs/CI-only changes)
- [ ] `config.yaml` version and `build.yaml` label are left for a batched release
      (I did **not** bump the version just for this PR), **or** this is the release PR
- [ ] Ran the relevant local checks (hadolint / shellcheck / build) — see CONTRIBUTING.md
- [ ] Conventional Commit title; no AI-attribution trailers
