# Contributing

Thanks for your interest in this add-on. It's a small, solo-maintained project, so
this guide is short.

## Ground rules

- **Open an issue first** for anything non-trivial (a bug, a feature idea) so we can
  agree on the approach before you spend time on a PR.
- **Security issues are different — do not open a public issue.** Follow
  [`SECURITY.md`](SECURITY.md) and report privately.
- Keep changes **small and focused**: one logical change per pull request.

## Where the code lives

The add-on lives entirely in [`claude-terminal/`](claude-terminal/). Everything at
the repo root (`flake.nix`, CI, docs) is tooling. The
[`CLAUDE.md`](CLAUDE.md) at the repo root documents the architecture, the golden
rule for shipping a Claude update, the release standard, and the invariants that
must not regress — **read it before changing anything.**

## Development

A Nix dev shell provides the tools (podman, hadolint, shellcheck helpers):

```bash
nix develop        # or `direnv allow`
```

Build and run against the real base image (note: Alpine **3.21**, which exports the
`statx` symbol newer Claude builds need):

```bash
podman build \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21 \
  -t local/claude-terminal:test ./claude-terminal

podman run -d --name cc-test -p 7680:7680 -v /tmp/cc-config:/config local/claude-terminal:test
podman logs -f cc-test
podman stop cc-test && podman rm cc-test
```

## What CI checks (run these locally first)

Every PR runs, in parallel:

- **hadolint** on `claude-terminal/Dockerfile` (intentional rule exceptions live in
  `.hadolint.yaml`)
- **shellcheck** on the shell scripts (`-s bash`, `severity: error`)
- the **Home Assistant add-on manifest linter**
- a **version-sync** guard: `config.yaml` `version` must equal the `build.yaml`
  `org.opencontainers.image.version` label
- an **amd64 image build + smoke test** that actually runs the built image (execs
  the Claude binary and probes the image-service `/health`) — this is what catches
  the runtime `statx`-class crash a plain build can't see

## Commits, versioning, releases

- **Conventional Commits** (`feat`, `fix`, `chore`, `docs`, `ci`, `build`, …).
  `feat!:` or a `BREAKING CHANGE:` footer marks a breaking change.
- **No AI-attribution trailers** in commit messages.
- **SemVer**, with the twist documented in `CLAUDE.md`: MINOR is a new *add-on*
  capability, PATCH covers fixes/hardening **and routine Claude CLI bumps**, MAJOR
  is a breaking change to config or the access model.
- Add a note under `## Unreleased` in
  [`claude-terminal/CHANGELOG.md`](claude-terminal/CHANGELOG.md) (Keep a Changelog).
  Releases are **batched** — don't bump the version in every PR; the maintainer cuts
  a single versioned release when shipping.

The full release procedure is the **Release standard** section of `CLAUDE.md`.
