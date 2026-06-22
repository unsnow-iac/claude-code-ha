# Claude Code for Home Assistant

A web-based terminal for Anthropic's Claude Code CLI in Home Assistant.

> **Community add-on** — not affiliated with, endorsed by, or supported by
> Anthropic or the Home Assistant project / Open Home Foundation. "Claude" and
> "Claude Code" are trademarks of Anthropic, PBC; "Home Assistant" is a trademark
> of the Open Home Foundation. Claude Code itself is subject to Anthropic's terms.

## About

Claude Code for Home Assistant is a maintained, community fork of the original
Claude Terminal add-on, providing a web-based terminal with the Claude Code CLI
pre-installed plus persistent package management. Access Claude's capabilities
directly from your Home Assistant dashboard, with the added benefit of installing
and persisting custom packages across restarts.

## Installation

1. Add this repository to your Home Assistant add-on store:
   - Go to Settings → Add-ons → Add-on Store
   - Click the menu (⋮) and select Repositories
   - Add: `https://github.com/unsnow-iac/claude-code-ha`
2. Install the Claude Code for Home Assistant add-on
3. Start the add-on
4. Open it from the **Claude Code** sidebar panel (ingress) — there is no
   separate host-port web UI by default
5. On first use, follow the OAuth prompts to log in to your Anthropic account

## Configuration

The add-on offers several configuration options:

### Auto Launch Claude
- **Default**: `true`
- When enabled, Claude starts automatically when you open the terminal
- When disabled, shows an interactive session picker menu

### Dangerously Skip Permissions
- **Default**: `false`
- When enabled, Claude runs with `--dangerously-skip-permissions` flag
- **⚠️ WARNING**: This gives Claude unrestricted file system access
- Use only if you understand the security implications
- Useful for advanced users who need full file access

### Persistent Packages
- Configure APK and pip packages to auto-install on startup
- Packages are stored in `/data/packages` and survive restarts

### Home Assistant operations (use the MCP server)
This add-on is a shell + config editor. It carries only a `homeassistant`-level
Supervisor token, so `ha core check`/`restart`/`info` work, but managing other
add-ons, the host, Docker, and backups from the shell is intentionally not
permitted. To *operate* Home Assistant from Claude, pair this with the **Home
Assistant MCP server** add-on. Power users who need shell-level `manager` access
must run a local copy with `hassio_role: manager` (a fixed manifest field, not
raisable from the HA UI).

**Example Configuration**:
```yaml
auto_launch_claude: false
dangerously_skip_permissions: true
persistent_apk_packages:
  - python3
  - git
persistent_pip_packages:
  - requests
```

Your OAuth credentials are stored in the `/config/claude-config` directory and
will persist across add-on updates and restarts, so you won't need to log in
again.

### Updating Claude Code

In-container self-update is disabled by design — the install is a self-contained
native binary baked into the image, and an in-place `claude update` can brick the
next launch. New Claude versions ship by bumping `ARG CLAUDE_VERSION` and
rebuilding the add-on (see the repository README). `/data` is preserved across
rebuilds, so updating is non-destructive.

## Usage

Claude launches automatically when you open the terminal. You can also start
Claude manually with:

```bash
claude
```

### Common Commands

- `claude -i` - Start an interactive Claude session
- `claude --help` - See all available commands
- `claude "your prompt"` - Ask Claude a single question
- `claude process myfile.py` - Have Claude analyze a file
- `claude --editor` - Start an interactive editor session

The terminal starts directly in your `/config` directory, giving you immediate
access to all your Home Assistant configuration files. This makes it easy to get
help with your configuration, create automations, and troubleshoot issues.

## Features

### Core Features
- **Web Terminal**: Access a full terminal environment via your browser
- **Auto-Launching**: Claude starts automatically when you open the terminal
- **Claude AI**: Access Claude's AI capabilities for programming, troubleshooting and more
- **Direct Config Access**: Terminal starts in `/config` for immediate access to all Home Assistant files
- **Simple Setup**: Uses OAuth for easy authentication
- **Home Assistant Integration**: Access directly from your dashboard

### Enhanced Features
- **Persistent Packages**: Install system (APK) and Python (pip) packages that survive restarts
- **Auto-Install Configuration**: Set packages to auto-install on startup
- **Simple Management**: Use `persist-install` command for easy package installation
- **Python Virtual Environment**: Isolated Python environment in `/data/packages`

## Troubleshooting

- If Claude doesn't start automatically, try running `claude -i` manually
- If you see permission errors, try restarting the add-on
- If you have authentication issues, try logging out and back in
- Check the add-on logs for any error messages

## Credits

**Original Creator:** Tom Cassady ([@heytcass](https://github.com/heytcass))
**Earlier Fork:** Javier Santos ([@esjavadex](https://github.com/esjavadex))
**Current Maintainer:** [unsnow-iac](https://github.com/unsnow-iac)

Forked from [ESJavadex/claude-code-ha](https://github.com/ESJavadex/claude-code-ha),
itself a fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons).
