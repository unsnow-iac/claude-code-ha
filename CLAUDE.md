# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

A Home Assistant add-on that runs the **Claude Code CLI** in a browser terminal
(`ttyd` + `tmux`), with persistent package management. This repo is a fork of
[ESJavadex/claude-code-ha](https://github.com/ESJavadex/claude-code-ha) that
exists to fix three things that broke the upstream add-on:

1. **`statx` crash** — newer Claude native builds need the `statx` symbol, which
   Alpine 3.19 (musl 1.2.4) doesn't export. The add-on bricked on launch with
   `Error relocating ...: statx: symbol not found`. Fixed by moving the base
   image to **Alpine 3.21 (musl 1.2.5)**.
2. **Broken `persist-install`** — the copy logic mishandled apk file paths and
   missed shared-lib deps, so "installed" packages didn't actually persist.
3. **A dead persistent-Claude layer** — an obsolete `cli.js`-based path fought
   the baked binary. Removed; the baked, pinned binary is now authoritative.

## Repo layout

The add-on lives entirely in **`claude-terminal/`**:

- `Dockerfile` — image build; Claude pinned via `ARG CLAUDE_VERSION`.
- `build.yaml` — base images (Alpine 3.21 per-arch) + image labels.
- `config.yaml` — add-on manifest: options, schema, ingress, ports, version.
- `run.sh` — startup: launcher hardening, package auto-install, ttyd launch.
- `scripts/` — `persist-install` and helpers (auth, session picker, health).
- `image-service/` — Node service for image upload/paste.
- `CHANGELOG.md` — user-facing release notes.

Everything else at the repo root (`flake.nix`, `DEVELOPMENT*.md`, etc.) is dev
tooling and docs.

## The golden rule: how to ship a Claude Code update

This is the **only supported way** to update the Claude binary:

1. Bump `ARG CLAUDE_VERSION` in `claude-terminal/Dockerfile`.
2. Bump `version:` in `claude-terminal/config.yaml` (and the label in
   `build.yaml`).
3. Add a `claude-terminal/CHANGELOG.md` entry.
4. Commit, push, then **Update/Rebuild the add-on** from the HA add-on store.

Version, changelog, and tag/release mechanics follow the **[Release
standard](#release-standard)** below — a routine Claude bump is normally a MINOR.
Updates are delivered by **rebuilding the image**, not by updating inside the
container. `/data` is preserved across rebuilds, so this is non-destructive.

### Do NOT update Claude from inside the container

- `npm update -g` is a **no-op** — the install is the self-contained native
  binary, not an npm package.
- `claude update` "works" but **bricks the next launch**: it writes a new build
  into `/data` and repoints the launcher; if that build needs a symbol the base
  musl lacks, every subsequent launch dies. Auto-update is disabled
  (`DISABLE_AUTOUPDATER=1`) for this reason — keep it that way.

`run.sh` defends against drift by **force-linking the launcher to the image's
baked binary on every boot** (`init_environment`), so any stray in-container
update self-heals on restart.

## Release standard

Releases follow **[Semantic Versioning](https://semver.org/)** and
**[Keep a Changelog](https://keepachangelog.com/)**, with commits in
**[Conventional Commits](https://www.conventionalcommits.org/)** style. The line
continues from **4.5.0**; **never lower the version on `main`** — the store
detects updates by the number increasing, so a downgrade can hide an update.

### Versioning — what bumps which number

- **MAJOR** (`X.0.0`) — a change existing users must act on: removing or renaming
  a config option, changing a default that alters behavior, or a base-image /
  architecture change that could disrupt installs.
- **MINOR** (`x.Y.0`) — backward-compatible new capability: a new option or
  feature, **and** routine Claude CLI version bumps (each ships new upstream
  capability) unless the bump is purely a fix.
- **PATCH** (`x.y.Z`) — backward-compatible fixes only: bug fixes, security
  hardening, dependency bumps, doc/image fixes that ship in the image.

### Cadence — release as needed, batched

Cut a release when either (a) the weekly `claude-version-bump.yml` PR lands
(typically a MINOR), or (b) enough user-meaningful change has accumulated under
`## Unreleased` to be worth shipping. There is **no calendar obligation** — the
auto-bump workflow supplies a natural heartbeat, and the store only ever offers
the latest version, so micro-bumps just add changelog noise. Batch related PRs
under one bump.

### Changelog — Keep a Changelog

`CHANGELOG.md` opens with `## Unreleased`; group entries under **Added / Changed /
Fixed / Security / Removed / Deprecated**. To cut a release, rename
`## Unreleased` to `## X.Y.Z — YYYY-MM-DD` and start a fresh `## Unreleased`.

### Commits — Conventional Commits

Type-prefix every commit: `feat`, `fix`, `chore`, `docs`, `ci`, `refactor`,
`perf`, `test`, `build` (optional `(scope)`; `feat!:` or a `BREAKING CHANGE:`
footer marks a MAJOR). Types map onto the SemVer bump above (`feat` → MINOR,
`fix` → PATCH, breaking → MAJOR). No AI-attribution trailers (global hygiene).

### Release procedure

1. Accumulate notes under `## Unreleased` as PRs merge.
2. Decide the SemVer bump from the accumulated change.
3. Set `version:` in `config.yaml` **and** the label in `build.yaml` (CI enforces
   they match); date the changelog section.
4. Land it via a release branch + PR (never straight to `main`).
5. After merge, tag `vX.Y.Z` (annotated) on `main` and publish a **GitHub
   Release** with the changelog section as its notes — this is what the repo
   homepage reads as "latest".

## Invariants — don't regress these

- **Base image must export `statx`.** Don't drop `build.yaml` below Alpine 3.21
  to chase a smaller image — you'll reintroduce the launch crash.
- **`ttyd` and `tmux` are baked in the Dockerfile**, not apk'd at runtime, so the
  terminal still starts when Alpine repos are unreachable. Keep them baked.
- **Reading a list option from `bashio`:** `bashio::config 'some_list'` already
  expands a list into newline-separated raw values. Do **not** pipe it back
  through `jq -r '.[]'` — that double-parses non-JSON and aborts with
  `jq: parse error: Invalid literal...`, silently installing nothing. Consume
  the lines directly. (This was the v3.0.1 fix.)

## persist-install (package persistence)

The container's apk/pip layer is **ephemeral** — `apk add` / `pip install` are
lost on restart. Use **`persist-install`**, which copies binaries and their
`ldd`-resolved libraries into `/data/packages/{bin,lib}` (and a Python venv),
which is on `PATH`/`LD_LIBRARY_PATH` and survives restarts and recreation.

```bash
persist-install git tmux openssh-client      # apk packages
persist-install --python requests pandas      # pip into the venv
persist-install --list
```

Users can also auto-install on boot via the `persistent_apk_packages` /
`persistent_pip_packages` options (handled by `auto_install_packages` in
`run.sh`). Full details: `claude-terminal/PERSISTENT_PACKAGES.md`.

## Build & test locally

```bash
nix develop                 # dev shell (podman, hadolint); or `direnv allow`

# Build against the real base (note: 3.21, not 3.19)
podman build \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21 \
  -t local/claude-terminal:test ./claude-terminal

# Run, inspect, tear down
podman run -d --name cc-test -p 7681:7681 -v /tmp/cc-config:/config local/claude-terminal:test
podman logs -f cc-test
podman stop cc-test && podman rm cc-test

hadolint ./claude-terminal/Dockerfile
```

## CI & automation

GitHub Actions in `.github/workflows/`:

- **`ci.yml`** — runs on every PR and on pushes to `main`. Independent parallel
  jobs: hadolint (Dockerfile; intentional rule exceptions in `.hadolint.yaml`),
  shellcheck (scripts), the Home Assistant add-on manifest linter, a guard that
  the `config.yaml` version equals the `build.yaml` label, and an **amd64 image
  build** against the real Alpine 3.21 base. The build catches *build* breaks,
  not runtime ones like the musl `statx` crash (that only shows on a device).
- **`claude-version-bump.yml`** — weekly (and manual via "Run workflow").
  Detects a newer Claude Code release via the npm registry and opens a PR that
  bumps `CLAUDE_VERSION`, the add-on version, the `build.yaml` label, and the
  changelog — the golden-rule update, ready to review and merge. Requires the
  repo setting *Actions → General → "Allow GitHub Actions to create and approve
  pull requests"* (already enabled).
- **`claude.yml`** — the `@claude` responder for issues/PRs (unchanged).

## Conventions

- **Releases follow the [Release standard](#release-standard)** above — SemVer,
  as-needed batched cadence, Keep a Changelog, Conventional Commits, and a
  tag + GitHub Release per version. Not every PR is a release; batch under
  `## Unreleased`.
- Add-on shell scripts use `#!/usr/bin/with-contenv bashio` and
  `bashio::log.*` for output; `persist-install` is plain `#!/bin/bash`.
- YAML: 2-space indent. Shell: 4-space indent.
- Prefer **baking** tools into the image over runtime `apk add` when they must be
  reliably present.

## Where the details live

The source is commented with the rationale for each fix — read it before
changing it: `build.yaml` (base/`statx`), `Dockerfile` (`CLAUDE_VERSION`),
`config.yaml` (options/schema), `run.sh` (launcher hardening, auto-install),
`scripts/persist-install` (copy + `ldd` dep resolution). Release history is in
`claude-terminal/CHANGELOG.md`.
