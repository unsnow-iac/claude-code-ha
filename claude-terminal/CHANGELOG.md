# Changelog

## Unreleased

### 🔗 Home Assistant MCP (ha-mcp) auto-wiring
- The add-on can now register the [`homeassistant-ai/ha-mcp`](https://github.com/homeassistant-ai/ha-mcp)
  server with Claude Code **on boot**, so the terminal opens already connected to
  Home Assistant's structured `ha_*` tools — no manual `claude mcp add`.
- **Setup:** install the separate **Home Assistant MCP Server** add-on, copy the
  URL it prints in its log (`http://<host>:9583/private_<secret>`), and paste it
  into the new **`home_assistant_mcp_url`** option. The secret path is the
  credential — no token is needed. Master switch **`enable_home_assistant_mcp`**
  (default `true`).
- **Not a privilege regression.** ha-mcp is a *separate* add-on holding its own
  `manager` token; this add-on's token stays `homeassistant`-scoped. Wiring routes
  HA operations through that audited MCP channel — exactly the path 4.4.0 intended —
  rather than through a broad ambient Supervisor token.
- **Safe by default for existing setups.** An empty `home_assistant_mcp_url` is a
  pure no-op (no Claude config is touched). When a URL is set, the add-on dedups by
  host:port: a connection to that server under a *different* name is left untouched
  rather than duplicated; the entry the add-on manages is named `ha-mcp` and is
  updated to match the option. The secret URL is never written to the log.

### 🧭 Onboarding hint for Claude
- On boot the add-on seeds a short orientation note into the **user-level** Claude
  memory (`~/.claude/CLAUDE.md`) so Claude knows it's in the HA add-on and prefers the
  `ha-mcp` `ha_*` tools for HA operations over raw shell. Master switch
  **`enable_onboarding_hint`** (default `true`); set `false` to remove it.
- **Never touches your `/config`.** It manages only a marker-delimited block in the
  add-on's own home dir, which Claude merges with — and never overrides — your
  `/config/CLAUDE.md`. Idempotent (no per-boot churn) and refuses to edit a file whose
  markers look hand-modified.

## 4.4.0

A hygiene release batching least-privilege, supply-chain, robustness, and docs
fixes.

### 🔒 Least privilege — Supervisor token lowered `manager` → `homeassistant`
- The add-on no longer requests the broad `manager` Supervisor role. It now
  carries only `hassio_role: homeassistant`, which keeps `ha core
  check`/`restart`/`info` working while **dropping** shell-level control of other
  add-ons, the host, Docker, and backups (the `/addons/*`, `/host/.+`,
  `/docker/.+`, `/backups.*` surface).
- **What to do instead:** operate Home Assistant through the **Home Assistant MCP
  server** add-on — an audited, structured channel for those operations.
- **Heads-up:** `hassio_role` is a fixed manifest field that **cannot** be raised
  from the HA UI. If you need shell-level `manager` access, run a local/forked
  copy with `hassio_role: manager`. See the README.

### 🔗 Supply chain — `ha` and `gh` CLIs pinned + checksum-verified
- The Dockerfile previously fetched `ha` and `gh` from `releases/latest` via
  unauthenticated GitHub API calls — unpinned and unverified. Both are now pinned
  (`HA_CLI_VERSION=5.2.0`, `GH_VERSION=2.95.0`) and **sha256-verified** at build:
  `gh` against its published `*_checksums.txt`, `ha` against hardcoded per-arch
  hashes (the HA CLI ships no checksums file). Builds are now reproducible and
  the unauthenticated API lookups are gone.

### 🛡️ Robustness — a failed image service no longer kills the terminal
- `run.sh` runs under `set -e`; a non-zero return from the (non-critical) image
  upload service would abort the whole add-on before `ttyd` started. The call is
  now guarded, so the terminal still comes up (image upload disabled) if that
  service fails.

### 📝 Docs & positioning refresh
- Rewrote the store and repository READMEs and `DOCS.md`: removed stale claims
  (`@latest`, `armv7`, host port `7681`, the `/addons` mount, the old
  `claude-auth`/`claude-logout` commands, and the "Open Web UI" host port).
- Added a **Home Assistant MCP server** companion section documenting the
  shell-vs-operate division of labour and the new token scope.
- Removed the broken third-party "Recommended Plugins" instructions
  (`npx claude-plugins install …`); the ha-mcp pairing is the recommended path.

## 4.3.3

### 🗑️ Dropped the deprecated `armv7` (32-bit ARM) architecture
- Home Assistant ended support for `armv7` add-ons in **2025.12**. Removed it from
  `config.yaml` (`arch`) and `build.yaml` (`build_from`); the add-on now targets
  `aarch64` and `amd64`. 64-bit ARM devices (Raspberry Pi 3/4/5 on a 64-bit OS)
  are unaffected — only 32-bit ARM installs, which current Home Assistant no
  longer runs add-ons on, are dropped.

## 4.3.2

### 🧹 Maintenance
- **Removed the redundant `panel_admin: true`** from `config.yaml`. `true` is
  already the default, so the line was a no-op; the new add-on manifest linter
  (added to CI) flags explicitly-set defaults. No functional change — the panel
  remains admin-only.

## 4.3.1

### 🧹 Maintenance
- **`multer` upgraded `1.4.5-lts.1` → `^2.0.0`** in the image-upload service. The
  1.x line is end-of-life and flagged by `npm audit`; 2.x is the maintained line.
  The APIs the service uses (`diskStorage`, `single`, `MulterError`) are unchanged.
- **Fixed image provenance label**: `build.yaml`'s `org.opencontainers.image.source`
  pointed at `anthropics/claude-code` (Anthropic's CLI repo) instead of this fork.
  It now points at `unsnow-iac/claude-code-ha`.
- **Removed the stale `DEVELOPMENT_STATUS.md`**: it described an in-progress
  "90% complete — auth persistence issue" from early development that has long
  since shipped. The current state lives in this changelog and `CLAUDE.md`.

## 4.3.0

### 🔒 Security — terminal is no longer exposed on the host network by default
- **Host ports default to `null` (not exposed).** Previously `config.yaml` mapped
  ports `7680`/`7681` straight to the host, and `ttyd` runs `--writable` with no
  credentials — so anyone on the LAN could open `http://<ha-host>:7681` and get an
  **unauthenticated root shell** with Claude, bypassing the Home Assistant login
  entirely (and unrestricted if `dangerously_skip_permissions` was on).
- **Use the ingress panel instead.** The add-on is meant to be used through the
  authenticated Home Assistant ingress panel, which is unaffected by this change.
- **Power users can still opt in:** assign a host port from the add-on's *Network*
  panel if you understand and accept the risk. The `webui` button (which required
  a host-mapped port) was removed in favour of the ingress panel.

## 4.2.0

First public release of the fork, now named **Claude Code for Home Assistant**.
The fork's earlier fixes landed incrementally as unreleased 3.0.x development
versions and are consolidated into this first tagged release.

### 🔧 Fixes consolidated from the unreleased 3.0.x work
- **Base image → Alpine 3.21 (musl 1.2.5)**: Alpine 3.19 (musl 1.2.4) lacks the `statx` symbol current Claude Code native builds require, so newer binaries crashed at launch with `Error relocating ...: statx: symbol not found`. 3.21 ships musl 1.2.5, which exports `statx`.
- **`persist-install` rewritten**: `apk info -L` lists paths without a leading slash, so the old match never fired — the script reported success but copied nothing, and packages vanished on container recreation. It now normalises paths and resolves real shared-library deps via `ldd`.
- **Removed the dead `persistent_claude` layer**: it targeted an obsolete `cli.js` path and fought the baked-binary model. The launcher is now force-linked to the baked binary on every boot, so a stray `claude update` self-heals on restart.
- **`persistent_apk_packages` / `persistent_pip_packages` auto-install fix**: `bashio::config` already expands a list option into newline-separated values; `run.sh` piped that back through `jq -r '.[]'`, double-parsing non-JSON and aborting startup with `jq: parse error`. Now consumes the expanded lines directly with null/empty guards.

### 📦 Public release
- **Rebranded** to **Claude Code for Home Assistant** (add-on name, panel title, repository metadata). The internal slug (`claude_terminal_unsnow`) is unchanged, so existing installs update in place — no reinstall needed.
- **Restored a proper MIT `LICENSE`** crediting the full fork lineage (the inherited file still carried an unfilled `[Your Name]` placeholder).
- **Fixed install pointers**: `repository.yaml` and the README/DOCS install URLs now point at `unsnow-iac/claude-code-ha`.
- **Fixed stale dev docs**: the `nix develop` `build-addon` alias and the `DEVELOPMENT.md` build commands now use the Alpine 3.21 base (were 3.19).
- **Removed docs for the deleted persistent-Claude options** from `DOCS.md` (the example config no longer references removed schema keys).
- **Added a community / non-affiliation disclaimer** across the docs.

## 2.0.11

### ✨ New Feature - Optional Persistent Claude Code Override
- **Safe-by-default persistent Claude support**: Added optional `use_persistent_claude` mode that lets advanced users run a Claude Code version installed under `/data/npm/`
  - **Default remains unchanged**: the add-on still uses the Claude version baked into the image unless explicitly enabled
  - **Official startup-managed symlink**: `/usr/local/bin/claude` now points to the persistent install during startup when present
  - **No self-modifying menu scripts**: persistent override is handled in `run.sh`, keeping behavior deterministic and easier to support
- **Optional startup updates**: Added `auto_update_claude_on_start` (default: `false`)
  - When enabled together with `use_persistent_claude`, the add-on runs `npm install -g @anthropic-ai/claude-code@latest` into `/data/npm/` at startup
  - If the update fails, startup continues and uses the previously installed persistent version when available
- **Session picker version visibility**: Interactive menu now shows the active Claude Code version at the top

## 2.0.10

### 🐛 Bug Fix - CPU Compatibility with AVX Fallback
- **Native installer with automatic npm fallback**: Fixed Docker build failure on CPUs without AVX support (#5)
  - **How it works**: Tries native installer first (Bun-based, recommended by Anthropic); if it fails (e.g., CPU lacks AVX), automatically falls back to npm installation
  - **Affected hardware**: Older NUCs, Intel Atom/Celeron processors, some virtualized environments (Proxmox, VirtualBox on older hosts)
  - **Modern hardware**: No change — continues using the native installer as before
  - **Result**: Add-on now builds on all CPUs without sacrificing the recommended install method for capable hardware

## 2.0.9

### 🐛 Bug Fix - First Connection Drop on Terminal Load
- **Removed invalid ttyd client options**: `enableReconnect` and `reconnectInterval` are hterm options not supported by ttyd 1.7.4 (xterm.js-based), causing the WebSocket client to error and disconnect on first load
  - Kept only valid options: `--ping-interval 30` and `--client-option reconnect=5`
  - First connection now establishes cleanly without requiring a retry

## 2.0.8

### 🐛 Bug Fix - Image Service Crash on WebSocket Errors (#8)
- **Fixed `res.status is not a function` crash**: The proxy `onError` handler in `server.js` now checks whether `res` is an Express response (HTTP) or a raw socket (WebSocket) before calling `.status()`
  - Previously, WebSocket proxy errors crashed the entire image service process
  - Now gracefully handles both HTTP and WebSocket error scenarios

### 🐛 Bug Fix - Disable Auto-Update Nag Inside Container (#7)
- **Suppressed Claude CLI update prompts**: Set `DISABLE_AUTOUPDATER=1` in both runtime environment and profile script
  - Claude Code binary is baked into the container image; updates are delivered via add-on releases
  - Eliminates the persistent "update available" banner on every session start

### 🐛 Bug Fix - Session Reconnection After Disconnect (#6)
- **Fixed "Press return to reconnect" not working**: Removed `exec` from session picker launch functions so Claude exiting returns to the menu instead of terminating the process
  - When Claude CLI exits (via `/exit`, Escape, or crash), the session picker menu now reappears automatically
  - Bash shell sessions also return to menu on `exit`
  - Removed aggressive EXIT trap that was killing the session picker prematurely
- **Added ttyd keepalive and auto-reconnect**: Configured `--ping-interval 30` and client-side reconnect options to prevent WebSocket idle disconnects and automatically recover from network interruptions

## 2.0.7

### 🐛 Bug Fix - Native Install Path Mismatch
- **Fixed "installMethod is native, but directory does not exist" error**: Claude binary now available at `$HOME/.local/bin/claude` at runtime
  - **Root cause**: Native installer places Claude at `/root/.local/bin/claude` during Docker build, but at runtime `HOME=/data/home`, so Claude's self-check looks in `/data/home/.local/bin/claude` which didn't exist
  - **Solution**: Symlink created from `/data/home/.local/bin/claude` → `/root/.local/bin/claude` on startup
  - **PATH updated**: Added `/data/home/.local/bin` to PATH in both runtime and profile script
  - **Result**: Claude native binary resolves correctly regardless of HOME directory change

## 2.0.6

### 🛠️ Improvement - Native Claude Code Installation
- **Migrated to native installer**: Claude Code now installed using Anthropic's recommended native binary installer
  - Replaces npm installation (`@anthropic-ai/claude-code`) with `curl -fsSL https://claude.ai/install.sh | bash`
  - More reliable builds (no npm retry logic needed)
  - Follows Anthropic's official distribution method
  - npm installation is deprecated by Anthropic
- **Updated health checks**: Network connectivity now validates `claude.ai` instead of npm registry
- **Simplified run.sh**: Removed `node $(which claude)` wrapper, now calls `claude` directly

## 2.0.5

### 🐛 Bug Fix - Claude CLI Not Found
- **Fixed session picker failing to launch Claude**: Used full path `/usr/local/bin/claude`
  - ttyd bash sessions don't inherit full PATH from parent process
  - All claude invocations now use absolute path for reliability

## 2.0.4

### ✨ New Feature - GitHub CLI Pre-installed
- **GitHub CLI (gh) included**: GitHub's official CLI tool now pre-installed in Docker image
  - Create, view, and manage GitHub issues and pull requests
  - Work with GitHub repositories directly from the terminal
  - Authenticate with `gh auth login`
  - Essential for git workflows: `gh pr create`, `gh issue list`, `gh repo clone`
  - Automatically fetches latest version during build

### 🛠️ Improvement - Persistent GitHub Authentication
- **GitHub credentials survive reboots**: `GH_CONFIG_DIR` set to `/data/.config/gh`
  - Login once with `gh auth login`, credentials persist across container restarts
  - Consistent with Claude credential persistence approach
  - No need to re-authenticate after Home Assistant updates
- **Session picker menu option**: New "🐙 GitHub CLI login" option (choice 6)
  - Guided authentication flow with browser or token options
  - Shows current auth status before prompting
  - Instructions for creating GitHub personal access tokens

## 2.0.3

### ✨ New Features - Enhanced Developer Toolkit
- **Pre-installed Python libraries**: Common libraries for Home Assistant scripting
  - `py3-requests` - HTTP library for API calls
  - `py3-aiohttp` - Async HTTP client/server
  - `py3-yaml` - YAML parsing for HA configuration
  - `py3-beautifulsoup4` - HTML/XML parsing
- **Additional system tools**: More utilities available out-of-the-box
  - `vim` - Advanced text editor
  - `wget` - File download utility
  - `tree` - Directory tree visualization
  - `yq` - YAML processor (essential for Home Assistant configs)

### 📚 Documentation
- **Community Tools section**: Added links to community-built tools in README
  - Featured: `ha-ws-client-go` by @schoolboyqueue for WebSocket API access

### 🔗 PR Attribution
- Incorporates contributions from PR #1 (adapted to current codebase)

## 2.0.2

### 🐛 Bug Fix - Claude CLI Launch Failure
- **Fixed session picker dropping to Node.js REPL**: Claude Code CLI now launches correctly
  - **Root cause**: Scripts incorrectly used `node "$(which claude)"` which passes the claude binary path to Node.js as if it were a JS file to execute
  - **Symptom**: Selecting "New interactive session" showed `Welcome to Node.js v20.15.1` and `>` prompt instead of launching Claude
  - **Solution**: Changed all invocations to use `exec claude $flags` directly, since `claude` is already a properly wrapped executable
  - **Affected scripts**: `claude-session-picker.sh`, `claude-auth-helper.sh`
  - **Result**: All session picker options now correctly launch Claude Code CLI

## 2.0.1

### 🐛 Bug Fix - Build Error
- **Removed unpublished plugin from Dockerfile**: Fixed Docker build failure
  - Plugin `@ESJavadex/claude-homeassistant-plugins` not yet in registry
  - Plugins now recommended for manual installation
  - Build process works correctly again

## 2.0.0

### 🎉 Major Release - Enhanced Developer Experience

### ✨ New Features

- **Git Pre-installed**: Git version control included in base Docker image
  - No need to use `persist-install git` anymore
  - Available immediately on fresh installs
  - Enables version control workflows within the terminal

### 📦 Recommended Plugins

For an enhanced experience, manually install the Claude Home Assistant Plugins:

```bash
npx claude-plugins install @ESJavadex/claude-homeassistant-plugins/homeassistant-config
```

See [claude-homeassistant-plugins](https://github.com/ESJavadex/claude-homeassistant-plugins) for details.

## 1.7.1

### ✨ Improvement - Auto-Copy & Focus for Image Uploads
- **Streamlined image workflow**: Path automatically copied and terminal focused after upload
  - **Auto-copy to clipboard**: File path instantly copied when image uploaded
  - **Auto-focus terminal**: Terminal iframe automatically focused and ready
  - **Auto-paste attempt**: Tries to paste path directly (may be blocked by browser security)
  - **Clear status**: Shows "Ready to use! (path in clipboard)"
  - **Workflow**: Upload image → Press Cmd+V → Done!
  - **Fallback**: If auto-paste blocked, just press Cmd+V (clipboard already has path)

**How it works now**:
1. Paste/drag/upload an image
2. Path is automatically copied to clipboard
3. Terminal is automatically focused
4. Just press Cmd+V to paste the path
5. Ask Claude to analyze it!

This makes the image workflow nearly seamless - you don't need to click anything after uploading!

## 1.7.0

### ✨ New Feature - Voice Input with Web Speech API
- **Talk to Claude instead of typing**: Built-in speech-to-text using Chrome's Web Speech API
  - **Press-to-talk button**: Click 🎤 Voice Input button in header
  - **Real-time transcription**: See your speech converted to text as you speak
  - **Continuous recording**: Keeps listening until you stop
  - **Editable transcript**: Edit the transcribed text before copying
  - **Copy to clipboard**: One-click copy to paste into Claude Terminal
  - **Keyboard shortcuts**:
    - `Space` - Start/stop recording
    - `Enter` - Copy transcript
    - `Escape` - Close modal
  - **Error handling**: Clear messages for microphone issues, permissions, etc.
  - **No external services**: Uses browser's built-in speech recognition (Chrome, Edge, Safari)
  - **Perfect for**: Long questions, complex queries, hands-free operation

- **How to use**:
  1. Click 🎤 Voice Input button
  2. Click "Start Recording" and speak
  3. Click "Stop Recording" when done
  4. Edit text if needed
  5. Click "Copy Text"
  6. Paste into Claude Terminal!

**Browser support**: Chrome, Edge, Safari (requires microphone permissions)

## 1.6.6

### 🐛 Bug Fix - Clipboard API in Home Assistant Ingress
- **Fixed clipboard copy in iframe context**: Added fallback methods for copying file path
  - **Root cause**: `navigator.clipboard` API is blocked in Home Assistant ingress iframes
  - **Error**: "Cannot read properties of undefined (reading 'writeText')"
  - **Solution**: Multi-tier fallback approach:
    1. Try modern Clipboard API if available
    2. Fallback to `document.execCommand('copy')` with text selection
    3. Final fallback: Select text for manual Cmd+C copy
  - **User feedback**: Shows "✓ Copied!" or "✓ Selected! Press Cmd+C to copy"
  - **Result**: Path copying now works in all contexts (direct access, ingress, iframes)

**Technical note**: Browser security restrictions prevent clipboard access in cross-origin iframes. The new implementation uses progressive enhancement to provide the best experience available in each context.

## 1.6.5

### ✨ UX Improvement - Better Path Visibility for Manual Copy
- **Enhanced upload status display**: Full file path now shown prominently with click-to-copy functionality
  - **Previous**: Only showed filename ("Uploaded: pasted-123.png")
  - **Now**: Shows full path with icon ("📋 /data/images/pasted-123.png (click to copy)")
  - **Persistent display**: Path remains visible until next upload (no auto-hide)
  - **Click-to-copy**: Click the status text to copy path to clipboard
  - **Visual feedback**: Shows "✓ Copied to clipboard!" confirmation
  - **Fallback**: If clipboard API fails, shows error and allows manual selection
  - **User-friendly**: Hover effect and cursor pointer indicate clickability

This improvement addresses the issue where users couldn't easily see or copy the full file path to manually paste into Claude Code CLI.

## 1.6.4

### 🐛 Critical Fix - Home Assistant Ingress Compatibility
- **Fixed 404 errors and config loading failures**: Changed all paths to relative for ingress compatibility
  - **Root cause**: Absolute paths (`/config`, `/terminal/`, `/upload`) don't work with Home Assistant ingress
  - **Impact**: All API endpoints returned 404, terminal wouldn't load, uploads failed
  - **Solution**: Changed to relative paths (`config`, `terminal/`, `upload`)
  - **Why**: Home Assistant ingress adds path prefix `/api/hassio_ingress/TOKEN/` to all requests
  - **Result**: All features now work correctly through Home Assistant ingress

**Technical note**: This is a common Home Assistant add-on issue. When using ingress, all fetch calls and iframe sources must use relative paths (without leading `/`) to work correctly with the ingress path prefix.

## 1.6.3

### 🐛 Bug Fix - Image Service Startup Logging
- **Improved error visibility**: Node.js console output now shown directly in add-on logs
  - **Previous issue**: Errors were hidden in /var/log/image-service.log
  - **Solution**: Pipe Node.js stdout/stderr directly to add-on logs with `[Image Service]` prefix
  - **Added checks**: Verify server.js and node_modules exist before starting
  - **Auto-recovery**: Attempt `npm install` if node_modules is missing
  - **Result**: All startup errors now visible in `ha addons logs`

This will help diagnose why the image service isn't starting properly.

## 1.6.2

### 🐛 Critical Bug Fix - Express Route Order
- **Fixed 404 errors on API endpoints**: API routes now registered before static file middleware
  - **Root cause**: Static file middleware was placed before API routes in Express app
  - **Impact**: `/config` returned HTML instead of JSON, `/terminal` returned 404
  - **Solution**: Moved all API routes (/health, /config, /upload, /terminal) before static middleware
  - **Result**: All endpoints now work correctly

This is a common Express.js gotcha - middleware order matters! Static file middleware should come AFTER API routes to prevent it from intercepting API requests.

## 1.6.1

### 🐛 Bug Fixes - Image Paste Service
- **Fixed upload JSON parse errors**: Server now returns proper JSON error responses instead of HTML
  - **Root cause**: Multer errors were not caught, Express returned default HTML error pages
  - **Solution**: Added Multer-specific error handling middleware
  - **Impact**: Upload errors now show clear, actionable messages

- **Fixed terminal not loading through Home Assistant ingress**: Terminal now loads via proxy endpoint
  - **Root cause**: iframe tried to access ttyd on port 7681 directly, incompatible with ingress
  - **Solution**: Added http-proxy-middleware with WebSocket support, created /terminal/ proxy endpoint
  - **Impact**: Terminal works correctly through Home Assistant ingress

- **Improved paste event detection**: Better debugging and compatibility
  - Added detailed console logging for troubleshooting
  - Added window-level paste handler as fallback
  - Enhanced error handling in upload function

### 📦 Dependencies
- Added `http-proxy-middleware@^2.0.6` for WebSocket-capable terminal proxying

## 1.6.0

### ✨ New Feature - Image Paste Support
- **Paste images directly in the terminal**: Upload images via paste (Ctrl+V), drag-drop, or upload button
  - **Lightweight Node.js service**: ~10MB RAM overhead, ARM-compatible for Raspberry Pi
  - **Multiple upload methods**: Clipboard paste, drag-and-drop, or button click
  - **Persistent storage**: Images saved to `/data/images/` (survives restarts)
  - **Claude integration**: Use uploaded images with Claude Code CLI for analysis, OCR, etc.
  - **File formats**: Supports JPEG, PNG, GIF, WebP, SVG (10MB limit)

- **Architecture changes**:
  - New image upload service on port 7680 (Express + Multer)
  - Custom HTML interface embeds ttyd terminal (port 7681)
  - Home Assistant ingress now points to port 7680
  - Both services run concurrently in the container

- **User experience**:
  - Copy image → Paste in terminal → Automatic upload
  - File path shown in status bar: `/data/images/pasted-<timestamp>.png`
  - Use with Claude: `analyze /data/images/pasted-123.png`

### 📚 Documentation
- Added `IMAGE_PASTE.md` with complete feature documentation
- Updated CLAUDE.md with image paste development notes
- Documented troubleshooting and browser compatibility

### 🔧 Technical Details
- Dependencies: Express (4.18.2), Multer (1.4.5-lts.1)
- Security: MIME type validation, 10MB size limit, isolated storage
- Performance: Minimal CPU usage, only active during uploads
- Compatibility: All supported architectures (amd64, aarch64, armv7)

## 1.5.2

### 🐛 Critical Bug Fix - Persistent Packages PATH
- **Fixed persistent packages not available in terminal**: Packages installed via `persist-install` are now correctly available in all bash sessions
  - **Root cause**: Environment variables (PATH, LD_LIBRARY_PATH) were only set in parent run.sh process
  - **Solution**: Created `/etc/profile.d/persistent-packages.sh` which is auto-sourced by all bash shells
  - **Impact**: `python3`, `ha`, and other installed packages now work immediately after installation
  - **Affected versions**: 1.4.0 - 1.5.1 (packages were installed correctly but not in PATH)

- **Technical details**:
  - ttyd spawns bash sessions that don't inherit parent process environment variables
  - Standard Linux solution: Use `/etc/profile.d/` for system-wide environment configuration
  - Profile script sets HOME, XDG variables, and persistent package paths for all sessions
  - No changes needed to existing installations - automatic on container restart

### 📚 Documentation Updates
- Added troubleshooting section for PATH issues in CLAUDE.md
- Documented the fix and migration path from older versions
- Updated development notes with container testing workflow

## 1.5.1

### 🐛 Bug Fixes
- Improved Home Assistant CLI installation verification
- Enhanced error handling for ha command checks

## 1.5.0

### ✨ New Features
- **Official Home Assistant CLI support**: Install with `persist-install --ha-cli`
  - Auto-detects architecture (amd64, aarch64, armv7, armhf, i386)
  - Downloads binary from official GitHub releases
  - Provides full access to Home Assistant management commands
  - Alternative to Supervisor REST API for programmatic access

## 1.4.0

### ✨ New Features - Persistent Package System
- **`persist-install` command**: Install packages that survive container restarts!
  - Simple syntax: `persist-install python3 git vim`
  - Python packages: `persist-install --python homeassistant-cli requests`
  - List installed: `persist-install --list`
  - Packages stored in `/data/packages` (persistent Home Assistant storage)
  - No need to rebuild Docker image for new tools

- **Auto-install packages on startup**: Configure packages in add-on settings
  - `persistent_apk_packages`: System packages (git, vim, htop, etc.)
  - `persistent_pip_packages`: Python packages (homeassistant-cli, requests, etc.)
  - Automatically installed on every container startup
  - Perfect for your essential toolkit

- **Python virtual environment**: Persistent Python environment
  - Located at `/data/packages/python/venv`
  - Automatically activated when packages are installed
  - Survives reboots and container recreations

### 🏗️ Architecture Improvements
- **Scalable package management**: No longer requires Dockerfile modifications
  - Add packages via terminal command or config
  - Instant package installation without rebuilding
  - Reduced image size (only core tools in image)
  - User-specific package installations

- **Smart PATH management**: Persistent binaries take priority
  - `/data/packages/bin` added to PATH
  - Python venv automatically activated
  - Library paths configured for compiled packages

### 📚 Documentation
- **Container architecture explained**: Comprehensive guide to persistence
  - Why runtime installations (apk add) disappear
  - Difference between image layers and volume layers
  - How persistent storage solves the problem
  - Migration from Dockerfile-based approach to persistent storage

## 1.3.2

### 🐛 Bug Fixes
- **Improved installation reliability** (#16): Enhanced resilience for network issues during installation
  - Added retry logic (3 attempts) for npm package installation
  - Configured npm with longer timeouts for slow/unstable connections
  - Explicitly set npm registry to avoid DNS resolution issues
  - Added 10-second delay between retry attempts

### 🛠️ Improvements
- **Enhanced network diagnostics**: Better troubleshooting for connection issues
  - Added DNS resolution checks to identify network configuration problems
  - Check connectivity to GitHub Container Registry (ghcr.io)
  - Extended connection timeouts for virtualized environments
  - More detailed error messages with specific solutions
- **Better virtualization support**: Improved guidance for VirtualBox and Proxmox users
  - Enhanced VirtualBox detection with detailed configuration requirements
  - Added Proxmox/QEMU environment detection
  - Specific network adapter recommendations for VM installations
  - Clear guidance on minimum resource requirements (2GB RAM, 8GB disk)

## 1.3.1

### 🐛 Critical Fix
- **Restored config directory access**: Fixed regression where add-on couldn't access Home Assistant configuration files
  - Re-added `config:rw` volume mapping that was accidentally removed in 1.2.0
  - Users can now properly access and edit their configuration files again

## 1.3.0

### ✨ New Features
- **Full Home Assistant API Access**: Enabled complete API access for automations and entity control
  - Added `hassio_api`, `homeassistant_api`, and `auth_api` permissions
  - Set `hassio_role` to 'manager' for full Supervisor access
  - Created comprehensive API examples script (`ha-api-examples.sh`)
  - Includes Supervisor API, Core API, and WebSocket examples
  - Python and bash code examples for entity control

### 🐛 Bug Fixes
- **Fixed authentication paste issues** (#14): Added authentication helper for clipboard problems
  - New authentication helper script with multiple input methods
  - Manual code entry option when clipboard paste fails
  - File-based authentication via `/config/auth-code.txt`
  - Integrated into session picker as menu option

### 🛠️ Improvements
- **Enhanced diagnostics** (#16): Added comprehensive health check system
  - System resource monitoring (memory, disk space)
  - Permission and dependency validation
  - VirtualBox-specific troubleshooting guidance
  - Automatic health check on startup
  - Improved error handling with strict mode

## 1.2.1

### 🔧 Internal Changes
- Fixed YAML formatting issues for better compatibility
- Added document start marker and fixed line lengths

## 1.2.0

### 🔒 Authentication Persistence Fix (PR #15)
- **Fixed OAuth token persistence**: Tokens now survive container restarts
  - Switched from `/config` to `/data` directory (Home Assistant best practice)
  - Implemented XDG Base Directory specification compliance
  - Added automatic migration for existing authentication files
  - Removed complex symlink/monitoring systems for simplicity
  - Maintains full backward compatibility

## 1.1.4

### 🧹 Maintenance
- **Cleaned up repository**: Removed erroneously committed test files (thanks @lox!)
- **Improved codebase hygiene**: Cleared unnecessary temporary and test configuration files

## 1.1.3

### 🐛 Bug Fixes
- **Fixed session picker input capture**: Resolved issue with ttyd intercepting stdin, preventing proper user input
- **Improved terminal interaction**: Session picker now correctly captures user choices in web terminal environment

## 1.1.2

### 🐛 Bug Fixes
- **Fixed session picker input handling**: Improved compatibility with ttyd web terminal environment
- **Enhanced input processing**: Better handling of user input with whitespace trimming
- **Improved error messages**: Added debugging output showing actual invalid input values
- **Better terminal compatibility**: Replaced `echo -n` with `printf` for web terminals

## 1.1.1

### 🐛 Bug Fixes  
- **Fixed session picker not found**: Moved scripts from `/config/scripts/` to `/opt/scripts/` to avoid volume mapping conflicts
- **Fixed authentication persistence**: Improved credential directory setup with proper symlink recreation
- **Enhanced credential management**: Added proper file permissions (600) and logging for debugging
- **Resolved volume mapping issues**: Scripts now persist correctly without being overwritten

## 1.1.0

### ✨ New Features
- **Interactive Session Picker**: New menu-driven interface for choosing Claude session types
  - 🆕 New interactive session (default)
  - ⏩ Continue most recent conversation (-c)
  - 📋 Resume from conversation list (-r) 
  - ⚙️ Custom Claude command with manual flags
  - 🐚 Drop to bash shell
  - ❌ Exit option
- **Configurable auto-launch**: New `auto_launch_claude` setting (default: true for backward compatibility)
- **Added nano text editor**: Enables `/memory` functionality and general text editing

### 🛠️ Architecture Changes
- **Simplified credential management**: Removed complex modular credential system
- **Streamlined startup process**: Eliminated problematic background services
- **Cleaner configuration**: Reduced complexity while maintaining functionality
- **Improved reliability**: Removed sources of startup failures from missing script dependencies

### 🔧 Improvements
- **Better startup logging**: More informative messages about configuration and setup
- **Enhanced backward compatibility**: Existing users see no change in behavior by default
- **Improved error handling**: Better fallback behavior when optional components are missing

## 1.0.2

### 🔒 Security Fixes
- **CRITICAL**: Fixed dangerous filesystem operations that could delete system files
- Limited credential searches to safe directories only (`/root`, `/home`, `/tmp`, `/config`)
- Replaced unsafe `find /` commands with targeted directory searches
- Added proper exclusions and safety checks in cleanup scripts

### 🐛 Bug Fixes
- **Fixed architecture mismatch**: Added missing `armv7` support to match build configuration
- **Fixed NPM package installation**: Pinned Claude Code package version for reliable builds
- **Fixed permission conflicts**: Standardized credential file permissions (600) across all scripts
- **Fixed race conditions**: Added proper startup delays for credential management service
- **Fixed script fallbacks**: Implemented embedded scripts when modules aren't found

### 🛠️ Improvements
- Added comprehensive error handling for all critical operations
- Improved build reliability with better package management
- Enhanced credential management with consistent permission handling
- Added proper validation for script copying and execution
- Improved startup logging for better debugging

### 🧪 Development
- Updated development environment to use Podman instead of Docker
- Added proper build arguments for local testing
- Created comprehensive testing framework with Nix development shell
- Added container policy configuration for rootless operation

## 1.0.0

- First stable release of Claude Terminal add-on:
  - Web-based terminal interface using ttyd
  - Pre-installed Claude Code CLI
  - User-friendly interface with clean welcome message
  - Simple claude-logout command for authentication
  - Direct access to Home Assistant configuration
  - OAuth authentication with Anthropic account
  - Auto-launches Claude in interactive mode