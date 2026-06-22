# Claude Code for Home Assistant

A web-based terminal with the Claude Code CLI and persistent package management for Home Assistant.

![Claude Code terminal screenshot](screenshot.png)

*The Claude Code terminal running in Home Assistant*

> **Community add-on** — not affiliated with, endorsed by, or supported by Anthropic or the Home Assistant project / Open Home Foundation. "Claude" and "Claude Code" are trademarks of Anthropic, PBC; "Home Assistant" is a trademark of the Open Home Foundation.

> **Fork Attribution:** Forked from [ESJavadex/claude-code-ha](https://github.com/ESJavadex/claude-code-ha) by Javier Santos, itself a fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons) by Tom Cassady. Maintained by [unsnow-iac](https://github.com/unsnow-iac).

## What is this add-on?

This add-on gives you Anthropic's **Claude Code CLI** in a browser terminal,
opened straight from your Home Assistant sidebar. The terminal starts in your
`/config` directory, so Claude can read and edit your Home Assistant
configuration in place — ideal for:

- Writing and editing automations, scripts, and YAML config
- Debugging problems in your setup
- Learning new programming concepts
- General coding and shell work, with persistent package installs

Access is through the **authenticated Home Assistant ingress panel** — there is
no host port and no separate web UI to expose. The Claude binary is **pinned**
to a known-good version and updated by rebuilding the add-on, not from inside the
container (see *Updating Claude Code* in the [repository README](../README.md)).

## Features

### Core Features
- **Web Terminal Interface**: Access Claude through a browser-based terminal using ttyd, served only over the Home Assistant ingress panel (no host port by default)
- **Auto-Launch**: Claude starts automatically when you open the terminal
- **Pinned Claude Code CLI**: Anthropic's official CLI, baked in at a known-good version for reproducible builds (updated by rebuilding the add-on)
- **No Configuration Needed**: Uses OAuth authentication for easy setup
- **Direct Config Access**: Terminal starts in your `/config` directory for immediate access to all Home Assistant files
- **Home Assistant Integration**: Access directly from your dashboard
- **Panel Icon**: Quick access from the sidebar with the code-braces-box icon
- **Multi-Architecture Support**: Works on amd64 and aarch64 platforms
- **Secure Credential Management**: Persistent authentication with safe credential storage
- **Automatic Recovery**: Built-in fallbacks and error handling for reliable operation

### Enhanced Features
- **Persistent Package Management**: Install APK and pip packages that survive container restarts
- **Auto-Install Configuration**: Configure packages to install automatically on startup
- **Python Virtual Environment**: Isolated Python environment in `/data/packages`
- **Simple Commands**: Use `persist-install` for easy package management
- **Persistent Storage**: All packages stored in `/data` which survives all reboots

## Quick Start

The terminal automatically starts Claude when you open it. You can immediately start using commands like:

```bash
# Ask Claude a question directly
claude "How can I write a Python script to control my lights?"

# Start an interactive session
claude -i

# Get help with available commands
claude --help
```

## Using it with the Home Assistant MCP server (recommended)

This add-on is a **shell + config editor**, not a Home Assistant control plane.
The recommended companion is the **Home Assistant MCP server** add-on, which
gives Claude an audited, structured channel to *operate* Home Assistant.
Division of labour:

- **Operate Home Assistant via the MCP** — call services, query state, manage
  entities/areas, manage other add-ons, the host, and backups.
- **Use this terminal for shell + config authoring** — read and edit the files
  under `/config`, run `git`, install packages, and have Claude write
  automations and scripts directly into your configuration.

### Supervisor token scope (least privilege)

This add-on intentionally carries only a **`homeassistant`**-level Supervisor
token, **not `manager`**. That keeps `ha core check` / `restart` / `info`
working while deliberately *dropping* shell-level control of other add-ons, the
host, Docker, and backups. Route those **HA operations through the MCP server**
instead.

If you specifically need shell-level `manager` access (e.g. scripting other
add-ons from the terminal), the Supervisor role is a fixed manifest field that
**cannot** be raised from the HA UI — run a local/forked copy of this add-on
with `hassio_role: manager` in `config.yaml` and accept the broader exposure.

## Installation

1. Add this repository to your Home Assistant add-on store:
   - Go to Settings → Add-ons → Add-on Store
   - Click the menu (⋮) and select Repositories
   - Add: `https://github.com/unsnow-iac/claude-code-ha`
2. Install the Claude Code for Home Assistant add-on
3. Start the add-on
4. Open it from the **Claude Code** sidebar panel (ingress) — there is no
   separate "Open Web UI" host port by default
5. On first use, follow the OAuth prompts to log in to your Anthropic account

## Configuration

The add-on works out of the box. Configurable options — auto-launch,
`dangerously_skip_permissions`, ha-mcp auto-wiring, the onboarding hint, and
persistent-package auto-install — are documented in the
[options table](../README.md#configuration) in the repository README. Other facts:

- **Access**: Served over the authenticated Home Assistant ingress panel; the
  direct `7680`/`7681` host ports are unset by default and should stay that way
  (ttyd runs unauthenticated, so a host-mapped port is an open root shell on
  your LAN)
- **Authentication**: OAuth with Anthropic (credentials stored under `/data/.config/claude`, which persists across restarts and rebuilds)
- **Terminal**: Full bash environment with Claude Code CLI pre-installed
- **Volumes**: Read/write access to `/config` (Home Assistant configuration)

## Troubleshooting

### Authentication Issues
Credentials live under `/data/.config/claude` and persist across restarts and
rebuilds. If you have authentication problems, re-run the OAuth flow from inside
the terminal:
```bash
claude        # prompts you to log in again if no valid credentials are found
```

### Container Issues
- Credentials are automatically saved and restored between restarts
- Check add-on logs if the terminal doesn't load
- Restart the add-on if Claude commands aren't recognized

For local development and testing, see [Development Environment](#development-environment) below.

## Architecture

- **Base Image**: Home Assistant Alpine Linux base (3.21; musl 1.2.5, which exports the `statx` symbol newer Claude builds require)
- **Container Runtime**: Compatible with Docker/Podman
- **Web Terminal**: ttyd for browser-based access (with `tmux`)
- **Startup**: `init: false` — `run.sh` is the entrypoint; it sets up `/data`, launches the image-upload service, then `exec`s ttyd
- **Networking**: Ingress support with Home Assistant reverse proxy

## Security

- **Least-privilege Supervisor token** — the add-on requests only the
  `homeassistant` role, not `manager`, so the shell cannot control other add-ons,
  the host, Docker, or backups; route those through the [MCP server](#using-it-with-the-home-assistant-mcp-server-recommended).
- **Ingress-only by default** — no host port; access is through the authenticated
  Home Assistant panel.
- **Credentials** stored with `600` permissions under `/data` and never in a
  git-trackable location.
- **Pinned + checksum-verified** `ha`/`gh` CLIs; auto-update disabled in favour of
  rebuild-based updates.

See the [CHANGELOG](CHANGELOG.md) (notably 4.4.0) for the full security history.

## Development Environment

This add-on includes a comprehensive development setup using Nix:

```bash
# Available development commands
build-addon      # Build the add-on container with Podman
run-addon        # Run add-on locally on port 7681
lint-dockerfile  # Lint Dockerfile with hadolint
test-endpoint    # Test web endpoint availability
```

**Requirements for development:**
- NixOS or Nix package manager
- Podman (automatically provided in dev shell)
- Optional: direnv for automatic environment activation

## Documentation

For detailed usage instructions, see the [documentation](DOCS.md).

## Version History

See [CHANGELOG.md](CHANGELOG.md) for all releases. The fork's headline fixes
(Alpine 3.21/`statx`, `persist-install` repair, least-privilege token, ha-mcp
wiring) are summarised in the [repository README](../README.md#about-this-fork).

## Useful Links

- [Claude Code Documentation](https://docs.anthropic.com/claude/docs/claude-code)
- [Get an Anthropic API Key](https://console.anthropic.com/)
- [Claude Code GitHub Repository](https://github.com/anthropics/claude-code)
- [Home Assistant Add-ons](https://www.home-assistant.io/addons/)

## Credits

**Original Creator:** Tom Cassady ([@heytcass](https://github.com/heytcass)) - Created the initial Claude Terminal add-on
**Earlier Fork:** Javier Santos ([@esjavadex](https://github.com/esjavadex)) - Added persistent package management and enhancements
**Current Maintainer:** [unsnow-iac](https://github.com/unsnow-iac) - Alpine 3.21/statx fix, persist-install repair, least-privilege token, ha-mcp wiring, public release

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.