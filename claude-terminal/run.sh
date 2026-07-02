#!/usr/bin/with-contenv bashio

# Enable strict error handling
set -e
set -o pipefail

# Initialize environment for Claude Code CLI using /data (HA best practice)
init_environment() {
    # Use /data exclusively - guaranteed writable by HA Supervisor
    local data_home="/data/home"
    local config_dir="/data/.config"
    local cache_dir="/data/.cache"
    local state_dir="/data/.local/state"
    local claude_config_dir="/data/.config/claude"
    local gh_config_dir="/data/.config/gh"
    local persist_root="/data/packages"
    local persist_bin="$persist_root/bin"
    local persist_lib="$persist_root/lib"
    local persist_python="$persist_root/python"

    bashio::log.info "Initializing Claude Code environment in /data..."

    # Create all required directories
    if ! mkdir -p "$data_home" "$config_dir/claude" "$config_dir/gh" "$cache_dir" "$state_dir" "/data/.local" \
                  "$persist_bin" "$persist_lib" "$persist_python"; then
        bashio::log.error "Failed to create directories in /data"
        exit 1
    fi

    # Set permissions
    chmod 755 "$data_home" "$config_dir" "$cache_dir" "$state_dir" "$claude_config_dir" "$gh_config_dir" \
              "$persist_root" "$persist_bin" "$persist_lib" "$persist_python"

    # Ensure Claude native binary is available at $HOME/.local/bin/claude.
    # The native installer places it at /root/.local/bin/claude during Docker build,
    # but at runtime HOME=/data/home, so Claude's self-check looks in /data/home/.local/bin/.
    #
    # ALWAYS re-point this launcher at the image's baked binary. If someone runs
    # `claude update`, the native updater drops a new build into XDG_DATA_HOME
    # (/data/.local/share, persistent) and repoints this launcher at it — which
    # both drifts from the add-on's pinned version and, on an old base, bricked
    # launch with `statx: symbol not found`. Forcing the link each boot makes the
    # baked version authoritative: any such drift is reset on the next restart.
    local native_bin_dir="$data_home/.local/bin"
    mkdir -p "$native_bin_dir"
    if [ -f /root/.local/bin/claude ]; then
        ln -sfn /root/.local/bin/claude "$native_bin_dir/claude"
        bashio::log.info "  - Claude native binary linked (baked image version): $native_bin_dir/claude"
    fi

    # Set XDG and application environment variables
    export HOME="$data_home"
    export XDG_CONFIG_HOME="$config_dir"
    export XDG_CACHE_HOME="$cache_dir"
    export XDG_STATE_HOME="$state_dir"
    export XDG_DATA_HOME="/data/.local/share"

    # Claude-specific environment variables
    export ANTHROPIC_CONFIG_DIR="$claude_config_dir"
    export ANTHROPIC_HOME="/data"

    # Disable auto-updates: binary is baked into the container image,
    # updates are delivered via add-on releases, not CLI self-update
    export DISABLE_AUTOUPDATER=1

    # GitHub CLI persistent configuration
    export GH_CONFIG_DIR="$gh_config_dir"

    # Get dangerously-skip-permissions configuration
    local dangerously_skip_permissions
    dangerously_skip_permissions=$(bashio::config 'dangerously_skip_permissions' 'false')
    export CLAUDE_DANGEROUS_MODE="$dangerously_skip_permissions"

    # Set IS_SANDBOX=1 to allow --dangerously-skip-permissions when running as root
    if [ "$dangerously_skip_permissions" = "true" ]; then
        export IS_SANDBOX=1
    fi

    # PATH ordering — deliberately SYSTEM-FIRST for run.sh's own boot logic.
    # `/data/packages` is writable and persistent, so it's exactly where a
    # compromised session would drop a binary to survive a reboot. run.sh runs as
    # root and its bashio helpers shell out to `jq`/`curl` by name, so the boot
    # context must resolve trusted baked binaries, not anything planted in /data.
    # Appending (not prepending) the persist dirs keeps persist-ONLY tools (e.g. a
    # user-installed `git`) reachable while preventing a persisted binary from
    # shadowing a baked one at boot. The interactive terminal gets persist-FIRST
    # separately, right before `exec ttyd` (see start_web_terminal), and sub-shells
    # get it via /etc/profile.d below — so the persistence feature is unaffected.
    export PATH="$PATH:$persist_bin:$persist_python/venv/bin:$data_home/.local/bin"
    # Do NOT put /data/packages/lib on run.sh's own LD_LIBRARY_PATH: the loader
    # always searches LD_LIBRARY_PATH ahead of the system default paths, so the only
    # way to keep boot-time root processes (and the image service spawned below) off
    # the writable lib dir is to omit it here. The terminal session re-adds it before
    # `exec ttyd`.
    export PKG_CONFIG_PATH="$persist_lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Python virtual environment if it exists
    if [ -d "$persist_python/venv" ]; then
        export VIRTUAL_ENV="$persist_python/venv"
        bashio::log.info "  - Python venv: active"
    fi

    # Create profile script for persistent environment variables
    # This ensures ALL bash sessions (including ttyd shells) have correct PATH
    cat > /etc/profile.d/persistent-packages.sh << 'PROFILE_EOF'
# Persistent package environment - auto-loaded for all bash sessions
export HOME="/data/home"
export XDG_CONFIG_HOME="/data/.config"
export XDG_CACHE_HOME="/data/.cache"
export XDG_STATE_HOME="/data/.local/state"
export XDG_DATA_HOME="/data/.local/share"
export ANTHROPIC_CONFIG_DIR="/data/.config/claude"
export ANTHROPIC_HOME="/data"

# Disable auto-updates inside container (updates via add-on releases)
export DISABLE_AUTOUPDATER=1

# GitHub CLI persistent configuration
export GH_CONFIG_DIR="/data/.config/gh"

# Persistent package paths and native Claude binary (HIGHEST PRIORITY)
export PATH="/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin:$PATH"
export LD_LIBRARY_PATH="/data/packages/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="/data/packages/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Python virtual environment if it exists
if [ -d "/data/packages/python/venv" ]; then
    export VIRTUAL_ENV="/data/packages/python/venv"
fi
PROFILE_EOF

    chmod 644 /etc/profile.d/persistent-packages.sh
    bashio::log.info "  - Profile script created: /etc/profile.d/persistent-packages.sh"

    # Migrate any existing authentication files from legacy locations
    migrate_legacy_auth_files "$claude_config_dir"

    # Setup Claude Code skills and commands
    if [ -d "/opt/.claude" ]; then
        if [ ! -d "$data_home/.claude" ]; then
            cp -r /opt/.claude "$data_home/.claude"
            bashio::log.info "  - Claude Code skills & commands installed"
        else
            bashio::log.info "  - Claude Code skills & commands: already configured"
        fi
    fi

    # Link the harness memory dir to git-tracked /config/.claude/memory.
    # HOME=/data/home is per-add-on, so a fresh /data has no memory symlink and
    # Claude Code silently recalls into a new empty dir. The memories themselves
    # live in /config (mounted, git-tracked) and survive; only the symlink needs
    # recreating. Project dir for cwd /config is sanitised to "-config".
    if [ -d "/config/.claude/memory" ]; then
        local mem_project_dir="$data_home/.claude/projects/-config"
        mkdir -p "$mem_project_dir"
        ln -sfn /config/.claude/memory "$mem_project_dir/memory"
        bashio::log.info "  - Harness memory linked: $mem_project_dir/memory -> /config/.claude/memory"
    fi

    bashio::log.info "Environment initialized:"
    bashio::log.info "  - Home: $HOME"
    bashio::log.info "  - Config: $XDG_CONFIG_HOME"
    bashio::log.info "  - Claude config: $ANTHROPIC_CONFIG_DIR"
    bashio::log.info "  - GitHub config: $GH_CONFIG_DIR"
    bashio::log.info "  - Cache: $XDG_CACHE_HOME"
    bashio::log.info "  - Persistent packages: $persist_root"
}

# One-time migration of existing authentication files
migrate_legacy_auth_files() {
    local target_dir="$1"
    local migrated=false

    bashio::log.info "Checking for existing authentication files to migrate..."

    # Check common legacy locations. Only trusted, image-internal paths are
    # migrated. The old `/config/claude-config` and `/tmp/claude-config` sources
    # were deliberately dropped: both are writable from outside this add-on
    # (/config is mapped rw and user-synced; /tmp is world-writable), so anything
    # placed there could be seeded by another party and would then be copied
    # verbatim into Claude's credential directory. Migrating only from /root keeps
    # this one-time import to files this image itself wrote.
    local legacy_locations=(
        "/root/.config/anthropic"
        "/root/.anthropic"
    )

    for legacy_path in "${legacy_locations[@]}"; do
        if [ -d "$legacy_path" ] && [ "$(ls -A "$legacy_path" 2>/dev/null)" ]; then
            bashio::log.info "Migrating auth files from: $legacy_path"
            
            # Copy files to new location
            if cp -r "$legacy_path"/* "$target_dir/" 2>/dev/null; then
                # Set proper permissions
                find "$target_dir" -type f -exec chmod 600 {} \;
                
                # Create compatibility symlink if this is a standard location
                if [[ "$legacy_path" == "/root/.config/anthropic" ]] || [[ "$legacy_path" == "/root/.anthropic" ]]; then
                    rm -rf "$legacy_path"
                    ln -sf "$target_dir" "$legacy_path"
                    bashio::log.info "Created compatibility symlink: $legacy_path -> $target_dir"
                fi
                
                migrated=true
                bashio::log.info "Migration completed from: $legacy_path"
            else
                bashio::log.warning "Failed to migrate from: $legacy_path"
            fi
        fi
    done

    if [ "$migrated" = false ]; then
        bashio::log.info "No existing authentication files found to migrate"
    fi
}

# Verify required tools. ttyd/jq/curl are baked into the image, so this is a
# no-op on a healthy build; only fall back to apk (network-dependent) if the
# terminal binary is somehow missing, instead of apk-ing on every boot.
install_tools() {
    if command -v ttyd >/dev/null 2>&1; then
        bashio::log.info "Required tools present (baked into image)"
        return 0
    fi
    bashio::log.warning "ttyd not found in image; installing at runtime..."
    if ! apk add --no-cache ttyd jq curl; then
        bashio::log.error "Failed to install required tools"
        exit 1
    fi
}

# (Removed setup_persistent_claude: it checked an obsolete
#  .../claude-code/cli.js path that current native installs no longer ship, so
#  it always warned and silently fell back, while npm-installing @latest into
#  /data/npm fought the baked-binary model. Claude is now baked at a pinned
#  CLAUDE_VERSION and the launcher is force-linked to it in init_environment.)

# Setup session picker script
setup_session_picker() {
    # Copy session picker script from built-in location
    if [ -f "/opt/scripts/claude-session-picker.sh" ]; then
        if ! cp /opt/scripts/claude-session-picker.sh /usr/local/bin/claude-session-picker; then
            bashio::log.error "Failed to copy claude-session-picker script"
            exit 1
        fi
        chmod +x /usr/local/bin/claude-session-picker
        bashio::log.info "Session picker script installed successfully"
    else
        bashio::log.warning "Session picker script not found, using auto-launch mode only"
    fi

    # Setup authentication helper if it exists
    if [ -f "/opt/scripts/claude-auth-helper.sh" ]; then
        chmod +x /opt/scripts/claude-auth-helper.sh
        bashio::log.info "Authentication helper script ready"
    fi
}

# Setup persistent package manager
setup_persistent_packages() {
    # Install persist-install command globally
    if [ -f "/opt/scripts/persist-install" ]; then
        cp /opt/scripts/persist-install /usr/local/bin/persist-install
        chmod +x /usr/local/bin/persist-install
        bashio::log.info "Persistent package manager installed: 'persist-install'"
    fi

    # Auto-install packages from configuration
    auto_install_packages
}

# Auto-install packages from add-on configuration
auto_install_packages() {
    # NOTE: bashio::config already expands a list option into newline-separated
    # raw values (it queries `.key[]` through `jq --raw-output`). Piping that
    # back through `jq -r '.[]'` double-parses it and aborts with
    # "jq: parse error: Invalid literal..." — so consume the lines directly.
    local apk_packages pip_packages
    apk_packages=$(bashio::config 'persistent_apk_packages')
    pip_packages=$(bashio::config 'persistent_pip_packages')

    # Check if any system (apk) packages are configured
    if [ -n "$apk_packages" ] && [ "$apk_packages" != "[]" ] && [ "$apk_packages" != "null" ]; then
        bashio::log.info "Auto-installing system packages from config..."
        while read -r pkg; do
            [ -n "$pkg" ] || continue
            # Reject anything that isn't a plain package name. This blocks a config
            # value that begins with `-` (which would be parsed as an apk flag, not a
            # package) and other argument-injection via the option list.
            if [[ ! "$pkg" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
                bashio::log.warning "  Skipping invalid apk package name: $pkg"
                continue
            fi
            bashio::log.info "  Installing: $pkg"
            /usr/local/bin/persist-install "$pkg" || bashio::log.warning "Failed to install: $pkg"
        done <<< "$apk_packages"
    fi

    # Check if any Python (pip) packages are configured
    if [ -n "$pip_packages" ] && [ "$pip_packages" != "[]" ] && [ "$pip_packages" != "null" ]; then
        bashio::log.info "Auto-installing Python packages from config..."

        # Validate each entry, then pass them as separate quoted arguments. The
        # regex allows pip version specifiers/extras (e.g. `pandas[all]`,
        # `requests==2.31.0`, `foo>=1,<2`) but still requires a leading alphanumeric,
        # so a `--flag`-style entry can't be smuggled in as a pip option.
        local -a pip_pkgs=()
        local pkg
        while read -r pkg; do
            [ -n "$pkg" ] || continue
            if [[ ! "$pkg" =~ ^[A-Za-z0-9][A-Za-z0-9._+=!~,\<\>\[\]-]*$ ]]; then
                bashio::log.warning "  Skipping invalid pip package spec: $pkg"
                continue
            fi
            pip_pkgs+=("$pkg")
        done <<< "$pip_packages"

        if [ "${#pip_pkgs[@]}" -gt 0 ]; then
            bashio::log.info "  Installing: ${pip_pkgs[*]}"
            /usr/local/bin/persist-install --python "${pip_pkgs[@]}" || bashio::log.warning "Failed to install Python packages"
        fi
    fi
}

# Auto-wire Claude Code to the ha-mcp (Home Assistant MCP) server.
#
# ha-mcp (homeassistant-ai/ha-mcp) is a SEPARATE add-on holding its own
# `hassio_role: manager` token; it exposes streamable-HTTP on :9583 at a secret
# path that IS the credential (no token needed from us). We only need its URL,
# which the user pastes into `home_assistant_mcp_url` (copied from ha-mcp's log) —
# we can't auto-discover it because reading another add-on's options needs the
# `manager` Supervisor scope this add-on deliberately dropped in 4.4.0.
#
# Hard rules (see plan / config.yaml comment):
#   - EMPTY url or disabled  => pure no-op: touch no Claude config at all, so an
#     existing manual wiring is left byte-for-byte intact.
#   - Dedup by URL host:port, not name: if any *other-named* server already targets
#     this host:port, leave it alone (don't create a duplicate connection).
#   - Never block boot (non-fatal, timeout-guarded) and never log the secret URL.
setup_ha_mcp() {
    local enabled url config stripped hostport existing other our_url to=""

    enabled=$(bashio::config 'enable_home_assistant_mcp' 'true')
    url=$(bashio::config 'home_assistant_mcp_url' '')

    # Trim surrounding whitespace (incl. a stray CR/space from a copy-paste) — an
    # untrimmed URL would silently break the connection or the host:port match.
    url="${url#"${url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"

    # Opt-out or not configured -> do absolutely nothing.
    if [ "$enabled" != "true" ]; then
        bashio::log.info "Home Assistant MCP auto-wiring disabled (enable_home_assistant_mcp=false)"
        return 0
    fi
    if [ -z "$url" ] || [ "$url" = "null" ]; then
        bashio::log.info "Home Assistant MCP: no URL set; skipping auto-wire."
        bashio::log.info "  To connect, install the ha-mcp add-on and paste the URL from its log"
        bashio::log.info "  into the 'home_assistant_mcp_url' option."
        return 0
    fi
    case "$url" in
        http://*|https://*) : ;;
        *)
            bashio::log.warning "home_assistant_mcp_url is not an http(s) URL; skipping ha-mcp auto-wire."
            return 0
            ;;
    esac
    if ! command -v claude >/dev/null 2>&1; then
        bashio::log.warning "claude binary not found; skipping ha-mcp auto-wire."
        return 0
    fi

    # host:port of the configured URL (scheme stripped, path stripped)
    stripped=${url#*://}
    hostport=${stripped%%/*}
    # Guard an empty host (e.g. "https://" or "http:///path"): an empty needle makes
    # awk's index() match every server, which would spuriously skip wiring.
    if [ -z "$hostport" ]; then
        bashio::log.warning "home_assistant_mcp_url has no host; skipping ha-mcp auto-wire."
        return 0
    fi

    # Inspect existing config without health-checking (jq, no network, no hang).
    # User-scope servers live at .mcpServers; project/local at .projects[].mcpServers.
    config="$HOME/.claude.json"
    if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
        existing=$(jq -r '
            ((.mcpServers // {}) | to_entries[]),
            ((.projects // {}) | to_entries[] | (.value.mcpServers // {}) | to_entries[])
            | "\(.key)\t\(.value.url // "")"
        ' "$config" 2>/dev/null || true)

        # An existing server under a DIFFERENT name already points here -> the user
        # wired it themselves; never duplicate it.
        other=$(printf '%s\n' "$existing" \
            | awk -F'\t' -v hp="$hostport" '$1 != "ha-mcp" && $2 != "" && index($2, hp) {print $1; exit}')
        if [ -n "$other" ]; then
            bashio::log.info "Home Assistant MCP: existing connection '${other}' already targets this server; leaving it untouched."
            return 0
        fi

        # Our own entry already correct -> nothing to do.
        our_url=$(jq -r '.mcpServers."ha-mcp".url // empty' "$config" 2>/dev/null || true)
        if [ "$our_url" = "$url" ]; then
            bashio::log.info "Home Assistant MCP: 'ha-mcp' already wired."
            return 0
        fi
    fi

    # (Re)register our managed entry at user scope. Use `add --transport http` (URL as
    # a positional arg) rather than hand-built add-json, so a URL with special chars
    # can't malform the JSON. timeout-guarded if available; always non-fatal. Output
    # is sent to /dev/null — `add` echoes the URL, which is a credential we never log.
    # NB: use an if-block, not `cmd && to=...`, so a missing `timeout` can't make
    # the line return non-zero and trip `set -e` (would abort boot).
    if command -v timeout >/dev/null 2>&1; then
        to="timeout 15"
    fi
    $to claude mcp remove ha-mcp --scope user >/dev/null 2>&1 || true
    if $to claude mcp add --transport http --scope user ha-mcp "$url" >/dev/null 2>&1; then
        bashio::log.info "Home Assistant MCP: 'ha-mcp' wired (user scope)."
    else
        bashio::log.warning "Home Assistant MCP: registration failed; continuing without it."
    fi
}

# Seed an add-on-owned onboarding hint into the USER-level Claude memory
# ($HOME/.claude/CLAUDE.md). Claude Code reads this as user memory and MERGES it
# with the project's /config/CLAUDE.md without overriding — so we orient Claude to
# this HA environment WITHOUT ever reading or writing the user's /config files.
#
# We manage ONLY a marker-delimited block, so any other content in the file (or the
# whole /config tree) is never touched. Idempotent: an identical block is left as-is.
setup_onboarding_hint() {
    local enabled file marker_start marker_end body desired current tmp
    enabled=$(bashio::config 'enable_onboarding_hint' 'true')
    file="$HOME/.claude/CLAUDE.md"
    marker_start="<!-- claude-code-ha:onboarding:start -->"
    marker_end="<!-- claude-code-ha:onboarding:end -->"

    mkdir -p "$HOME/.claude"

    # Body in a QUOTED heredoc (no shell expansion, backticks free); markers are
    # added from the variables so there is a single source of truth for them.
    body=$(cat <<'EOF'
# Claude Code for Home Assistant — environment notes

You are in the **Claude Code for Home Assistant** add-on: a browser terminal that
starts in `/config`, the Home Assistant configuration directory.

- **Prefer the Home Assistant MCP server for HA operations.** If a `home-assistant` /
  `ha-mcp` MCP server is connected, use its `ha_*` tools (entities, services,
  automations, scenes, dashboards, add-ons, backups) instead of raw shell or `curl`.
- **Use this shell for authoring and config**, not control: read and edit the YAML
  under `/config`, run `git`, and let the MCP handle live HA operations.
- This shell carries only a reduced `homeassistant` Supervisor token (not `manager`),
  so add-on / host / backup operations must go through the MCP server.
- Use `persist-install <pkg>` for packages that must survive restarts (plain
  `apk add` / `pip install` are lost when the container restarts).
EOF
)
    desired=$(printf '%s\n%s\n%s' "$marker_start" "$body" "$marker_end")

    # Disabled: remove only our well-formed block; leave any other content intact.
    if [ "$enabled" != "true" ]; then
        if [ -f "$file" ] && grep -qF "$marker_start" "$file" && grep -qF "$marker_end" "$file"; then
            tmp=$(mktemp)
            awk -v s="$marker_start" -v e="$marker_end" '
                index($0, s){drop=1}
                !drop{print}
                drop && index($0, e){drop=0; next}
            ' "$file" > "$tmp"
            if grep -q '[^[:space:]]' "$tmp"; then
                mv "$tmp" "$file"
            else
                rm -f "$tmp" "$file"
            fi
            bashio::log.info "Onboarding hint removed (enable_onboarding_hint=false)"
        fi
        return 0
    fi

    # Enabled, no file yet -> create with just our block.
    if [ ! -f "$file" ]; then
        printf '%s\n' "$desired" > "$file"
        bashio::log.info "Onboarding hint installed: $file"
        return 0
    fi

    # No managed block yet -> append after existing content.
    if ! grep -qF "$marker_start" "$file"; then
        printf '\n%s\n' "$desired" >> "$file"
        bashio::log.info "Onboarding hint added: $file"
        return 0
    fi

    # Start marker present but end marker missing -> malformed (user truncated it).
    # Do NOT strip to EOF; leave the file untouched to avoid deleting user content.
    if ! grep -qF "$marker_end" "$file"; then
        bashio::log.warning "Onboarding hint markers malformed in $file; leaving it untouched."
        return 0
    fi

    # Already current -> nothing to do (no per-boot churn).
    current=$(awk -v s="$marker_start" -v e="$marker_end" '
        index($0, s){keep=1}
        keep{print}
        keep && index($0, e){exit}
    ' "$file")
    if [ "$current" = "$desired" ]; then
        return 0
    fi

    # Stale block -> strip it (inclusive) and re-append the fresh one.
    tmp=$(mktemp)
    awk -v s="$marker_start" -v e="$marker_end" '
        index($0, s){drop=1}
        !drop{print}
        drop && index($0, e){drop=0; next}
    ' "$file" > "$tmp"
    if grep -q '[^[:space:]]' "$tmp"; then
        printf '\n%s\n' "$desired" >> "$tmp"
    else
        printf '%s\n' "$desired" > "$tmp"
    fi
    mv "$tmp" "$file"
    bashio::log.info "Onboarding hint updated: $file"
}

# Legacy monitoring functions removed - using simplified /data approach

# Determine Claude launch command based on configuration
# Session picker handles its own loop, so Claude exiting returns to the menu (#6)
get_claude_launch_command() {
    local auto_launch_claude
    local dangerously_skip_permissions
    local claude_flags=""

    # Get configuration values
    auto_launch_claude=$(bashio::config 'auto_launch_claude' 'true')
    dangerously_skip_permissions=$(bashio::config 'dangerously_skip_permissions' 'false')

    # Build Claude flags
    if [ "$dangerously_skip_permissions" = "true" ]; then
        claude_flags="--dangerously-skip-permissions"
        bashio::log.warning "Claude will run with --dangerously-skip-permissions (unrestricted file access)"
    fi

    if [ "$auto_launch_claude" = "true" ]; then
        # Auto-launch Claude first, then fall back to session picker on exit
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && echo 'Welcome to Claude Code!' && echo '' && echo 'Starting Claude...' && sleep 1 && claude ${claude_flags}; /usr/local/bin/claude-session-picker"
        else
            echo "clear && echo 'Welcome to Claude Code!' && echo '' && echo 'Starting Claude...' && sleep 1 && claude ${claude_flags}"
        fi
    else
        # Show interactive session picker (has its own while-true loop)
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && /usr/local/bin/claude-session-picker"
        else
            bashio::log.warning "Session picker not found, falling back to auto-launch"
            echo "clear && echo 'Welcome to Claude Code!' && echo '' && echo 'Starting Claude...' && sleep 1 && claude"
        fi
    fi
}


# Start image upload service
start_image_service() {
    local image_port=7680
    local ttyd_port=7681
    local upload_dir="/data/images"
    local service_dir="/opt/image-service"
    local server_file="${service_dir}/server.js"

    bashio::log.info "Starting image upload service on port ${image_port}..."

    # Create upload directory if it doesn't exist
    mkdir -p "${upload_dir}"
    chmod 755 "${upload_dir}"

    # Export environment variables for the image service
    export IMAGE_SERVICE_PORT="${image_port}"
    export TTYD_PORT="${ttyd_port}"
    export UPLOAD_DIR="${upload_dir}"

    # Check if server.js exists
    if [ ! -f "${server_file}" ]; then
        bashio::log.error "server.js not found at ${server_file}"
        ls -la "${service_dir}"
        return 1
    fi

    # Check if node_modules exists
    if [ ! -d "${service_dir}/node_modules" ]; then
        bashio::log.error "node_modules not found in ${service_dir}"
        bashio::log.info "Attempting to install dependencies..."
        cd "${service_dir}" && npm install || bashio::log.error "npm install failed"
        cd - > /dev/null
    fi

    # Start with better error logging (run from current directory with absolute path)
    bashio::log.info "Starting Node.js service from ${server_file}..."
    node "${server_file}" 2>&1 | while IFS= read -r line; do
        bashio::log.info "[Image Service] $line"
    done &

    # Store the PID for potential cleanup
    local image_service_pid=$!
    bashio::log.info "Image service started (PID: ${image_service_pid})"

    # Give it a moment to start
    sleep 3

    # Check if it's running
    if kill -0 "${image_service_pid}" 2>/dev/null; then
        bashio::log.info "Image service is running successfully"
    else
        bashio::log.error "Image service failed to start! Check logs above for errors"
        return 1
    fi
}

# Start main web terminal
start_web_terminal() {
    local port=7681
    bashio::log.info "Starting web terminal on port ${port}..."

    # Log environment information for debugging
    bashio::log.info "Environment variables:"
    bashio::log.info "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR}"
    bashio::log.info "HOME=${HOME}"

    # Get the appropriate launch command based on configuration
    local launch_command
    launch_command=$(get_claude_launch_command)

    # Log the configuration being used
    local auto_launch_claude
    auto_launch_claude=$(bashio::config 'auto_launch_claude' 'true')
    bashio::log.info "Auto-launch Claude: ${auto_launch_claude}"

    # Start the image upload service first. It is non-critical: under `set -e`
    # a non-zero return here would abort the whole add-on before ttyd starts, so
    # guard it and continue with a terminal-only session if it fails.
    start_image_service || bashio::log.warning "Image upload service failed to start; continuing with terminal only"

    # Give the interactive terminal session persist-FIRST resolution — the mirror
    # of run.sh's system-first boot PATH. This runs AFTER the image service is
    # already spawned (so that root service stays on trusted system binaries) and
    # applies to ttyd and everything it launches: Claude and any shell the user
    # opens now prefer user-installed persistent packages and their libs.
    export PATH="/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin:$PATH"
    export LD_LIBRARY_PATH="/data/packages/lib:${LD_LIBRARY_PATH:-}"

    # Run ttyd with keepalive and reconnect configuration
    # --interface 127.0.0.1: bind to loopback ONLY. ttyd runs `--writable` with no
    #   credentials — a full root shell — so it must never be reachable off-box. The
    #   only client that needs it is the image-service proxy, which targets
    #   localhost:7681 from inside this same container. HA ingress reaches the
    #   terminal through that proxy (port 7680), which enforces ingress-origin.
    #   Direct in-container access (e.g. `docker exec`) is unaffected.
    # --ping-interval 30: WebSocket ping every 30s (default 300s) to prevent idle disconnects
    # --client-option reconnect=5: xterm.js auto-reconnect after 5 seconds on disconnect
    exec ttyd \
        --port "${port}" \
        --interface 127.0.0.1 \
        --writable \
        --ping-interval 30 \
        --client-option reconnect=5 \
        bash -c "$launch_command"
}

# Run health check
run_health_check() {
    if [ -f "/opt/scripts/health-check.sh" ]; then
        bashio::log.info "Running system health check..."
        chmod +x /opt/scripts/health-check.sh
        /opt/scripts/health-check.sh || bashio::log.warning "Some health checks failed but continuing..."
    fi
}

# Main execution
main() {
    bashio::log.info "Initializing Claude Code for Home Assistant add-on..."

    # Run diagnostics first (especially helpful for VirtualBox issues)
    run_health_check

    init_environment
    install_tools
    setup_session_picker
    setup_persistent_packages
    setup_ha_mcp
    setup_onboarding_hint
    start_web_terminal
}

# Execute main function
main "$@"