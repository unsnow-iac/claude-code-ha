# Claude Code for Home Assistant

A Home Assistant add-on that runs Anthropic's Claude Code CLI in a browser terminal, with persistent package management and image-paste support. A maintained, community fork of the now-dormant upstream add-on.

> **Community add-on** — not affiliated with, endorsed by, or supported by Anthropic or the Home Assistant project / Open Home Foundation. "Claude" and "Claude Code" are trademarks of Anthropic, PBC; "Home Assistant" is a trademark of the Open Home Foundation. Claude Code itself is subject to Anthropic's terms.

---

## ⚙️ unsnow fork

This is a maintenance fork of [ESJavadex/claude-code-ha](https://github.com/ESJavadex/claude-code-ha), kept on the `main` branch of [`unsnow-iac/claude-code-ha`](https://github.com/unsnow-iac/claude-code-ha). It exists to fix issues that broke the environment in practice:

| Fixed | Why it mattered |
|---|---|
| **Base image → Alpine 3.21** (was 3.19) | Alpine 3.19 ships musl 1.2.4, which lacks the `statx` symbol current Claude Code native builds require — newer binaries crashed at launch with `Error relocating ...: statx: symbol not found`. 3.21 ships musl 1.2.5. |
| **Claude pinned + baked; `ttyd`/`tmux` baked** | Reproducible builds (`ARG CLAUDE_VERSION`); web terminal and tmux no longer depend on `apk` reaching the network at every boot. |
| **`persist-install` rewritten** | `apk info -L` lists paths *without* a leading slash, so the old `== /usr/bin/*` test never matched — the script reported success but copied nothing, so packages vanished on container recreation. Now normalises paths and resolves real deps via `ldd`. |
| **Removed the `persistent_claude` layer** | It checked an obsolete `cli.js` path (always warned, silently fell back) and `npm install`-ed `@latest` into `/data/npm`, fighting the baked-binary model. The launcher is now force-linked to the baked binary on every boot, so a stray `claude update` self-heals on restart. |

### Updating Claude Code

In-container self-update is disabled by design. To ship a new Claude version:

1. Bump `ARG CLAUDE_VERSION` in `claude-terminal/Dockerfile`.
2. Bump `version:` in `claude-terminal/config.yaml` and `claude-terminal/build.yaml`.
3. Commit, push to `main`, then **Update**/**Rebuild** the add-on in Home Assistant.

The add-on builds on-device (no prebuilt image), so the rebuild picks up the new base + pinned Claude. `/data` (auth, config, packages) is preserved across rebuilds.

---

## What it does

A browser-terminal Claude Code CLI for Home Assistant, opened from the sidebar
(ingress only — no host port by default). It starts in `/config`, so Claude can
read and edit your Home Assistant configuration in place: write automations and
scripts, run `git`, and install packages that persist across restarts. The
Claude binary is pinned and updated by rebuilding the add-on.

## Pairs with the Home Assistant MCP server

Treat this add-on as a **shell + config editor**, and pair it with the **Home
Assistant MCP server** add-on for *operating* Home Assistant:

- **Operate HA via the MCP** — call services, query state, manage
  entities/areas/other add-ons, the host, and backups through an audited,
  structured channel.
- **Author config in this terminal** — edit the YAML under `/config`, run shell
  tooling, and have Claude write changes directly into your configuration.

By design this add-on carries only a **`homeassistant`**-level Supervisor token
(not `manager`): `ha core check`/`restart`/`info` keep working, but shell-level
control of other add-ons, the host, Docker, and backups is intentionally
dropped — route those through the MCP. Power users who need shell `manager`
access must run a local copy with `hassio_role: manager` (it's a fixed manifest
field, not raisable from the HA UI). See the
[add-on README](claude-terminal/README.md) for details.

## Fork Attribution

Forked from [ESJavadex/claude-code-ha](https://github.com/ESJavadex/claude-code-ha) by Javier Santos, itself a fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons) by Tom Cassady. Maintained by [unsnow-iac](https://github.com/unsnow-iac).

This fork exists to fix breakages that left the upstream add-on unusable (see the **unsnow fork** section near the top) and to keep it actively maintained.

### What earlier forks added

- **Image Paste Support**: Upload images via paste (Ctrl+V), drag-drop, or upload button for Claude analysis
- **Persistent Package Management**: Install system and Python packages that survive reboots
- **Auto-install Configuration**: Configure packages to auto-install on startup
- **Improved Credential Handling**: Enhanced authentication persistence
- **Additional Documentation**: Comprehensive guides for development and usage

This project maintains the same MIT license as the original.

## Installation

To add this repository to your Home Assistant instance:

1. Go to **Settings** → **Add-ons** → **Add-on Store**
2. Click the three dots menu in the top right corner
3. Select **Repositories**
4. Add the URL: `https://github.com/unsnow-iac/claude-code-ha`
5. Click **Add**

## Add-ons

### Claude Code for Home Assistant

A web-based terminal interface with Claude Code CLI pre-installed and enhanced package management. This add-on provides a terminal environment directly in your Home Assistant dashboard, allowing you to use Claude's powerful AI capabilities for coding, automation, and configuration tasks.

#### Core Features
- Web terminal access through your Home Assistant UI
- Pre-installed Claude Code CLI that launches automatically
- Direct access to your Home Assistant config directory
- No configuration needed (uses OAuth)
- Access to Claude's complete capabilities including:
  - Code generation and explanation
  - Debugging assistance
  - Home Assistant automation help
  - Learning resources

#### Enhanced Features
- **Image Paste Support**: Paste (Ctrl+V), drag-drop, or upload images for Claude analysis
  - Lightweight service (~10MB RAM, ARM-compatible)
  - Supports JPEG, PNG, GIF, WebP, SVG (10MB limit)
  - Persistent storage in `/data/images/`
  - Perfect for OCR, image analysis, screenshot debugging
- **Persistent Package Management**: Install packages that survive container restarts
- **Auto-install Packages**: Configure APK and pip packages to auto-install on startup
- **Python Virtual Environment**: Isolated Python environment for packages
- **Simple Commands**: Use `persist-install` for easy package management
- **Unrestricted Mode**: Option to run Claude with `--dangerously-skip-permissions` for full file access

#### Configuration Options
- `auto_launch_claude`: Auto-start Claude or show session picker (default: true)
- `dangerously_skip_permissions`: Enable unrestricted file access (default: false)
- `persistent_apk_packages`: System packages to auto-install
- `persistent_pip_packages`: Python packages to auto-install

[Documentation](claude-terminal/DOCS.md)

## Community Tools

Tools built by the community to enhance Claude Code for Home Assistant:

- **[ha-ws-client-go](https://github.com/schoolboyqueue/home-assistant-blueprints/tree/main/scripts/ha-ws-client-go)** by [@schoolboyqueue](https://github.com/schoolboyqueue) - Lightweight Go CLI for Home Assistant WebSocket API. Gives Claude direct access to entity states, service calls, automation traces, and real-time monitoring. Single binary, no dependencies.

## Support

If you have any questions or issues with this add-on, please create an issue in this repository.

## Credits

**Original Creator:** Tom Cassady ([@heytcass](https://github.com/heytcass)) - Created the initial Claude Terminal add-on
**Earlier Fork:** Javier Santos ([@esjavadex](https://github.com/esjavadex)) - Added persistent package management and enhancements
**Current Maintainer:** [unsnow-iac](https://github.com/unsnow-iac) - Alpine 3.21/statx fix, persist-install repair, public release

This add-on was created and enhanced with the assistance of Claude Code itself! The development process, debugging, and documentation were all completed using Claude's AI capabilities.

## License

This repository is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
